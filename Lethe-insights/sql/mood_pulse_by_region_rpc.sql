-- =============================================================================
-- MOOD PULSE BY REGION: Returns balance scores per region for World Map
-- =============================================================================
--
-- Returns emotional balance score for each region in the date range.
-- Used for the "World Mood Map" on Mood page.
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role).
-- DEPENDS ON: confession_metrics_daily table must exist.
--
-- =============================================================================

-- =============================================================================
-- 1. DROP EXISTING FUNCTION (if upgrading)
-- =============================================================================

DROP FUNCTION IF EXISTS public.rpc_get_mood_pulse_by_region(date, date);

-- =============================================================================
-- 2. CREATE FUNCTION: rpc_get_mood_pulse_by_region
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_mood_pulse_by_region(
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  region text,
  balance_score numeric,
  prev_balance_score numeric,
  delta_balance_score numeric,
  positive_share numeric,
  negative_share numeric,
  total_confessions numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days int;
  v_prev_start date;
  v_prev_end date;
  v_positive_moods text[] := ARRAY['joy', 'love', 'calm', 'hope', 'gratitude', 'confidence'];
  v_negative_moods text[] := ARRAY['anxiety', 'sadness', 'anger', 'loneliness', 'shame'];
BEGIN
  -- ==========================================================================
  -- VALIDATION
  -- ==========================================================================
  
  IF p_start_date IS NULL THEN
    RAISE EXCEPTION 'p_start_date cannot be NULL';
  END IF;
  
  IF p_end_date IS NULL THEN
    RAISE EXCEPTION 'p_end_date cannot be NULL';
  END IF;
  
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'p_start_date cannot be after p_end_date';
  END IF;
  
  -- ==========================================================================
  -- CALCULATE PERIOD LENGTHS
  -- ==========================================================================
  
  v_days := p_end_date - p_start_date + 1;
  v_prev_end := p_start_date - 1;
  v_prev_start := v_prev_end - v_days + 1;
  
  -- ==========================================================================
  -- RETURN QUERY
  -- ==========================================================================
  
  RETURN QUERY
  WITH current_period AS (
    SELECT 
      cmd.region AS r_region,
      SUM(CASE WHEN cmd.mood_bucket = ANY(v_positive_moods) THEN cmd.count ELSE 0 END) AS positive,
      SUM(CASE WHEN cmd.mood_bucket = ANY(v_negative_moods) THEN cmd.count ELSE 0 END) AS negative,
      SUM(cmd.count) AS total
    FROM public.confession_metrics_daily cmd
    WHERE cmd.date >= p_start_date
      AND cmd.date <= p_end_date
    GROUP BY cmd.region
  ),
  prev_period AS (
    SELECT 
      cmd.region AS r_region,
      SUM(CASE WHEN cmd.mood_bucket = ANY(v_positive_moods) THEN cmd.count ELSE 0 END) AS positive,
      SUM(CASE WHEN cmd.mood_bucket = ANY(v_negative_moods) THEN cmd.count ELSE 0 END) AS negative,
      SUM(cmd.count) AS total
    FROM public.confession_metrics_daily cmd
    WHERE cmd.date >= v_prev_start
      AND cmd.date <= v_prev_end
    GROUP BY cmd.region
  ),
  combined AS (
    SELECT
      COALESCE(c.r_region, p.r_region) AS region_name,
      COALESCE(c.positive, 0) AS c_positive,
      COALESCE(c.negative, 0) AS c_negative,
      COALESCE(c.total, 0) AS c_total,
      COALESCE(p.positive, 0) AS p_positive,
      COALESCE(p.negative, 0) AS p_negative,
      COALESCE(p.total, 0) AS p_total
    FROM current_period c
    FULL OUTER JOIN prev_period p ON c.r_region = p.r_region
  )
  SELECT
    cb.region_name AS region,
    CASE 
      WHEN cb.c_total > 0 THEN ROUND(((cb.c_positive - cb.c_negative)::numeric / cb.c_total), 4)
      ELSE 0::numeric
    END AS balance_score,
    CASE 
      WHEN cb.p_total > 0 THEN ROUND(((cb.p_positive - cb.p_negative)::numeric / cb.p_total), 4)
      ELSE 0::numeric
    END AS prev_balance_score,
    CASE 
      WHEN cb.c_total > 0 AND cb.p_total > 0 THEN 
        ROUND(
          ((cb.c_positive - cb.c_negative)::numeric / cb.c_total) -
          ((cb.p_positive - cb.p_negative)::numeric / cb.p_total),
          4
        )
      WHEN cb.c_total > 0 THEN ROUND(((cb.c_positive - cb.c_negative)::numeric / cb.c_total), 4)
      ELSE 0::numeric
    END AS delta_balance_score,
    CASE 
      WHEN cb.c_total > 0 THEN ROUND((cb.c_positive::numeric / cb.c_total) * 100, 1)
      ELSE 0::numeric
    END AS positive_share,
    CASE 
      WHEN cb.c_total > 0 THEN ROUND((cb.c_negative::numeric / cb.c_total) * 100, 1)
      ELSE 0::numeric
    END AS negative_share,
    cb.c_total AS total_confessions
  FROM combined cb
  WHERE cb.region_name IS NOT NULL
  ORDER BY cb.c_total DESC;
END;
$$;

-- Comment
COMMENT ON FUNCTION public.rpc_get_mood_pulse_by_region IS 
  'Returns emotional balance scores per region for World Mood Map.';

-- =============================================================================
-- 3. SECURITY: Grant to authenticated users
-- =============================================================================

REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse_by_region(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse_by_region(date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_pulse_by_region(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_pulse_by_region(date, date) TO service_role;

-- =============================================================================
-- 4. NOTIFY POSTGREST
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 5. TEST QUERIES
-- =============================================================================

/*
-- Test: Last 7 days
SELECT * FROM public.rpc_get_mood_pulse_by_region(
  current_date - 6,
  current_date
);

-- Test: Last 30 days
SELECT * FROM public.rpc_get_mood_pulse_by_region(
  current_date - 29,
  current_date
);
*/
