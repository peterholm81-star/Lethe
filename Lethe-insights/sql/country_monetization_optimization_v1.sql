-- =============================================================================
-- COUNTRY MONETIZATION OPTIMIZATION VIEW v1
-- =============================================================================
--
-- Purpose: Generate per-country monetization optimization recommendations
--          based on aggregated metrics from metrics_country_daily.
--
-- Principles:
--   - READ-ONLY view (no table modifications)
--   - Privacy-safe (aggregated data only, no user/session joins)
--   - Deterministic logic (no randomness)
--   - Safe division (NULLIF to prevent divide-by-zero)
--   - Last 30 days aggregation window
--
-- Input Source: metrics_country_daily
--
-- Decision Logic:
--   exit_rate > 0.25                                    → DECREASE (cap: 0)
--   exit_rate < 0.08 AND ads/session < 0.8 AND n>=300  → INCREASE (cap: 2)
--   else                                                → HOLD (cap: 1)
--
-- Confidence:
--   sessions >= 1000  → HIGH
--   sessions >= 300   → MED
--   else              → LOW
--
-- =============================================================================

DROP VIEW IF EXISTS country_monetization_optimization_v1 CASCADE;

CREATE OR REPLACE VIEW country_monetization_optimization_v1 AS
WITH 
-- =============================================================================
-- STEP 1: Aggregate last 30 days per country
-- =============================================================================
aggregated AS (
  SELECT
    country_code,
    SUM(sessions)::integer AS sessions,
    SUM(ads_shown)::integer AS ads_shown
  FROM metrics_country_daily
  WHERE date >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY country_code
  HAVING SUM(sessions) > 0
),

-- =============================================================================
-- STEP 2: Compute derived metrics with safe division
-- =============================================================================
metrics AS (
  SELECT
    country_code,
    sessions,
    ads_shown,
    
    -- Ads per session (safe division)
    ROUND(
      ads_shown::numeric / NULLIF(sessions, 0),
      3
    ) AS ads_per_session,
    
    -- Exit rate after ad
    -- PLACEHOLDER: Using constant 0.05 (5%) until real tracking exists
    -- When exits_after_ad is properly tracked, use:
    -- exits_after_ad::numeric / NULLIF(ads_shown, 0)
    0.05::numeric AS exit_rate_after_ad,
    
    -- Current cap assumption (v1 baseline)
    1 AS current_cap
    
  FROM aggregated
),

-- =============================================================================
-- STEP 3: Apply decision logic
-- =============================================================================
recommendations AS (
  SELECT
    country_code,
    sessions,
    ads_per_session,
    exit_rate_after_ad,
    current_cap,
    
    -- Confidence based on data volume
    CASE
      WHEN sessions >= 1000 THEN 'HIGH'
      WHEN sessions >= 300 THEN 'MED'
      ELSE 'LOW'
    END AS confidence,
    
    -- Decision logic (deterministic heuristics v1)
    CASE
      -- Rule 1: High exit rate → DECREASE
      WHEN COALESCE(exit_rate_after_ad, 0) > 0.25 
        THEN 'DECREASE'
      
      -- Rule 2: Low exit rate + low saturation + sufficient data → INCREASE
      WHEN COALESCE(exit_rate_after_ad, 1) < 0.08
        AND COALESCE(ads_per_session, 1) < 0.8
        AND sessions >= 300
        THEN 'INCREASE'
      
      -- Rule 3: Default → HOLD
      ELSE 'HOLD'
    END AS decision,
    
    -- Recommended cap based on decision
    CASE
      WHEN COALESCE(exit_rate_after_ad, 0) > 0.25 
        THEN 0
      WHEN COALESCE(exit_rate_after_ad, 1) < 0.08
        AND COALESCE(ads_per_session, 1) < 0.8
        AND sessions >= 300
        THEN 2
      ELSE 1
    END AS recommended_cap
    
  FROM metrics
)

-- =============================================================================
-- STEP 4: Final output with explanation reasons
-- =============================================================================
SELECT
  r.country_code,
  r.sessions,
  r.ads_per_session,
  r.exit_rate_after_ad,
  r.current_cap,
  r.recommended_cap,
  r.confidence,
  r.decision,
  
  -- Reasons: human-readable explanation
  CASE
    -- DECREASE reasons
    WHEN r.decision = 'DECREASE' THEN
      'High exit rate after ads (' || ROUND(r.exit_rate_after_ad * 100, 1) || '%). ' ||
      'Recommend reducing ad exposure to improve retention.'
    
    -- INCREASE reasons
    WHEN r.decision = 'INCREASE' THEN
      'Low exit rate (' || ROUND(r.exit_rate_after_ad * 100, 1) || '%) and ' ||
      'low ad saturation (' || ROUND(COALESCE(r.ads_per_session, 0), 2) || ' ads/session). ' ||
      'Users tolerate monetization well. Opportunity to increase ad cap.'
    
    -- HOLD reasons
    ELSE
      CASE 
        WHEN r.confidence = 'LOW' THEN
          'Stable monetization behavior. Limited data volume (' || r.sessions || ' sessions) — monitor before changes.'
        ELSE
          'Stable monetization behavior. Current settings appear balanced.'
      END
  END AS reasons

FROM recommendations r

ORDER BY 
  -- Prioritize actionable recommendations with high confidence
  CASE r.confidence 
    WHEN 'HIGH' THEN 1 
    WHEN 'MED' THEN 2 
    ELSE 3 
  END,
  CASE r.decision 
    WHEN 'DECREASE' THEN 1
    WHEN 'INCREASE' THEN 2
    ELSE 3 
  END,
  r.sessions DESC;

-- =============================================================================
-- COMMENT
-- =============================================================================
COMMENT ON VIEW country_monetization_optimization_v1 IS 
'Intelligence layer: per-country monetization optimization recommendations.
Source: metrics_country_daily (last 30 days aggregated).
Privacy-safe: no individual user tracking.
v1 heuristics: cap adjustments (0/1/2) based on exit rates and ad saturation.
Confidence levels: HIGH (>=1000 sessions), MED (>=300), LOW (<300).';

-- =============================================================================
-- GRANTS (read-only)
-- =============================================================================
GRANT SELECT ON country_monetization_optimization_v1 TO anon;
GRANT SELECT ON country_monetization_optimization_v1 TO authenticated;

-- =============================================================================
-- NOTIFY PostgREST
-- =============================================================================
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES
-- =============================================================================

-- All recommendations
SELECT '--- All optimization recommendations ---' AS test;
SELECT * FROM country_monetization_optimization_v1;

-- High confidence actionable items only
SELECT '--- High confidence actionable items ---' AS test;
SELECT * FROM country_monetization_optimization_v1
WHERE confidence = 'HIGH' AND decision != 'HOLD';

-- Summary by decision type
SELECT '--- Summary by decision type ---' AS test;
SELECT 
  decision,
  confidence,
  COUNT(*) AS countries,
  SUM(sessions) AS total_sessions
FROM country_monetization_optimization_v1
GROUP BY decision, confidence
ORDER BY decision, confidence;
