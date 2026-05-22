-- =============================================================================
-- Migration 042: Harden public.get_reports_sla_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_sla_v1 with a
--   production-safe, admin-gated aggregate read RPC.
--
--   This migration also fixes a pre-existing shape mismatch: the old DB function
--   returned (avg_hours_to_handle, p95_hours_to_handle, overdue_open) but the
--   frontend hook (useReportsSla.ts) has always expected a different 5-column
--   shape (median_minutes, p90_minutes, oldest_pending_minutes, actioned_reports,
--   pending_reports). The old columns were never consumed by the frontend — all
--   SLA fields were silently null in the dashboard. This migration corrects both
--   the security posture and the contract in a single isolated step.
--
-- Shape changes (pre-existing mismatch, not a new regression):
--   Old (unused by frontend): avg_hours_to_handle numeric,
--                              p95_hours_to_handle numeric,
--                              overdue_open bigint
--   New (what frontend expects):
--     median_minutes          numeric  -- median resolution time (minutes), nullable
--     p90_minutes             numeric  -- 90th-pct resolution time (minutes), nullable
--     oldest_pending_minutes  numeric  -- age of oldest open report (minutes), nullable
--     actioned_reports        bigint   -- reports that are handled or non-open
--     pending_reports         bigint   -- reports still open
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); the frontend hook
--     (useReportsSla.ts lines 113-121) handles an empty array gracefully,
--     rendering null/0 defaults without errors
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--
-- Frontend contract (useReportsSla.ts):
--   - Same name: get_reports_sla_v1
--   - Same parameters with same defaults:
--       p_days    integer DEFAULT 7
--       p_region  text    DEFAULT NULL
--       p_country text    DEFAULT NULL
--       p_city    text    DEFAULT NULL
--   - Corrected return columns matching frontend expectations:
--       median_minutes          numeric (nullable — null when no resolved reports)
--       p90_minutes             numeric (nullable — null when no resolved reports)
--       oldest_pending_minutes  numeric (nullable — null when no open reports)
--       actioned_reports        bigint
--       pending_reports         bigint
-- =============================================================================

-- DROP the old function first because the return columns change (shape fix).
-- The old shape (avg_hours_to_handle, p95_hours_to_handle, overdue_open) was
-- never consumed by the frontend — all SLA fields were always null. Dropping
-- and recreating is safe; no downstream callers depend on the old columns.
DROP FUNCTION IF EXISTS public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_reports_sla_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  median_minutes         NUMERIC,
  p90_minutes            NUMERIC,
  oldest_pending_minutes NUMERIC,
  actioned_reports       BIGINT,
  pending_reports        BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — SLA/moderation timing metrics
  -- must not be visible outside the admin boundary.
  -- The frontend handles an empty result with null/0 defaults.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH r AS (
    SELECT r.*, c.region, c.country_code, c.city_code
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
  )
  SELECT
    -- Median resolution time in minutes (null when no resolved reports in window)
    -- Cast to numeric: percentile_cont returns double precision
    (percentile_cont(0.50) WITHIN GROUP (
      ORDER BY EXTRACT(EPOCH FROM (handled_at - created_at)) / 60
    ) FILTER (WHERE handled_at IS NOT NULL))::NUMERIC,

    -- 90th-percentile resolution time in minutes
    (percentile_cont(0.90) WITHIN GROUP (
      ORDER BY EXTRACT(EPOCH FROM (handled_at - created_at)) / 60
    ) FILTER (WHERE handled_at IS NOT NULL))::NUMERIC,

    -- Age of the oldest still-open report in minutes (null when none are open)
    -- Cast to numeric: EXTRACT returns double precision
    (EXTRACT(EPOCH FROM (now() - min(created_at) FILTER (WHERE status = 'open'))) / 60)::NUMERIC,

    -- Reports that have been actioned (handled or moved out of open state)
    count(*) FILTER (WHERE handled OR status <> 'open'),

    -- Reports still pending/open
    count(*) FILTER (WHERE status = 'open')
  FROM r;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read SLA or moderation timing metrics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;
