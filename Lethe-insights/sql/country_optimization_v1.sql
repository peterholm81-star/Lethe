-- ============================================================================
-- VIEW: country_optimization_v1
-- ============================================================================
-- Unified per-country monetization optimization view.
-- Combines: continuation, drop, depth, recommendation signal, ad policy,
-- a deterministic Friction Risk Index, and real session counts.
--
-- Dependencies:
--   - public.country_ad_continue_summary  (continue_rate_30d, total_ads_30d, confidence)
--   - public.country_ad_depth_summary     (median_fetches_after_ad_30d)
--   - public.ad_policy_effective          (ads_per_session_cap, trigger_pages, enabled, source)
--   - public.event_logs                   (session_hash, event_name, country_code, created_at)
--
-- Friction Risk Index (0–100):
--   Drop contribution:    0 / +20 / +40 / +60 based on drop_rate_30d thresholds
--   Depth contribution:   0 / +15 / +30 / +45 based on median depth thresholds
--   Confidence penalty:   0 / +5 / +15 for HIGH / MED / LOW
--   Clamped to [0, 100].
--   Level: 0–34 LOW, 35–64 MED, 65–100 HIGH (LOW confidence => LOW_VOLUME)
--   Reason: up to 2 short explanations, or "Healthy engagement"
--
-- sessions_30d: COUNT(DISTINCT session_hash) of session_start events per country.
--
-- Privacy: anonymous session_hash only, no user tracking.
-- ============================================================================

-- Drop dependent views first (will be recreated after)
DROP VIEW IF EXISTS public.country_optimization_action_summary_30d;
DROP VIEW IF EXISTS public.country_optimization_v1;

-- ============================================================================
-- Sessions per country (last 30 days) from event_logs
-- ============================================================================

CREATE VIEW public.country_optimization_v1 AS
WITH
-- Real session counts from event_logs
country_sessions AS (
  SELECT
    UPPER(TRIM(el.country_code)) AS country_code,
    COUNT(DISTINCT el.session_hash)::int AS sessions_30d
  FROM public.event_logs el
  WHERE el.event_name = 'session_start'
    AND el.created_at >= now() - interval '30 days'
    AND el.country_code IS NOT NULL
    AND TRIM(el.country_code) <> ''
    AND el.session_hash IS NOT NULL
    AND el.session_hash <> ''
  GROUP BY UPPER(TRIM(el.country_code))
),

base AS (
  SELECT
    c.country_code,
    c.total_ads_30d::bigint                              AS total_ads_30d,
    COALESCE(c.continue_rate_30d, 0)                     AS continue_rate_30d,
    ROUND(100 - COALESCE(c.continue_rate_30d, 0), 2)    AS drop_rate_30d,
    COALESCE(d.median_fetches_after_ad_30d, 0)           AS median_fetches_after_ad_30d,
    c.confidence,

    -- Recommendation signal
    CASE
      WHEN c.confidence = 'LOW' THEN 'HOLD'
      WHEN c.continue_rate_30d >= 75
        AND (100 - COALESCE(c.continue_rate_30d, 0)) <= 30
        AND COALESCE(d.median_fetches_after_ad_30d, 0) >= 1.2
        THEN 'INCREASE'
      WHEN c.continue_rate_30d <= 55
        OR (100 - COALESCE(c.continue_rate_30d, 0)) >= 55
        THEN 'DECREASE'
      ELSE 'HOLD'
    END AS signal,

    -- Policy columns
    p.ads_per_session_cap  AS current_cap,
    p.trigger_pages        AS current_trigger,
    p.enabled              AS current_enabled,
    p.source               AS policy_source,

    -- Sessions (real, from event_logs)
    COALESCE(sess.sessions_30d, 0) AS sessions_30d,

    now() AS updated_at
  FROM public.country_ad_continue_summary c
  LEFT JOIN public.country_ad_depth_summary d
    ON d.country_code = c.country_code
  LEFT JOIN public.ad_policy_effective p
    ON p.country_code = c.country_code
  LEFT JOIN country_sessions sess
    ON sess.country_code = c.country_code
  WHERE c.country_code IS NOT NULL
    AND c.country_code != '??'
),

-- Friction Risk scoring
scored AS (
  SELECT
    b.*,
    CASE
      WHEN b.drop_rate_30d <= 25 THEN 0
      WHEN b.drop_rate_30d <= 40 THEN 20
      WHEN b.drop_rate_30d <= 55 THEN 40
      ELSE 60
    END
    + CASE
      WHEN b.median_fetches_after_ad_30d >= 1.5 THEN 0
      WHEN b.median_fetches_after_ad_30d >= 1.2 THEN 15
      WHEN b.median_fetches_after_ad_30d >= 0.8 THEN 30
      ELSE 45
    END
    + CASE
      WHEN b.confidence = 'HIGH' THEN 0
      WHEN b.confidence = 'MED'  THEN 5
      ELSE 15
    END AS raw_score
  FROM base b
)

SELECT
  s.country_code,
  s.total_ads_30d,
  s.continue_rate_30d,
  s.drop_rate_30d,
  s.median_fetches_after_ad_30d,
  s.confidence,
  s.signal,
  s.current_cap,
  s.current_trigger,
  s.current_enabled,
  s.policy_source,

  -- Friction Risk Index (clamped 0–100)
  LEAST(GREATEST(s.raw_score, 0), 100) AS friction_risk_score,

  -- Friction Risk Level (LOW confidence => LOW_VOLUME)
  CASE
    WHEN s.confidence = 'LOW' THEN 'LOW_VOLUME'
    WHEN LEAST(GREATEST(s.raw_score, 0), 100) >= 65 THEN 'HIGH'
    WHEN LEAST(GREATEST(s.raw_score, 0), 100) >= 35 THEN 'MED'
    ELSE 'LOW'
  END AS friction_risk_level,

  -- Friction Risk Reason
  CASE
    WHEN s.confidence = 'LOW'
      THEN 'Insufficient volume'
    WHEN s.drop_rate_30d > 55 AND s.median_fetches_after_ad_30d < 0.8
      THEN 'High drop after ads, Low scroll depth'
    WHEN s.drop_rate_30d > 55
      THEN 'High drop after ads'
    WHEN s.median_fetches_after_ad_30d < 0.8
      THEN 'Low scroll depth after ads'
    WHEN s.drop_rate_30d > 40
      THEN 'Elevated drop after ads'
    WHEN s.median_fetches_after_ad_30d < 1.2
      THEN 'Shallow depth after ads'
    ELSE 'Healthy engagement'
  END AS friction_risk_reason,

  s.sessions_30d,
  s.updated_at

FROM scored s
ORDER BY s.total_ads_30d DESC;

COMMENT ON VIEW public.country_optimization_v1 IS
'Unified per-country monetization optimization view.
Combines signals (continue, drop, depth), ad policy, recommendation, Friction Risk Index,
and real session counts from event_logs.

sessions_30d: COUNT(DISTINCT session_hash) of session_start events per country (last 30d).

Friction Risk (0–100): drop contribution + depth contribution + confidence penalty.
  LOW (0–34): Safe to increase ads.
  MED (35–64): Caution; monitor engagement.
  HIGH (65–100): Increasing ads is likely to hurt engagement.
  LOW_VOLUME: confidence=LOW, insufficient data for actionable risk.

Recommendation: INCREASE / HOLD / DECREASE based on signal thresholds.';

GRANT SELECT ON public.country_optimization_v1 TO anon;
GRANT SELECT ON public.country_optimization_v1 TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VERIFICATION (run manually)
-- ============================================================================
/*
-- Session counts per country (raw)
SELECT UPPER(TRIM(country_code)) AS cc, COUNT(DISTINCT session_hash) AS sessions
FROM event_logs
WHERE event_name = 'session_start'
  AND created_at >= now() - interval '30 days'
  AND country_code IS NOT NULL AND TRIM(country_code) <> ''
GROUP BY 1
ORDER BY sessions DESC
LIMIT 20;

-- View with sessions
SELECT country_code, total_ads_30d, sessions_30d, confidence, signal
FROM country_optimization_v1
ORDER BY total_ads_30d DESC
LIMIT 20;

-- Friction Risk distribution
SELECT friction_risk_level, COUNT(*), AVG(friction_risk_score)
FROM country_optimization_v1
GROUP BY friction_risk_level;
*/
