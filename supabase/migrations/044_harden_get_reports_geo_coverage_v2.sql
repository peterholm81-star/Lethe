-- =============================================================================
-- Migration 044: Harden public.get_reports_geo_coverage_v2
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_geo_coverage_v2
--   with a production-safe, admin-gated aggregate read RPC.
--
--   This RPC returns a single-row aggregate of geo coverage quality across
--   reports in a time window: totals, backfillable/ungeocodable split, and
--   per-dimension (region/city/country) coverage counts and percentages.
--   It is operational admin analytics and must remain admin-only.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); the frontend hook
--     (useReportsGeoCoverage.ts line 134) handles an empty array gracefully,
--     rendering null coverage state without errors
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Language changed from sql to plpgsql to support the admin gate;
--     all CTEs, query logic, return columns, order, and types are preserved
--     exactly
--
-- Frontend contract preserved (useReportsGeoCoverage.ts):
--   - Same name: get_reports_geo_coverage_v2
--   - Same parameters with same defaults:
--       p_days         integer DEFAULT 7
--       p_region       text    DEFAULT NULL
--       p_country_code text    DEFAULT NULL
--       p_city_code    text    DEFAULT NULL
--   - Same return columns (one aggregate row, all 9 columns match frontend):
--       total_reports         bigint
--       backfillable_reports  bigint
--       ungeocodable_reports  bigint
--       region_covered        bigint
--       city_covered          bigint
--       country_covered       bigint
--       region_pct            numeric
--       city_pct              numeric
--       country_pct           numeric
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v2(
  p_days         INTEGER DEFAULT 7,
  p_region       TEXT    DEFAULT NULL,
  p_country_code TEXT    DEFAULT NULL,
  p_city_code    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  total_reports        BIGINT,
  backfillable_reports BIGINT,
  ungeocodable_reports BIGINT,
  region_covered       BIGINT,
  city_covered         BIGINT,
  country_covered      BIGINT,
  region_pct           NUMERIC,
  city_pct             NUMERIC,
  country_pct          NUMERIC
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
  -- The frontend handles an empty result by setting coverage to null.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH r AS (
    SELECT r.*, c.region, c.country_code, c.city_code
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region       IS NULL OR c.region       = p_region)
      AND (p_country_code IS NULL OR c.country_code = p_country_code)
      AND (p_city_code    IS NULL OR c.city_code    = p_city_code)
  ),
  a AS (
    SELECT
      count(*)                                              AS total,
      count(*) FILTER (WHERE confession_id IS NOT NULL)    AS backfillable,
      count(*) FILTER (WHERE confession_id IS NULL)        AS ungeocodable,
      count(*) FILTER (WHERE region       IS NOT NULL)     AS region_count,
      count(*) FILTER (WHERE city_code    IS NOT NULL)     AS city_count,
      count(*) FILTER (WHERE country_code IS NOT NULL)     AS country_count
    FROM r
  )
  SELECT
    total,
    backfillable,
    ungeocodable,
    region_count,
    city_count,
    country_count,
    CASE WHEN backfillable > 0 THEN region_count  * 100.0 / backfillable ELSE 0 END,
    CASE WHEN backfillable > 0 THEN city_count    * 100.0 / backfillable ELSE 0 END,
    CASE WHEN backfillable > 0 THEN country_count * 100.0 / backfillable ELSE 0 END
  FROM a;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read geo coverage analytics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_geo_coverage_v2(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(INTEGER, TEXT, TEXT, TEXT) TO authenticated;
