-- =============================================================================
-- Migration 039: Harden public.get_reports_overview
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_overview with a
--   production-safe, admin-gated aggregate read RPC.
--
--   This RPC returns a single-row aggregate summary of moderation workload:
--   total confession count, total report count, total unhandled report count,
--   and a per-reason breakdown as JSONB. This is operational admin intelligence
--   and must not be visible outside the admin boundary.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); the frontend hook
--     (useReportsOverview.ts lines 116-132) handles an empty array gracefully
--     and renders EMPTY_OVERVIEW (all zeros) without errors
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Language changed from sql to plpgsql to support the admin gate;
--     all query logic, CTEs, return columns, and ordering are preserved exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_overview
--   - Same parameters with same defaults:
--       p_only_unhandled boolean DEFAULT true
--       p_reason         text    DEFAULT NULL
--       p_visibility     text    DEFAULT NULL
--   - Same return columns (one aggregate row):
--       total_confessions       bigint
--       total_reports           bigint
--       total_unhandled_reports bigint
--       reasons_json            jsonb
--   - Frontend (useReportsOverview.ts) handles empty result via EMPTY_OVERVIEW
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_overview(
  p_only_unhandled BOOLEAN DEFAULT true,
  p_reason         TEXT    DEFAULT NULL,
  p_visibility     TEXT    DEFAULT NULL
)
RETURNS TABLE(
  total_confessions       BIGINT,
  total_reports           BIGINT,
  total_unhandled_reports BIGINT,
  reasons_json            JSONB
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
  -- The frontend hook handles an empty result gracefully via EMPTY_OVERVIEW.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH filtered AS (
    SELECT r.*, c.is_hidden
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE (p_reason      IS NULL OR r.reason = p_reason)
      AND (p_visibility  IS NULL
           OR (p_visibility = 'hidden'  AND     COALESCE(c.is_hidden, false))
           OR (p_visibility = 'visible' AND NOT COALESCE(c.is_hidden, false)))
      AND (NOT p_only_unhandled OR r.status = 'open')
  ), reasons AS (
    SELECT COALESCE(jsonb_object_agg(reason, cnt), '{}'::jsonb) AS j
    FROM (SELECT reason, count(*) AS cnt FROM filtered GROUP BY reason) x
  )
  SELECT
    (SELECT count(*) FROM public.confessions),
    (SELECT count(*) FROM filtered),
    (SELECT count(*) FROM filtered WHERE status = 'open'),
    reasons.j
  FROM reasons;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read moderation workload metrics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_overview(BOOLEAN, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_overview(BOOLEAN, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_overview(BOOLEAN, TEXT, TEXT) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_reports_overview();
--    -- Expected: ERROR 42501 permission denied for function
--
-- 2. Authenticated non-admin receives zero rows:
--    -- (role change only, no jwt claims set)
--    SELECT count(*) FROM public.get_reports_overview();
--    -- Expected: 0
--
-- 3. Authenticated admin receives one aggregate row:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    SELECT * FROM public.get_reports_overview();
--    -- Expected: 1 row with totals > 0
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
