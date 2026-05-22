-- =============================================================================
-- Migration 040: Harden public.get_reports_overview_v2
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_overview_v2 with
--   a production-safe, admin-gated aggregate read RPC.
--
--   This RPC returns a single-row aggregate of time-windowed moderation
--   workload metrics: report volume, reports-per-1k-reads ratio, hidden count,
--   severity score, spike detection flag, and moderation action count. This is
--   operational admin intelligence and must not be visible outside the admin
--   boundary.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); the frontend
--     (ReportsPage.tsx lines 856-866) handles an empty array gracefully,
--     rendering safe defaults (0, null, false) without errors
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Language changed from sql to plpgsql to support the admin gate;
--     all CTEs, query logic, return columns, order, and types are preserved
--     exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_overview_v2
--   - Same parameters with same defaults:
--       p_range   text DEFAULT '7d'
--       p_region  text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city    text DEFAULT NULL
--   - Same return columns (one aggregate row):
--       reports_total        bigint
--       reports_per_1k_reads numeric
--       hidden_total         bigint
--       severity_score       numeric
--       spike_detected       boolean
--       actions_total        bigint
--   - Frontend (ReportsPage.tsx) handles empty result with safe zero defaults
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_overview_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  reports_total        BIGINT,
  reports_per_1k_reads NUMERIC,
  hidden_total         BIGINT,
  severity_score       NUMERIC,
  spike_detected       BOOLEAN,
  actions_total        BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — moderation workload metrics
  -- must not be visible outside the admin boundary.
  -- The frontend handles an empty result with safe zero/null/false defaults.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH params AS (
    SELECT public._lethe_reports_range_days(p_range) AS days
  ),
  reports_filtered AS (
    SELECT r.*, c.region, c.country_code, c.city_code, c.is_hidden
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    CROSS JOIN params p
    WHERE r.created_at >= now() - make_interval(days => p.days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
  ),
  reads AS (
    SELECT count(*) AS reads_count
    FROM public.event_logs e
    CROSS JOIN params p
    WHERE e.created_at >= now() - make_interval(days => p.days)
      AND e.event_name IN ('feed_view', 'page_fetch')
      AND (p_region  IS NULL OR e.region       = p_region)
      AND (p_country IS NULL OR e.country_code = p_country)
      AND (p_city    IS NULL OR e.city_code    = p_city)
  ),
  actions AS (
    SELECT count(*) AS actions_count
    FROM public.moderation_actions a
    LEFT JOIN public.confessions c ON c.id = a.confession_id
    CROSS JOIN params p
    WHERE a.created_at >= now() - make_interval(days => p.days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
  ),
  totals AS (
    SELECT
      count(*)                                                              AS reports_count,
      count(*) FILTER (WHERE COALESCE(is_hidden, false))                   AS hidden_count,
      count(*) FILTER (WHERE reason IN ('threats', 'identifying', 'contact')) AS severe_count
    FROM reports_filtered
  )
  SELECT
    totals.reports_count,
    CASE WHEN reads.reads_count > 0
         THEN totals.reports_count * 1000.0 / reads.reads_count
         ELSE NULL
    END,
    totals.hidden_count,
    CASE WHEN totals.reports_count > 0
         THEN ROUND(totals.severe_count * 100.0 / totals.reports_count, 2)
         ELSE 0
    END,
    totals.reports_count > 50,
    actions.actions_count
  FROM totals, reads, actions;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read moderation workload metrics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_overview_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_overview_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_overview_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_reports_overview_v2();
--    -- Expected: ERROR 42501 permission denied for function
--
-- 2. Authenticated non-admin receives zero rows:
--    SELECT count(*) FROM public.get_reports_overview_v2();
--    -- Expected: 0
--
-- 3. Authenticated admin receives one aggregate row:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    SELECT * FROM public.get_reports_overview_v2('30d');
--    -- Expected: 1 row with totals > 0
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
