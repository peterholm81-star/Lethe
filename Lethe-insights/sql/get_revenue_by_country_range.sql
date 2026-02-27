-- ============================================================
-- REVENUE BY COUNTRY RANGE RPC: get_revenue_by_country_range
-- ============================================================
-- Returns revenue metrics aggregated by country_code for a time range.
-- Used by Monetization "Revenue Map" feature.
--
-- CURRENT BEHAVIOR (v1):
--   Since event_logs does not yet contain actual revenue values,
--   this function returns:
--   - sessions: from session_start events (actual data)
--   - ad_impressions: count of ad_shown events (proxy for impressions)
--   - ad_revenue: 0 (placeholder until we track actual revenue)
--   - premium_revenue: 0 (placeholder for future premium tracking)
--   - revenue_total: ad_revenue + premium_revenue
--   - revenue_per_session: revenue_total / sessions
--
-- FUTURE ENHANCEMENT:
--   When revenue events are added (e.g., 'ad_revenue' with metadata->>'revenue'),
--   update the ad_revenue calculation to sum actual values.
--
-- PARAMETERS:
--   p_start:  Start of window (inclusive, timestamptz)
--   p_end:    End of window (exclusive, timestamptz)
--   p_region: Filter by region (nullable) - e.g., 'Europe', 'North America'
--             If NULL or 'all' (case-insensitive), returns all regions.
--
-- RETURNS:
--   country_code:       Country code (e.g., 'NO', 'US', 'GB')
--   sessions:           Number of distinct sessions
--   ad_impressions:     Count of ad_shown events (proxy for impressions)
--   revenue_total:      Total revenue (ad + premium)
--   ad_revenue:         Revenue from ads
--   premium_revenue:    Revenue from premium (placeholder: 0)
--   revenue_per_session: revenue_total / sessions
--
-- NOTE: Results ordered by sessions DESC (top countries first)
-- ============================================================

-- Drop existing versions (for clean re-runs during development)
DROP FUNCTION IF EXISTS public.get_revenue_by_country_range(timestamptz, timestamptz, text);

-- ============================================================
-- CREATE FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_revenue_by_country_range(
  p_start timestamptz,
  p_end timestamptz,
  p_region text DEFAULT NULL
)
RETURNS TABLE (
  country_code text,
  sessions bigint,
  ad_impressions bigint,
  revenue_total numeric,
  ad_revenue numeric,
  premium_revenue numeric,
  revenue_per_session numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH 
  -- Aggregate sessions by country (from session_start events)
  session_counts AS (
    SELECT 
      UPPER(TRIM(el.country_code)) AS country_code,
      COUNT(DISTINCT el.session_hash) AS sessions
    FROM public.event_logs el
    WHERE 
      el.event_name = 'session_start'
      AND el.created_at >= p_start
      AND el.created_at < p_end
      AND el.country_code IS NOT NULL
      AND TRIM(el.country_code) <> ''
      AND (
        p_region IS NULL 
        OR LOWER(TRIM(p_region)) = 'all'
        OR UPPER(TRIM(el.region)) = UPPER(TRIM(p_region))
      )
    GROUP BY UPPER(TRIM(el.country_code))
  ),
  
  -- Aggregate ad impressions by country (from ad_shown events)
  -- This serves as a proxy until we have actual ad revenue data
  ad_counts AS (
    SELECT 
      UPPER(TRIM(el.country_code)) AS country_code,
      COUNT(*) AS ad_impressions
    FROM public.event_logs el
    WHERE 
      el.event_name = 'ad_shown'
      AND el.created_at >= p_start
      AND el.created_at < p_end
      AND el.country_code IS NOT NULL
      AND TRIM(el.country_code) <> ''
      AND (
        p_region IS NULL 
        OR LOWER(TRIM(p_region)) = 'all'
        OR UPPER(TRIM(el.region)) = UPPER(TRIM(p_region))
      )
    GROUP BY UPPER(TRIM(el.country_code))
  )
  
  SELECT 
    sc.country_code,
    sc.sessions,
    COALESCE(ac.ad_impressions, 0) AS ad_impressions,
    -- Revenue placeholders (0 until we have actual revenue data)
    0::numeric AS revenue_total,
    0::numeric AS ad_revenue,
    0::numeric AS premium_revenue,
    0::numeric AS revenue_per_session
  FROM session_counts sc
  LEFT JOIN ad_counts ac ON sc.country_code = ac.country_code
  ORDER BY sc.sessions DESC;
$$;

-- ============================================================
-- COMMENT ON FUNCTION
-- ============================================================
COMMENT ON FUNCTION public.get_revenue_by_country_range(timestamptz, timestamptz, text) IS 
'Returns geo revenue metrics per country for Revenue Map.
v1: Sessions and ad_impressions from event_logs; revenue columns are placeholders.
When revenue tracking is added, update this function to compute actual ad_revenue.';

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_revenue_by_country_range(timestamptz, timestamptz, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_revenue_by_country_range(timestamptz, timestamptz, text) TO authenticated;

-- ============================================================
-- CONDITIONAL INDEXES
-- Only create if they don't already exist
-- ============================================================

-- Index: event_name + created_at (for time-range queries by event type)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'public' 
      AND tablename = 'event_logs' 
      AND indexname = 'idx_event_logs_event_created'
  ) THEN
    CREATE INDEX idx_event_logs_event_created 
    ON public.event_logs (event_name, created_at);
    RAISE NOTICE 'Created index: idx_event_logs_event_created';
  ELSE
    RAISE NOTICE 'Index already exists: idx_event_logs_event_created';
  END IF;
END $$;

-- Index: country_code (for grouping by country)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'public' 
      AND tablename = 'event_logs' 
      AND indexname = 'idx_event_logs_country_code'
  ) THEN
    CREATE INDEX idx_event_logs_country_code 
    ON public.event_logs (country_code);
    RAISE NOTICE 'Created index: idx_event_logs_country_code';
  ELSE
    RAISE NOTICE 'Index already exists: idx_event_logs_country_code';
  END IF;
END $$;

-- Index: region (for filtering by region)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'public' 
      AND tablename = 'event_logs' 
      AND indexname = 'idx_event_logs_region'
  ) THEN
    CREATE INDEX idx_event_logs_region 
    ON public.event_logs (region);
    RAISE NOTICE 'Created index: idx_event_logs_region';
  ELSE
    RAISE NOTICE 'Index already exists: idx_event_logs_region';
  END IF;
END $$;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST QUERIES
-- ============================================================

-- Test 1: All countries, last 7 days
SELECT '--- Revenue by country (last 7 days, all regions) ---' AS test;
SELECT * FROM public.get_revenue_by_country_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL
) LIMIT 10;

-- Test 2: Europe only, last 7 days
SELECT '--- Revenue by country (last 7 days, Europe only) ---' AS test;
SELECT * FROM public.get_revenue_by_country_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  'Europe'
) LIMIT 10;

-- Test 3: All countries (explicit 'all'), last 30 days
SELECT '--- Revenue by country (last 30 days, explicit all) ---' AS test;
SELECT * FROM public.get_revenue_by_country_range(
  NOW() - INTERVAL '30 days',
  NOW(),
  'all'
) LIMIT 10;

-- Test 4: North America only, last 30 days
SELECT '--- Revenue by country (last 30 days, North America only) ---' AS test;
SELECT * FROM public.get_revenue_by_country_range(
  NOW() - INTERVAL '30 days',
  NOW(),
  'North America'
) LIMIT 10;
