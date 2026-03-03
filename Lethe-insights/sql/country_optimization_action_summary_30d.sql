-- ============================================================================
-- VIEW: country_optimization_action_summary_30d
-- ============================================================================
-- Returns EXACTLY ONE ROW summarizing the country optimization state.
-- Source: country_optimization_v1
-- Purpose: Drive a compact "Action Summary" card in the Monetization UI.
--
-- Privacy: no user data, aggregated country-level counts only.
-- ============================================================================

CREATE OR REPLACE VIEW public.country_optimization_action_summary_30d AS
WITH
src AS (
  SELECT
    country_code,
    COALESCE(confidence, 'LOW') AS confidence,
    COALESCE(signal, 'HOLD')   AS signal,
    COALESCE(friction_risk_level, 'LOW_VOLUME') AS friction_risk_level,
    COALESCE(drop_rate_30d, 0)  AS drop_rate_30d,
    total_ads_30d
  FROM public.country_optimization_v1
),

counts AS (
  SELECT
    COUNT(*)::int AS total_countries,
    COUNT(*) FILTER (WHERE confidence IN ('MED','HIGH'))::int AS actionable_countries,
    COUNT(*) FILTER (WHERE signal = 'INCREASE' AND confidence IN ('MED','HIGH'))::int AS inc_count,
    COUNT(*) FILTER (WHERE signal = 'DECREASE' AND confidence IN ('MED','HIGH'))::int AS dec_count,
    COUNT(*) FILTER (WHERE signal = 'HOLD')::int AS hold_count,
    COUNT(*) FILTER (WHERE confidence = 'LOW' OR friction_risk_level = 'LOW_VOLUME')::int AS low_volume_count,
    COUNT(*) FILTER (WHERE friction_risk_level = 'HIGH' AND confidence IN ('MED','HIGH'))::int AS high_risk_count,
    COUNT(*) FILTER (WHERE friction_risk_level = 'MED' AND confidence IN ('MED','HIGH'))::int AS med_risk_count
  FROM src
),

-- Top actionable rows for generating bullets (max 5, ordered by risk then ads)
top_rows AS (
  SELECT
    country_code,
    signal,
    confidence,
    friction_risk_level,
    drop_rate_30d,
    ROW_NUMBER() OVER (
      ORDER BY
        CASE friction_risk_level WHEN 'HIGH' THEN 0 WHEN 'MED' THEN 1 ELSE 2 END,
        CASE signal WHEN 'DECREASE' THEN 0 WHEN 'INCREASE' THEN 1 ELSE 2 END,
        total_ads_30d DESC NULLS LAST
    ) AS rn
  FROM src
  WHERE confidence IN ('MED','HIGH')
    AND signal IN ('INCREASE','DECREASE')
),

bullets AS (
  SELECT COALESCE(
    ARRAY_AGG(
      CASE
        WHEN signal = 'DECREASE' AND friction_risk_level = 'HIGH'
          THEN 'Decrease ads in ' || country_code || ' (' || confidence || ' confidence, HIGH risk).'
        WHEN signal = 'DECREASE'
          THEN 'Consider decrease in ' || country_code || ' (' || confidence || ' confidence, ' || friction_risk_level || ' risk).'
        WHEN signal = 'INCREASE' AND friction_risk_level IN ('LOW','LOW_VOLUME')
          THEN 'Safe to increase in ' || country_code || ' (' || confidence || ' confidence, low risk).'
        WHEN signal = 'INCREASE'
          THEN 'Consider increase in ' || country_code || ' (' || confidence || ' confidence, ' || friction_risk_level || ' risk).'
        ELSE 'Review ' || country_code || ' (' || signal || ', ' || confidence || ').'
      END
      ORDER BY rn
    ) FILTER (WHERE rn <= 5),
    ARRAY['Not enough data for changes yet. Keep collecting.']::text[]
  ) AS action_bullets
  FROM top_rows
  WHERE rn <= 5
)

SELECT
  c.total_countries,
  c.actionable_countries,
  c.inc_count,
  c.dec_count,
  c.hold_count,
  c.low_volume_count,
  c.high_risk_count,
  c.med_risk_count,

  -- Plain-language paragraph
  CASE
    WHEN c.actionable_countries = 0
      THEN 'No actionable countries yet (all low volume). Keep collecting data.'
    ELSE
      'Actionable: ' || c.actionable_countries || ' countries (MED/HIGH confidence). '
      || 'Suggested now: '
        || c.inc_count || ' increase, '
        || c.dec_count || ' decrease, '
        || c.hold_count || ' hold. '
      || CASE WHEN c.high_risk_count > 0 OR c.med_risk_count > 0
           THEN 'Risk: '
             || CASE WHEN c.high_risk_count > 0 THEN c.high_risk_count || ' HIGH' ELSE '' END
             || CASE WHEN c.high_risk_count > 0 AND c.med_risk_count > 0 THEN ', ' ELSE '' END
             || CASE WHEN c.med_risk_count > 0 THEN c.med_risk_count || ' MED' ELSE '' END
             || '. '
           ELSE ''
         END
      || CASE WHEN c.low_volume_count > 0
           THEN 'Low-volume: ' || c.low_volume_count || ' (ignore for now).'
           ELSE ''
         END
  END AS top_actions,

  b.action_bullets,

  now() AS updated_at

FROM counts c
CROSS JOIN bullets b;

COMMENT ON VIEW public.country_optimization_action_summary_30d IS
'Single-row summary of country monetization optimization state.
Counts actionable countries, signals, risk levels, and generates
a plain-language paragraph + bullet list for the UI.';

GRANT SELECT ON public.country_optimization_action_summary_30d TO anon;
GRANT SELECT ON public.country_optimization_action_summary_30d TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VERIFICATION (run manually)
-- ============================================================================
/*
SELECT * FROM country_optimization_action_summary_30d;
*/
