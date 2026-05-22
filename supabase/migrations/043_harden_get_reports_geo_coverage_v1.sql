-- =============================================================================
-- Migration 043: Harden public.get_reports_geo_coverage_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_geo_coverage_v1
--   with a production-safe, admin-gated aggregate read RPC.
--
--   This RPC returns a single-row aggregate of how many reports have geographic
--   data attached (country_code or city_code), plus the coverage percentage.
--   It is moderation/operational analytics and must remain admin-only.
--
--   NOTE: As of this migration, no frontend hook calls this RPC. It exists in
--   the DB from the dev seed but is not yet wired to any Insights dashboard
--   page. It is hardened now so it is production-safe before being connected.
--   No local runtime shim restoration is needed (nothing calls it anonymously).
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Language changed from sql to plpgsql to support the admin gate;
--     all CTEs, query logic, return columns, order, and types are preserved
--     exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_geo_coverage_v1
--   - Same parameters with same defaults:
--       p_days    integer DEFAULT 7
--       p_region  text    DEFAULT NULL
--       p_country text    DEFAULT NULL
--       p_city    text    DEFAULT NULL
--   - Same return columns (one aggregate row):
--       total_reports    bigint
--       reports_with_geo bigint
--       geo_coverage_pct numeric
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  total_reports    BIGINT,
  reports_with_geo BIGINT,
  geo_coverage_pct NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — geo coverage analytics
  -- must not be visible outside the admin boundary.
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
  ),
  a AS (
    SELECT
      count(*)                                                                    AS total,
      count(*) FILTER (WHERE city_code IS NOT NULL OR country_code IS NOT NULL)  AS with_geo
    FROM r
  )
  SELECT
    total,
    with_geo,
    CASE WHEN total > 0 THEN with_geo * 100.0 / total ELSE 0 END
  FROM a;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read geo coverage analytics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_geo_coverage_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_geo_coverage_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_geo_coverage_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;
