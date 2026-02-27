-- ============================================================
-- SESSIONS BY COUNTRY RANGE RPC: get_sessions_by_country_range
-- ============================================================
-- Returns session counts aggregated by country_code for a time range.
-- Used by Monetization v1.5 "Top Earning Countries" feature.
--
-- DEFINITIONS:
--   sessions = COUNT(DISTINCT session_hash) WHERE event_name = 'session_start'
--
-- PARAMETERS:
--   p_start_ts:     Start of window (inclusive, timestamptz ISO)
--   p_end_ts:       End of window (exclusive, timestamptz ISO)
--   p_region:       Filter by region (nullable) - e.g., 'Europe', 'North America'
--   p_country_code: Filter by specific country (nullable)
--   p_city_code:    Filter by city (nullable)
--   p_mode:         Filter by mode (nullable)
--
-- RETURNS:
--   country_code: Country code (e.g., 'NO', 'US', 'GB')
--   sessions:     Number of distinct sessions in that country
--
-- NOTE: Results ordered by sessions DESC (top countries first)
-- ============================================================

-- Drop existing versions
DROP FUNCTION IF EXISTS public.get_sessions_by_country_range(timestamptz, timestamptz, text, text, text, text);

-- ============================================================
-- CREATE FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_sessions_by_country_range(
  p_start_ts timestamptz,
  p_end_ts timestamptz,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL
)
RETURNS TABLE (
  country_code text,
  sessions bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    UPPER(TRIM(el.country_code)) AS country_code,
    COUNT(DISTINCT el.session_hash) AS sessions
  FROM public.event_logs el
  WHERE 
    -- Only count session_start events (consistent with engagement_flow)
    el.event_name = 'session_start'
    -- Time range filter
    AND el.created_at >= p_start_ts
    AND el.created_at < p_end_ts
    -- Country must exist
    AND el.country_code IS NOT NULL
    AND TRIM(el.country_code) <> ''
    -- Optional lens filters
    AND (p_region IS NULL OR UPPER(TRIM(el.region)) = UPPER(TRIM(p_region)))
    AND (p_country_code IS NULL OR UPPER(TRIM(el.country_code)) = UPPER(TRIM(p_country_code)))
    AND (p_city_code IS NULL OR UPPER(TRIM(el.city_code)) = UPPER(TRIM(p_city_code)))
    AND (p_mode IS NULL OR el.mode = p_mode)
  GROUP BY UPPER(TRIM(el.country_code))
  ORDER BY sessions DESC;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_sessions_by_country_range(timestamptz, timestamptz, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_sessions_by_country_range(timestamptz, timestamptz, text, text, text, text) TO authenticated;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST QUERIES
-- ============================================================

-- Test 1: All countries, last 7 days
SELECT '--- Sessions by country (last 7 days, all regions) ---' AS test;
SELECT * FROM public.get_sessions_by_country_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL, NULL, NULL, NULL
);

-- Test 2: Europe only, last 7 days
SELECT '--- Sessions by country (last 7 days, Europe only) ---' AS test;
SELECT * FROM public.get_sessions_by_country_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  'Europe', NULL, NULL, NULL
);

-- Test 3: All countries, last 30 days
SELECT '--- Sessions by country (last 30 days, all regions) ---' AS test;
SELECT * FROM public.get_sessions_by_country_range(
  NOW() - INTERVAL '30 days',
  NOW(),
  NULL, NULL, NULL, NULL
);

-- Test 4: North America only, last 30 days
SELECT '--- Sessions by country (last 30 days, North America only) ---' AS test;
SELECT * FROM public.get_sessions_by_country_range(
  NOW() - INTERVAL '30 days',
  NOW(),
  'North America', NULL, NULL, NULL
);
