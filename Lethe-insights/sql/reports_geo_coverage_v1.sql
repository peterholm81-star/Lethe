-- =============================================================================
-- RPC: get_reports_geo_coverage_v1
-- Returns geo data quality metrics (how much data has known region/city).
-- =============================================================================
--
-- PURPOSE:
--   Shows percentage of reports and reads that have valid geo data.
--   Helps explain why "Unknown" appears in Top Regions/Hotspots.
--
-- DEFINITIONS:
--   - "known" region: NOT NULL AND != '' AND != 'UNKNOWN' (case-insensitive)
--   - "known" city: NOT NULL AND != '' AND != 'UNKNOWN' (case-insensitive)
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_geo_coverage_v1(int, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v1(
  p_days int DEFAULT 7,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  total_reports int,
  known_region_reports int,
  known_city_reports int,
  known_country_reports int,
  known_region_reports_pct numeric,
  known_city_reports_pct numeric,
  known_country_reports_pct numeric,
  total_reads int,
  known_region_reads int,
  known_city_reads int,
  known_region_reads_pct numeric,
  known_city_reads_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  -- Reports
  v_total_reports int;
  v_known_region_reports int;
  v_known_city_reports int;
  v_known_country_reports int;
  -- Reads
  v_total_reads int;
  v_known_region_reads int;
  v_known_city_reads int;
BEGIN
  -- Auth check (admin only, but allow service context for SQL Editor testing)
  -- auth.uid() IS NULL in SQL Editor/service context → allow
  -- auth.uid() IS NOT NULL but not admin → deny
  IF auth.uid() IS NOT NULL AND NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Calculate time window
  v_start := now() - (p_days || ' days')::interval;

  -- ==========================================================================
  -- REPORTS COVERAGE
  -- Uses confession_reports columns directly (populated by trigger),
  -- with fallback to confessions table for older records.
  -- ==========================================================================
  
  -- Total reports in period (with geo filters if specified)
  SELECT COUNT(*)::int INTO v_total_reports
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (p_region IS NULL OR COALESCE(cr.region, c.region) = p_region)
    AND (p_city IS NULL OR COALESCE(cr.city_code, c.city_code) = p_city);
  
  -- Reports with known region (check cr.region first, then c.region)
  SELECT COUNT(*)::int INTO v_known_region_reports
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (p_region IS NULL OR COALESCE(cr.region, c.region) = p_region)
    AND (p_city IS NULL OR COALESCE(cr.city_code, c.city_code) = p_city)
    AND (
      (cr.region IS NOT NULL AND TRIM(cr.region) != '' AND UPPER(TRIM(cr.region)) != 'UNKNOWN')
      OR (c.region IS NOT NULL AND TRIM(c.region) != '' AND UPPER(TRIM(c.region)) != 'UNKNOWN')
    );
  
  -- Reports with known city (check cr.city_code first, then c.city_code)
  SELECT COUNT(*)::int INTO v_known_city_reports
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (p_region IS NULL OR COALESCE(cr.region, c.region) = p_region)
    AND (p_city IS NULL OR COALESCE(cr.city_code, c.city_code) = p_city)
    AND (
      (cr.city_code IS NOT NULL AND TRIM(cr.city_code) != '' AND UPPER(TRIM(cr.city_code)) != 'UNKNOWN')
      OR (c.city_code IS NOT NULL AND TRIM(c.city_code) != '' AND UPPER(TRIM(c.city_code)) != 'UNKNOWN')
    );

  -- Reports with known country (check cr.country_code first, then c.country_code)
  SELECT COUNT(*)::int INTO v_known_country_reports
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (p_region IS NULL OR COALESCE(cr.region, c.region) = p_region)
    AND (p_city IS NULL OR COALESCE(cr.city_code, c.city_code) = p_city)
    AND (
      (cr.country_code IS NOT NULL AND TRIM(cr.country_code) != '' AND UPPER(TRIM(cr.country_code)) != 'UNKNOWN')
      OR (c.country_code IS NOT NULL AND TRIM(c.country_code) != '' AND UPPER(TRIM(c.country_code)) != 'UNKNOWN')
    );

  -- ==========================================================================
  -- READS COVERAGE (from event_logs page_fetch events)
  -- ==========================================================================
  
  -- Total reads in period
  SELECT COUNT(DISTINCT session_hash)::int INTO v_total_reads
  FROM event_logs el
  WHERE el.event_name = 'page_fetch'
    AND el.created_at >= v_start
    AND (p_region IS NULL OR el.region = p_region)
    AND (p_city IS NULL OR el.city_code = p_city);
  
  -- Reads with known region
  SELECT COUNT(DISTINCT session_hash)::int INTO v_known_region_reads
  FROM event_logs el
  WHERE el.event_name = 'page_fetch'
    AND el.created_at >= v_start
    AND (p_region IS NULL OR el.region = p_region)
    AND (p_city IS NULL OR el.city_code = p_city)
    AND el.region IS NOT NULL 
    AND TRIM(el.region) != ''
    AND UPPER(TRIM(el.region)) != 'UNKNOWN';
  
  -- Reads with known city
  SELECT COUNT(DISTINCT session_hash)::int INTO v_known_city_reads
  FROM event_logs el
  WHERE el.event_name = 'page_fetch'
    AND el.created_at >= v_start
    AND (p_region IS NULL OR el.region = p_region)
    AND (p_city IS NULL OR el.city_code = p_city)
    AND el.city_code IS NOT NULL 
    AND TRIM(el.city_code) != ''
    AND UPPER(TRIM(el.city_code)) != 'UNKNOWN';

  -- ==========================================================================
  -- RETURN
  -- ==========================================================================
  RETURN QUERY SELECT
    v_total_reports,
    v_known_region_reports,
    v_known_city_reports,
    v_known_country_reports,
    CASE WHEN v_total_reports > 0 
      THEN ROUND((v_known_region_reports::numeric / v_total_reports) * 100, 1)
      ELSE NULL
    END AS known_region_reports_pct,
    CASE WHEN v_total_reports > 0 
      THEN ROUND((v_known_city_reports::numeric / v_total_reports) * 100, 1)
      ELSE NULL
    END AS known_city_reports_pct,
    CASE WHEN v_total_reports > 0 
      THEN ROUND((v_known_country_reports::numeric / v_total_reports) * 100, 1)
      ELSE NULL
    END AS known_country_reports_pct,
    v_total_reads,
    v_known_region_reads,
    v_known_city_reads,
    CASE WHEN v_total_reads > 0 
      THEN ROUND((v_known_region_reads::numeric / v_total_reads) * 100, 1)
      ELSE NULL
    END AS known_region_reads_pct,
    CASE WHEN v_total_reads > 0 
      THEN ROUND((v_known_city_reads::numeric / v_total_reads) * 100, 1)
      ELSE NULL
    END AS known_city_reads_pct;
END;
$$;

-- Grant execute to authenticated users (admin check is in function)
GRANT EXECUTE ON FUNCTION public.get_reports_geo_coverage_v1(int, text, text, text) TO authenticated;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_geo_coverage_v1(7, NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_geo_coverage_v1(30, 'Europe', NULL, NULL);

-- =============================================================================
-- VERIFICATION: Test that function works in SQL Editor
-- =============================================================================
-- After deploying, run this in Supabase SQL Editor:
-- SELECT * FROM public.get_reports_geo_coverage_v1(7, NULL, NULL, NULL);
-- Should return a row with total_reports, known_region_reports, etc.
-- (No "Access denied" error)

-- =============================================================================
-- VERIFICATION: Compare RPC output with direct query
-- =============================================================================
/*
-- Run this to verify country_pct matches:
WITH report_stats AS (
  SELECT 
    COUNT(*)::int AS total_reports,
    COUNT(*) FILTER (WHERE 
      cr.country_code IS NOT NULL 
      AND TRIM(cr.country_code) != '' 
      AND UPPER(TRIM(cr.country_code)) != 'UNKNOWN'
    )::int AS known_country_reports
  FROM confession_reports cr
  WHERE cr.created_at >= now() - interval '7 days'
)
SELECT 
  total_reports,
  known_country_reports,
  CASE WHEN total_reports > 0 
    THEN ROUND((known_country_reports::numeric / total_reports) * 100, 1)
    ELSE NULL
  END AS country_pct_manual
FROM report_stats;

-- Compare with RPC:
SELECT 
  total_reports,
  known_country_reports,
  known_country_reports_pct
FROM public.get_reports_geo_coverage_v1(7, NULL, NULL, NULL);
*/
