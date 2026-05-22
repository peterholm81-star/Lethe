-- =============================================================================
-- Migration 041: Harden public.get_reports_outcomes_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_outcomes_v1 with
--   a production-safe, admin-gated aggregate read RPC.
--
--   This RPC returns a single-row aggregate of moderation resolution outcomes:
--   actioned, handled, hidden, dismissed, and escalated report counts, plus
--   percentage rates for each. This is operational moderation intelligence and
--   must remain visible only to authenticated Insights admins.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); the frontend hook
--     (useReportsOutcomes.ts lines 120-129) handles an empty array gracefully,
--     rendering zero-value defaults without errors
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Language changed from sql to plpgsql to support the admin gate;
--     all CTEs, query logic, return columns, order, and types are preserved
--     exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_outcomes_v1
--   - Same parameters with same defaults:
--       p_days    integer DEFAULT 7
--       p_region  text    DEFAULT NULL
--       p_country text    DEFAULT NULL
--       p_city    text    DEFAULT NULL
--   - Same return columns (one aggregate row):
--       actioned_reports   bigint
--       handled_reports    bigint
--       hidden_reports     bigint
--       dismissed_reports  bigint
--       escalated_reports  bigint
--       handled_rate_pct   numeric
--       hidden_rate_pct    numeric
--       dismissed_rate_pct numeric
--       escalated_rate_pct numeric
--   - Frontend (useReportsOutcomes.ts) handles empty result with zero defaults
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_outcomes_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  actioned_reports   BIGINT,
  handled_reports    BIGINT,
  hidden_reports     BIGINT,
  dismissed_reports  BIGINT,
  escalated_reports  BIGINT,
  handled_rate_pct   NUMERIC,
  hidden_rate_pct    NUMERIC,
  dismissed_rate_pct NUMERIC,
  escalated_rate_pct NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — moderation outcome metrics
  -- must not be visible outside the admin boundary.
  -- The frontend handles an empty result with zero-value defaults.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH r AS (
    SELECT r.*, c.region, c.country_code, c.city_code, c.is_hidden
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
  ),
  a AS (
    SELECT
      count(*)                                                                          AS total,
      count(*) FILTER (WHERE status = 'actioned')                                      AS actioned,
      count(*) FILTER (WHERE handled OR status <> 'open')                              AS handled_count,
      count(*) FILTER (WHERE COALESCE(is_hidden, false))                               AS hidden,
      count(*) FILTER (WHERE status = 'dismissed')                                     AS dismissed,
      count(*) FILTER (WHERE status = 'open' AND created_at < now() - INTERVAL '12 hours') AS escalated
    FROM r
  )
  SELECT
    actioned,
    handled_count,
    hidden,
    dismissed,
    escalated,
    CASE WHEN total > 0 THEN handled_count * 100.0 / total ELSE 0 END,
    CASE WHEN total > 0 THEN hidden       * 100.0 / total ELSE 0 END,
    CASE WHEN total > 0 THEN dismissed    * 100.0 / total ELSE 0 END,
    CASE WHEN total > 0 THEN escalated    * 100.0 / total ELSE 0 END
  FROM a;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read moderation outcome metrics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_outcomes_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_outcomes_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_outcomes_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;
