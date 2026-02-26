-- =============================================================================
-- RPC: get_reports_geo_coverage_v2
-- =============================================================================
--
-- PURPOSE:
--   Returns honest geo coverage metrics that distinguish between:
--   - Backfillable reports (confession has lat/lng, geo CAN be derived)
--   - Ungeocodable reports (confession lacks lat/lng, geo CANNOT be derived)
--
-- DEFINITIONS:
--   - backfillable_report: report where joined confession has lat IS NOT NULL AND lng IS NOT NULL
--   - ungeocodable_report: report where joined confession has lat IS NULL OR lng IS NULL
--   - Coverage percentages are calculated ONLY from backfillable_reports
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_geo_coverage_v2(integer, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v2(
  p_days integer DEFAULT 7,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL
)
RETURNS TABLE (
  total_reports integer,
  backfillable_reports integer,
  ungeocodable_reports integer,
  region_covered integer,
  city_covered integer,
  country_covered integer,
  region_pct numeric,
  city_pct numeric,
  country_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_total integer;
  v_backfillable integer;
  v_ungeocodable integer;
  v_region_covered integer;
  v_city_covered integer;
  v_country_covered integer;
BEGIN
  -- Auth check: allow service context (SQL Editor) OR admin users
  -- Explicitly handle NULL first to avoid is_admin(NULL) issues
  IF auth.uid() IS NULL THEN
    -- Service context (SQL Editor, postgres superuser) - allow
    NULL; -- no-op, proceed
  ELSIF NOT COALESCE(is_admin(auth.uid()), FALSE) THEN
    -- Authenticated but not admin - deny
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Calculate time window
  v_start := now() - (p_days || ' days')::interval;

  -- ==========================================================================
  -- TOTAL REPORTS (with filters)
  -- p_region = NULL → no filter (all regions)
  -- p_region = 'Unknown' → match NULL/empty/UNKNOWN
  -- p_region = 'Europe' etc → exact match
  -- ==========================================================================
  SELECT COUNT(*)::integer INTO v_total
  FROM confession_reports cr
  WHERE cr.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND cr.region = p_region)
    )
    AND (p_country_code IS NULL OR cr.country_code = p_country_code)
    AND (p_city_code IS NULL OR cr.city_code = p_city_code);

  -- ==========================================================================
  -- BACKFILLABLE REPORTS (confession has lat/lng)
  -- ==========================================================================
  SELECT COUNT(*)::integer INTO v_backfillable
  FROM confession_reports cr
  JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND c.lat IS NOT NULL
    AND c.lng IS NOT NULL
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND cr.region = p_region)
    )
    AND (p_country_code IS NULL OR cr.country_code = p_country_code)
    AND (p_city_code IS NULL OR cr.city_code = p_city_code);

  -- ==========================================================================
  -- UNGEOCODABLE REPORTS (confession lacks lat/lng or doesn't exist)
  -- ==========================================================================
  SELECT COUNT(*)::integer INTO v_ungeocodable
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (c.id IS NULL OR c.lat IS NULL OR c.lng IS NULL)
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND cr.region = p_region)
    )
    AND (p_country_code IS NULL OR cr.country_code = p_country_code)
    AND (p_city_code IS NULL OR cr.city_code = p_city_code);

  -- ==========================================================================
  -- REGION COVERAGE (within backfillable only)
  -- ==========================================================================
  SELECT COUNT(*)::integer INTO v_region_covered
  FROM confession_reports cr
  JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND c.lat IS NOT NULL
    AND c.lng IS NOT NULL
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND cr.region = p_region)
    )
    AND (p_country_code IS NULL OR cr.country_code = p_country_code)
    AND (p_city_code IS NULL OR cr.city_code = p_city_code)
    AND cr.region IS NOT NULL
    AND TRIM(cr.region) != ''
    AND UPPER(TRIM(cr.region)) != 'UNKNOWN';

  -- ==========================================================================
  -- CITY COVERAGE (within backfillable only)
  -- ==========================================================================
  SELECT COUNT(*)::integer INTO v_city_covered
  FROM confession_reports cr
  JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND c.lat IS NOT NULL
    AND c.lng IS NOT NULL
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND cr.region = p_region)
    )
    AND (p_country_code IS NULL OR cr.country_code = p_country_code)
    AND (p_city_code IS NULL OR cr.city_code = p_city_code)
    AND cr.city_code IS NOT NULL
    AND TRIM(cr.city_code) != ''
    AND UPPER(TRIM(cr.city_code)) != 'UNKNOWN';

  -- ==========================================================================
  -- COUNTRY COVERAGE (within backfillable only, uses country_code)
  -- ==========================================================================
  SELECT COUNT(*)::integer INTO v_country_covered
  FROM confession_reports cr
  JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND c.lat IS NOT NULL
    AND c.lng IS NOT NULL
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND cr.region = p_region)
    )
    AND (p_country_code IS NULL OR cr.country_code = p_country_code)
    AND (p_city_code IS NULL OR cr.city_code = p_city_code)
    AND cr.country_code IS NOT NULL
    AND TRIM(cr.country_code) != ''
    AND UPPER(TRIM(cr.country_code)) != 'UNKNOWN';

  -- ==========================================================================
  -- RETURN
  -- ==========================================================================
  RETURN QUERY SELECT
    v_total,
    v_backfillable,
    v_ungeocodable,
    v_region_covered,
    v_city_covered,
    v_country_covered,
    -- Percentages based on backfillable_reports (not total)
    CASE WHEN v_backfillable > 0 
      THEN ROUND((v_region_covered::numeric / v_backfillable) * 100, 1)
      ELSE 0::numeric
    END,
    CASE WHEN v_backfillable > 0 
      THEN ROUND((v_city_covered::numeric / v_backfillable) * 100, 1)
      ELSE 0::numeric
    END,
    CASE WHEN v_backfillable > 0 
      THEN ROUND((v_country_covered::numeric / v_backfillable) * 100, 1)
      ELSE 0::numeric
    END;
END;
$$;

-- Grant execute (admin check is in function)
GRANT EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(integer, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(integer, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(integer, text, text, text) TO service_role;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- VERIFICATION QUERY
-- =============================================================================
-- Run this after deploying to verify:
/*
SELECT * FROM public.get_reports_geo_coverage_v2(30, NULL, NULL, NULL);

-- Expected output (example):
-- total_reports: 15
-- backfillable_reports: 4
-- ungeocodable_reports: 11
-- region_covered: 4
-- city_covered: 4
-- country_covered: 4
-- region_pct: 100.0
-- city_pct: 100.0
-- country_pct: 100.0

-- Compare with raw data:
SELECT 
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE c.lat IS NOT NULL AND c.lng IS NOT NULL) AS backfillable,
  COUNT(*) FILTER (WHERE c.lat IS NULL OR c.lng IS NULL) AS ungeocodable
FROM confession_reports cr
LEFT JOIN confessions c ON c.id = cr.confession_id
WHERE cr.created_at >= now() - interval '30 days';
*/
