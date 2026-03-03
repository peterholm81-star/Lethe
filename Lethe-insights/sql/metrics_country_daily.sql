-- =============================================================================
-- METRICS COUNTRY DAILY - Compatibility Layer View
-- =============================================================================
--
-- Purpose: Provide a STABLE CONTRACT between raw analytics data and
--          higher-level intelligence engines (optimization, insights).
--
-- Principles:
--   - READ-ONLY view (no modifications to source tables)
--   - Privacy-first (aggregated data only, no user_id/device_id)
--   - Standardized schema for downstream consumers
--   - LAST 30 DAYS window only
--
-- Data Sources:
--   - public.event_logs (session_start, ad_shown events)
--
-- Schema:
--   date              - Day of metrics
--   country_code      - ISO country code (uppercase)
--   sessions          - Distinct session count
--   page_fetches      - Page views (PLACEHOLDER: = sessions)
--   ads_shown         - Ad impression count
--   estimated_revenue - Revenue estimate (PLACEHOLDER: 0)
--   avg_session_length - Avg session duration (PLACEHOLDER: 60s)
--   exits_after_ad    - Sessions that exited after ad (PLACEHOLDER: ads * 0.05)
--
-- =============================================================================

DROP VIEW IF EXISTS metrics_country_daily CASCADE;

CREATE OR REPLACE VIEW metrics_country_daily AS
WITH 
-- =============================================================================
-- SESSIONS: Aggregate by date + country from session_start events
-- =============================================================================
sessions_daily AS (
  SELECT 
    (el.created_at AT TIME ZONE 'UTC')::date AS date,
    UPPER(TRIM(el.country_code)) AS country_code,
    COUNT(DISTINCT el.session_hash) AS sessions
  FROM public.event_logs el
  WHERE 
    el.event_name = 'session_start'
    AND el.created_at >= (CURRENT_DATE - INTERVAL '30 days')
    AND el.country_code IS NOT NULL
    AND TRIM(el.country_code) <> ''
  GROUP BY 
    (el.created_at AT TIME ZONE 'UTC')::date,
    UPPER(TRIM(el.country_code))
),

-- =============================================================================
-- ADS: Aggregate by date + country from ad_shown events
-- =============================================================================
ads_daily AS (
  SELECT 
    (el.created_at AT TIME ZONE 'UTC')::date AS date,
    UPPER(TRIM(el.country_code)) AS country_code,
    COUNT(*) AS ads_shown
  FROM public.event_logs el
  WHERE 
    el.event_name = 'ad_shown'
    AND el.created_at >= (CURRENT_DATE - INTERVAL '30 days')
    AND el.country_code IS NOT NULL
    AND TRIM(el.country_code) <> ''
  GROUP BY 
    (el.created_at AT TIME ZONE 'UTC')::date,
    UPPER(TRIM(el.country_code))
)

-- =============================================================================
-- FINAL OUTPUT: Join sessions + ads, add placeholders for missing metrics
-- =============================================================================
SELECT 
  s.date,
  s.country_code,
  
  -- Actual data: sessions
  COALESCE(s.sessions, 0)::integer AS sessions,
  
  -- PLACEHOLDER: page_fetches = sessions (until page_fetch events are tracked)
  -- TODO: Replace with actual page_fetch event count when available
  COALESCE(s.sessions, 0)::integer AS page_fetches,
  
  -- Actual data: ads_shown (from ad_shown events)
  COALESCE(a.ads_shown, 0)::integer AS ads_shown,
  
  -- PLACEHOLDER: estimated_revenue = 0 (until revenue tracking is implemented)
  -- TODO: Replace with actual revenue calculation when ad_revenue events exist
  0::numeric AS estimated_revenue,
  
  -- PLACEHOLDER: avg_session_length = 60 seconds (until session duration tracking)
  -- TODO: Replace with actual session duration when session_end events are tracked
  60::numeric AS avg_session_length,
  
  -- PLACEHOLDER: exits_after_ad = ads_shown * 0.05 (5% exit rate assumption)
  -- TODO: Replace with actual exit-after-ad tracking when available
  -- This is a conservative estimate for optimization heuristics
  ROUND(COALESCE(a.ads_shown, 0) * 0.05)::integer AS exits_after_ad

FROM sessions_daily s
LEFT JOIN ads_daily a 
  ON s.date = a.date 
  AND s.country_code = a.country_code

-- Only include rows with at least 1 session
WHERE s.sessions > 0

ORDER BY s.date DESC, s.sessions DESC;

-- =============================================================================
-- COMMENT
-- =============================================================================
COMMENT ON VIEW metrics_country_daily IS 
'Compatibility layer providing standardized daily country metrics.
Last 30 days window. Privacy-first: aggregated data only.
PLACEHOLDER columns: page_fetches, estimated_revenue, avg_session_length, exits_after_ad.
Used by: country_monetization_optimization_v1 and future intelligence engines.';

-- =============================================================================
-- GRANTS (read-only)
-- =============================================================================
GRANT SELECT ON metrics_country_daily TO anon;
GRANT SELECT ON metrics_country_daily TO authenticated;

-- =============================================================================
-- NOTIFY PostgREST
-- =============================================================================
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERY
-- =============================================================================
SELECT '--- metrics_country_daily sample (last 7 days) ---' AS test;
SELECT * FROM metrics_country_daily 
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC, sessions DESC
LIMIT 20;

-- Aggregation check
SELECT '--- Aggregated totals (last 30 days) ---' AS test;
SELECT 
  COUNT(DISTINCT country_code) AS countries,
  SUM(sessions) AS total_sessions,
  SUM(ads_shown) AS total_ads,
  MIN(date) AS earliest_date,
  MAX(date) AS latest_date
FROM metrics_country_daily;
