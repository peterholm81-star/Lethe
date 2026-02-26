-- =============================================================================
-- MOOD PULSE: Emotional Temperature Index RPC
-- =============================================================================
--
-- Returns the emotional balance score comparing positive vs negative moods.
-- Used for the "Emotional Temperature Index" on Mood page.
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role).
-- DEPENDS ON: confession_metrics_daily table must exist.
--
-- =============================================================================

-- =============================================================================
-- 1. DROP EXISTING FUNCTION (if upgrading)
-- =============================================================================

DROP FUNCTION IF EXISTS public.rpc_get_mood_pulse(date, date, text, text, text);

-- =============================================================================
-- 2. CREATE FUNCTION: rpc_get_mood_pulse
-- =============================================================================
--
-- Balance score calculation:
--   positive_count = sum of (joy, love, calm, hope, gratitude, confidence)
--   negative_count = sum of (anxiety, sadness, anger, loneliness, shame)
--   neutral_count = sum of (desire)
--   balance_score = (positive - negative) / total  (range: -1 to +1)
--
-- Previous period: same duration, immediately before start_date
--

CREATE OR REPLACE FUNCTION public.rpc_get_mood_pulse(
  p_start_date date,
  p_end_date date,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL
)
RETURNS TABLE (
  balance_score numeric,
  prev_balance_score numeric,
  delta_balance_score numeric,
  positive_share numeric,
  negative_share numeric,
  total_confessions bigint
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
  -- Current period
  v_positive bigint;
  v_negative bigint;
  v_total bigint;
  v_balance numeric;
  v_pos_share numeric;
  v_neg_share numeric;
  -- Previous period
  v_prev_positive bigint;
  v_prev_negative bigint;
  v_prev_total bigint;
  v_prev_balance numeric;
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
  -- CURRENT PERIOD STATS
  -- ==========================================================================
  
  SELECT 
    COALESCE(SUM(CASE WHEN mood_bucket = ANY(v_positive_moods) THEN count ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mood_bucket = ANY(v_negative_moods) THEN count ELSE 0 END), 0),
    COALESCE(SUM(count), 0)
  INTO v_positive, v_negative, v_total
  FROM public.confession_metrics_daily cmd
  WHERE cmd.date >= p_start_date
    AND cmd.date <= p_end_date
    AND (p_region IS NULL OR cmd.region = p_region)
    AND (p_country_code IS NULL OR cmd.country_code = p_country_code)
    AND (p_city_code IS NULL OR cmd.city_code = p_city_code);
  
  -- Calculate balance score (-1 to +1)
  IF v_total > 0 THEN
    v_balance := ROUND(((v_positive - v_negative)::numeric / v_total), 4);
    v_pos_share := ROUND((v_positive::numeric / v_total) * 100, 1);
    v_neg_share := ROUND((v_negative::numeric / v_total) * 100, 1);
  ELSE
    v_balance := 0;
    v_pos_share := 0;
    v_neg_share := 0;
  END IF;
  
  -- ==========================================================================
  -- PREVIOUS PERIOD STATS
  -- ==========================================================================
  
  SELECT 
    COALESCE(SUM(CASE WHEN mood_bucket = ANY(v_positive_moods) THEN count ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN mood_bucket = ANY(v_negative_moods) THEN count ELSE 0 END), 0),
    COALESCE(SUM(count), 0)
  INTO v_prev_positive, v_prev_negative, v_prev_total
  FROM public.confession_metrics_daily cmd
  WHERE cmd.date >= v_prev_start
    AND cmd.date <= v_prev_end
    AND (p_region IS NULL OR cmd.region = p_region)
    AND (p_country_code IS NULL OR cmd.country_code = p_country_code)
    AND (p_city_code IS NULL OR cmd.city_code = p_city_code);
  
  -- Calculate previous balance score
  IF v_prev_total > 0 THEN
    v_prev_balance := ROUND(((v_prev_positive - v_prev_negative)::numeric / v_prev_total), 4);
  ELSE
    v_prev_balance := 0;
  END IF;
  
  -- ==========================================================================
  -- RETURN
  -- ==========================================================================
  
  RETURN QUERY SELECT
    v_balance AS balance_score,
    v_prev_balance AS prev_balance_score,
    ROUND(v_balance - v_prev_balance, 4) AS delta_balance_score,
    v_pos_share AS positive_share,
    v_neg_share AS negative_share,
    v_total AS total_confessions;
END;
$$;

-- Comment
COMMENT ON FUNCTION public.rpc_get_mood_pulse IS 
  'Returns emotional balance score (positive vs negative moods) for Mood page temperature index.';

-- =============================================================================
-- 3. SECURITY: Grant to authenticated users
-- =============================================================================

REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse(date, date, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse(date, date, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_pulse(date, date, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_pulse(date, date, text, text, text) TO service_role;

-- =============================================================================
-- 4. NOTIFY POSTGREST
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 5. TEST QUERIES
-- =============================================================================

/*
-- Test: Last 7 days globally
SELECT * FROM public.rpc_get_mood_pulse(
  current_date - 6,
  current_date,
  NULL, NULL, NULL
);

-- Test: Last 7 days Europe only
SELECT * FROM public.rpc_get_mood_pulse(
  current_date - 6,
  current_date,
  'Europe', NULL, NULL
);

-- Test: Last 30 days
SELECT * FROM public.rpc_get_mood_pulse(
  current_date - 29,
  current_date,
  NULL, NULL, NULL
);
*/
