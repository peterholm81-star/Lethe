-- ============================================================================
-- MONETIZATION CONTINUE-AFTER-AD INSTRUMENTATION LAYER
-- ============================================================================
-- Purpose: Track whether users continue browsing after seeing an ad.
-- This is a key signal for monetization optimization per country.
--
-- Privacy-safe:
--   - No user_id
--   - No device_id
--   - Only anonymous session_hash
--
-- Uses: event_name, session_hash (real event_logs columns)
-- Created: 2026-02-03
-- Updated: Use event_name and session_hash
-- ============================================================================

-- ============================================================================
-- STEP 1: Ensure performance indexes (use event_name, session_hash)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_event_logs_country_event_time
ON public.event_logs (country_code, event_name, created_at);

CREATE INDEX IF NOT EXISTS idx_event_logs_session_hash_time
ON public.event_logs (session_hash, created_at);

CREATE INDEX IF NOT EXISTS idx_event_logs_session_event_time
ON public.event_logs (session_hash, event_name, created_at);

-- ============================================================================
-- STEP 2: Drop and recreate country_ad_continue_daily
-- ============================================================================
-- Logic:
--   For each ad_shown: find next page_fetch in same session_hash within 60s
--   Only count the first one per ad
--   Group by date, country_code
--   Return: date, country_code, total_ads, continued_sessions, continue_rate
-- ============================================================================

DROP VIEW IF EXISTS public.country_ad_continue_summary;
DROP VIEW IF EXISTS public.country_ad_continue_daily;

CREATE VIEW public.country_ad_continue_daily AS
WITH 
ad_events AS (
  SELECT
    id AS ad_event_id,
    session_hash,
    country_code,
    created_at AS ad_time,
    date_trunc('day', created_at)::date AS event_date
  FROM public.event_logs
  WHERE event_name = 'ad_shown'
    AND session_hash IS NOT NULL
    AND session_hash != ''
    AND country_code IS NOT NULL
    AND country_code != ''
    AND created_at >= now() - interval '90 days'
),

ad_with_continuation AS (
  SELECT
    a.ad_event_id,
    a.session_hash,
    a.country_code,
    a.ad_time,
    a.event_date,
    CASE 
      WHEN next_fetch.id IS NOT NULL THEN 1 
      ELSE 0 
    END AS continued
  FROM ad_events a
  LEFT JOIN LATERAL (
    SELECT id
    FROM public.event_logs e
    WHERE e.session_hash = a.session_hash
      AND e.event_name = 'page_fetch'
      AND e.created_at > a.ad_time
      AND e.created_at <= a.ad_time + interval '60 seconds'
    ORDER BY e.created_at ASC
    LIMIT 1
  ) next_fetch ON true
)

SELECT
  event_date AS date,
  country_code,
  COUNT(*) AS total_ads,
  SUM(continued) AS continued_sessions,
  ROUND(
    CASE 
      WHEN COUNT(*) > 0 
      THEN (SUM(continued)::numeric / COUNT(*)::numeric) * 100
      ELSE 0 
    END,
    2
  ) AS continue_rate
FROM ad_with_continuation
GROUP BY event_date, country_code
ORDER BY event_date DESC, total_ads DESC;

COMMENT ON VIEW public.country_ad_continue_daily IS 
'Daily aggregation of ad continuation behavior per country.
Shows how often users continue browsing (page_fetch within 60s) after seeing an ad.

Columns:
- date: The day of the ad events
- country_code: ISO country code
- total_ads: Number of ad_shown events
- continued_sessions: Number of sessions that had a page_fetch within 60s after ad
- continue_rate: Percentage (continued_sessions / total_ads * 100)

Uses event_name and session_hash. No user tracking.';

-- ============================================================================
-- STEP 3: Drop and recreate country_ad_continue_summary
-- ============================================================================

CREATE VIEW public.country_ad_continue_summary AS
SELECT
  country_code,
  SUM(total_ads) AS total_ads_30d,
  SUM(continued_sessions) AS continued_30d,
  ROUND(
    CASE 
      WHEN SUM(total_ads) > 0 
      THEN (SUM(continued_sessions)::numeric / SUM(total_ads)::numeric) * 100
      ELSE 0 
    END,
    2
  ) AS continue_rate_30d,
  CASE
    WHEN SUM(total_ads) >= 1000 THEN 'HIGH'
    WHEN SUM(total_ads) >= 100 THEN 'MED'
    ELSE 'LOW'
  END AS confidence
FROM public.country_ad_continue_daily
WHERE date >= current_date - interval '30 days'
GROUP BY country_code
ORDER BY total_ads_30d DESC;

COMMENT ON VIEW public.country_ad_continue_summary IS 
'30-day summary of ad continuation rate per country.
High continue_rate (>70%) = users tolerate ads well
Low continue_rate (<40%) = ads may be causing exits';

-- ============================================================================
-- STEP 4: Grant permissions
-- ============================================================================

GRANT SELECT ON public.country_ad_continue_daily TO anon;
GRANT SELECT ON public.country_ad_continue_daily TO authenticated;
GRANT SELECT ON public.country_ad_continue_summary TO anon;
GRANT SELECT ON public.country_ad_continue_summary TO authenticated;

-- ============================================================================
-- STEP 5: Notify PostgREST to reload schema
-- ============================================================================

NOTIFY pgrst, 'reload schema';
