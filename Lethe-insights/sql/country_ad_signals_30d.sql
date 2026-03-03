-- ============================================================================
-- MIGRATION: country_ad_signals_30d
-- ============================================================================
-- Creates the signals layer that combines continuation and depth metrics
-- into a single per-country recommendation view.
--
-- Dependencies (must exist before running):
--   - public.country_ad_continue_summary  (continue_rate_30d, total_ads_30d)
--   - public.event_logs                   (event_name, session_hash, created_at)
--
-- Creates:
--   1. public.country_ad_depth_daily      (page_fetch depth after each ad)
--   2. public.country_ad_depth_summary    (30d aggregated depth per country)
--   3. public.country_ad_signals_30d      (joined signals + recommendation)
--
-- Recommendation thresholds (v1):
--   INCREASE: continue >= 75%, drop <= 30%, median depth >= 1.2
--   DECREASE: continue <= 55% OR drop >= 55%
--   HOLD:     everything else, or LOW confidence
--
-- Privacy: anonymous session_hash only, no user tracking.
-- ============================================================================


-- ============================================================================
-- STEP 1: country_ad_depth_daily
-- ============================================================================
-- For each ad_shown event, count how many page_fetch events follow in the
-- same session within 5 minutes. Aggregate per country per day.

CREATE OR REPLACE VIEW public.country_ad_depth_daily AS
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
    AND session_hash IS NOT NULL AND session_hash != ''
    AND country_code IS NOT NULL AND country_code != '' AND country_code != '??'
    AND created_at >= now() - interval '90 days'
),

-- Count page_fetches within 5 minutes after each ad
ad_depth AS (
  SELECT
    a.ad_event_id,
    a.country_code,
    a.event_date,
    COUNT(pf.id)::bigint AS fetches_after_ad
  FROM ad_events a
  LEFT JOIN LATERAL (
    SELECT id
    FROM public.event_logs e
    WHERE e.session_hash = a.session_hash
      AND e.event_name = 'page_fetch'
      AND e.created_at > a.ad_time
      AND e.created_at <= a.ad_time + interval '5 minutes'
  ) pf ON true
  GROUP BY a.ad_event_id, a.country_code, a.event_date
)

SELECT
  event_date AS date,
  country_code,
  COUNT(*)::bigint AS total_ads,
  ROUND(AVG(fetches_after_ad), 2) AS avg_fetches_after_ad,
  -- Approximate median using percentile_cont
  ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY fetches_after_ad)::numeric, 2)
    AS median_fetches_after_ad
FROM ad_depth
GROUP BY event_date, country_code
ORDER BY event_date DESC, total_ads DESC;

COMMENT ON VIEW public.country_ad_depth_daily IS
'Daily per-country page_fetch depth after ad_shown events.
Measures how many pages users browse within 5 min after seeing an ad.';

GRANT SELECT ON public.country_ad_depth_daily TO anon;
GRANT SELECT ON public.country_ad_depth_daily TO authenticated;


-- ============================================================================
-- STEP 2: country_ad_depth_summary (30d)
-- ============================================================================

CREATE OR REPLACE VIEW public.country_ad_depth_summary AS
SELECT
  country_code,
  SUM(total_ads)::bigint AS total_ads_30d,
  ROUND(
    CASE WHEN SUM(total_ads) > 0
      THEN SUM(avg_fetches_after_ad * total_ads) / SUM(total_ads)
      ELSE 0
    END, 2
  ) AS avg_fetches_after_ad_30d,
  ROUND(
    CASE WHEN SUM(total_ads) > 0
      THEN SUM(median_fetches_after_ad * total_ads) / SUM(total_ads)
      ELSE 0
    END, 2
  ) AS median_fetches_after_ad_30d
FROM public.country_ad_depth_daily
WHERE date >= current_date - interval '30 days'
GROUP BY country_code
ORDER BY total_ads_30d DESC;

COMMENT ON VIEW public.country_ad_depth_summary IS
'30-day weighted depth summary per country.
avg/median_fetches_after_ad_30d = weighted averages of daily values by ad volume.';

GRANT SELECT ON public.country_ad_depth_summary TO anon;
GRANT SELECT ON public.country_ad_depth_summary TO authenticated;


-- ============================================================================
-- STEP 3: country_ad_signals_30d (joined signals + recommendation)
-- ============================================================================

CREATE OR REPLACE VIEW public.country_ad_signals_30d AS
SELECT
  c.country_code,
  c.total_ads_30d::bigint                                   AS total_ads_30d,
  COALESCE(c.continue_rate_30d, 0)                          AS continue_rate_30d,
  ROUND(100 - COALESCE(c.continue_rate_30d, 0), 2)         AS drop_rate_30d,
  COALESCE(d.median_fetches_after_ad_30d, 0)                AS median_fetches_after_ad_30d,
  c.confidence,

  -- Recommendation logic (v1)
  -- LOW confidence -> always HOLD (insufficient data)
  -- MED/HIGH: threshold-based on continue, drop, and depth
  CASE
    WHEN c.confidence = 'LOW'
      THEN 'HOLD'
    WHEN c.continue_rate_30d >= 75
      AND (100 - COALESCE(c.continue_rate_30d, 0)) <= 30
      AND COALESCE(d.median_fetches_after_ad_30d, 0) >= 1.2
      THEN 'INCREASE'
    WHEN c.continue_rate_30d <= 55
      OR (100 - COALESCE(c.continue_rate_30d, 0)) >= 55
      THEN 'DECREASE'
    ELSE 'HOLD'
  END AS recommendation,

  now() AS updated_at

FROM public.country_ad_continue_summary c
LEFT JOIN public.country_ad_depth_summary d
  ON d.country_code = c.country_code
WHERE c.country_code IS NOT NULL
  AND c.country_code != '??'
ORDER BY c.total_ads_30d DESC;

COMMENT ON VIEW public.country_ad_signals_30d IS
'Per-country monetization signal: joins continuation rate, drop rate, and
engagement depth into a single recommendation (INCREASE / HOLD / DECREASE).

Thresholds (v1 — tune via SQL, no code deploy needed):
  INCREASE: continue >= 75%, drop <= 30%, median depth >= 1.2
  DECREASE: continue <= 55% OR drop >= 55%
  HOLD:     everything else, or LOW confidence

Confidence: HIGH >= 1000 ads, MED >= 100, LOW < 100.';

GRANT SELECT ON public.country_ad_signals_30d TO anon;
GRANT SELECT ON public.country_ad_signals_30d TO authenticated;


-- ============================================================================
-- STEP 4: Reload PostgREST schema
-- ============================================================================

NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- VERIFICATION (run manually)
-- ============================================================================
/*
SELECT * FROM country_ad_depth_daily
WHERE date >= current_date - interval '7 days'
LIMIT 20;

SELECT * FROM country_ad_depth_summary LIMIT 20;

SELECT * FROM country_ad_signals_30d ORDER BY total_ads_30d DESC LIMIT 20;

-- Check recommendation distribution
SELECT recommendation, COUNT(*), AVG(continue_rate_30d), AVG(drop_rate_30d)
FROM country_ad_signals_30d
GROUP BY recommendation;
*/
