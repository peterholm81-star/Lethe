-- =============================================================================
-- Insights Filter Options RPCs
-- =============================================================================
-- Lightweight functions to get distinct filter values for dropdowns
-- =============================================================================

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS public.get_insights_country_options();
DROP FUNCTION IF EXISTS public.get_insights_country_options(text);
DROP FUNCTION IF EXISTS public.get_insights_region_options();
DROP FUNCTION IF EXISTS public.get_insights_city_options(text, text);

-- =============================================================================
-- get_insights_country_options(p_region)
-- Returns distinct country_code values from event_logs
-- Optionally filtered by region for cascading filters
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_insights_country_options(
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE (country_code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT UPPER(TRIM(el.country_code)) AS country_code
  FROM public.event_logs el
  WHERE el.country_code IS NOT NULL
    AND TRIM(el.country_code) <> ''
    -- Filter by region if provided (case-insensitive, trimmed)
    AND (p_region IS NULL OR UPPER(TRIM(el.region)) = UPPER(TRIM(p_region)))
  ORDER BY country_code ASC;
$$;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION public.get_insights_country_options(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_insights_country_options(text) TO anon;

-- =============================================================================
-- get_insights_region_options()
-- Returns distinct region values from event_logs
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_insights_region_options()
RETURNS TABLE (region TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT TRIM(el.region) AS region
  FROM public.event_logs el
  WHERE el.region IS NOT NULL
    AND TRIM(el.region) <> ''
  ORDER BY region ASC;
$$;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION public.get_insights_region_options() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_insights_region_options() TO anon;

-- =============================================================================
-- get_insights_city_options(p_country_code, p_region)
-- Returns distinct city_code values from event_logs
-- Optionally filtered by country_code and/or region
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_insights_city_options(
  p_country_code TEXT DEFAULT NULL,
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE (city_code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT UPPER(TRIM(el.city_code)) AS city_code
  FROM public.event_logs el
  WHERE el.city_code IS NOT NULL
    AND TRIM(el.city_code) <> ''
    -- Filter by country if provided (case-insensitive)
    AND (p_country_code IS NULL OR UPPER(TRIM(el.country_code)) = UPPER(TRIM(p_country_code)))
    -- Filter by region if provided (case-insensitive, trimmed)
    AND (p_region IS NULL OR UPPER(TRIM(el.region)) = UPPER(TRIM(p_region)))
  ORDER BY city_code ASC;
$$;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION public.get_insights_city_options(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_insights_city_options(text, text) TO anon;

-- =============================================================================
-- Test queries
-- =============================================================================
SELECT '--- Region options ---' AS test;
SELECT * FROM public.get_insights_region_options();

SELECT '--- Country options (all) ---' AS test;
SELECT * FROM public.get_insights_country_options();

SELECT '--- Country options (Europe only) ---' AS test;
SELECT * FROM public.get_insights_country_options('Europe');

SELECT '--- Country options (North America only) ---' AS test;
SELECT * FROM public.get_insights_country_options('North America');

SELECT '--- City options (all) ---' AS test;
SELECT * FROM public.get_insights_city_options();

SELECT '--- City options (US only) ---' AS test;
SELECT * FROM public.get_insights_city_options('US', NULL);

SELECT '--- City options (Europe region only) ---' AS test;
SELECT * FROM public.get_insights_city_options(NULL, 'Europe');
