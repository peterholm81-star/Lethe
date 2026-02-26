-- ============================================================
-- ENGAGEMENT FLOW RPC: get_engagement_flow
-- ============================================================
-- Calculates engagement metrics from event_logs for Metrics Spine v1.
--
-- Returns:
--   - sessions: COUNT(DISTINCT session_hash) where session_start
--   - pages_loaded: COUNT(*) where page_fetch
--   - post_attempts: COUNT(*) where post_attempt
--   - post_success: COUNT(*) where post_success
--   - ads_shown: COUNT(*) where ad_shown
--   - ads_shown_sessions: DISTINCT sessions that saw an ad
--   - ad_continue_sessions: Sessions with page_fetch AFTER first ad_shown (within 10 min)
--   - ad_drop_sessions: Sessions with ad_shown but NO page_fetch after
--   - posts_per_session: post_success / sessions
--   - pages_per_session: pages_loaded / sessions
--   - ad_continue_rate: ad_continue_sessions / ads_shown_sessions
--
-- Filters: country_code, region, city_code, mode (all optional)
-- Period: p_days_back (default 7)
-- ============================================================

-- Drop both variants to avoid "not unique" error
DROP FUNCTION IF EXISTS public.get_engagement_flow();
DROP FUNCTION IF EXISTS public.get_engagement_flow(text, text, text, text, integer);

CREATE OR REPLACE FUNCTION public.get_engagement_flow(
  p_country_code text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL,
  p_days_back integer DEFAULT 7
)
RETURNS TABLE (
  sessions integer,
  pages_loaded integer,
  post_attempts integer,
  post_success integer,
  ads_shown integer,
  ads_shown_sessions integer,
  ad_continue_sessions integer,
  ad_drop_sessions integer,
  posts_per_session numeric,
  pages_per_session numeric,
  ad_continue_rate numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_date date := CURRENT_DATE - p_days_back;
  v_sessions integer;
  v_pages_loaded integer;
  v_post_attempts integer;
  v_post_success integer;
  v_ads_shown integer;
  v_ads_shown_sessions integer;
  v_ad_continue_sessions integer;
  v_ad_drop_sessions integer;
BEGIN
  -- ============================================================
  -- BASIC COUNTS (with filters)
  -- ============================================================
  
  -- Sessions: distinct session_hash with session_start event
  SELECT COUNT(DISTINCT session_hash)::integer INTO v_sessions
  FROM event_logs
  WHERE event_name = 'session_start'
    AND day_bucket >= v_start_date
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Pages loaded: count of page_fetch events
  SELECT COUNT(*)::integer INTO v_pages_loaded
  FROM event_logs
  WHERE event_name = 'page_fetch'
    AND day_bucket >= v_start_date
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Post attempts
  SELECT COUNT(*)::integer INTO v_post_attempts
  FROM event_logs
  WHERE event_name = 'post_attempt'
    AND day_bucket >= v_start_date
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Post success
  SELECT COUNT(*)::integer INTO v_post_success
  FROM event_logs
  WHERE event_name = 'post_success'
    AND day_bucket >= v_start_date
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Ads shown (event count)
  SELECT COUNT(*)::integer INTO v_ads_shown
  FROM event_logs
  WHERE event_name = 'ad_shown'
    AND day_bucket >= v_start_date
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Ads shown sessions (distinct sessions with ad_shown)
  SELECT COUNT(DISTINCT session_hash)::integer INTO v_ads_shown_sessions
  FROM event_logs
  WHERE event_name = 'ad_shown'
    AND day_bucket >= v_start_date
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- ============================================================
  -- AD CONTINUATION ANALYSIS
  -- Sessions that continued browsing after seeing an ad
  -- ============================================================
  
  -- Ad continue sessions: sessions with page_fetch AFTER first ad_shown (within 10 min)
  WITH ad_first AS (
    -- Get first ad_shown timestamp per session
    SELECT 
      session_hash,
      MIN(created_at) AS first_ad_at
    FROM event_logs
    WHERE event_name = 'ad_shown'
      AND day_bucket >= v_start_date
      AND (p_country_code IS NULL OR country_code = p_country_code)
      AND (p_region IS NULL OR region = p_region)
      AND (p_city_code IS NULL OR city_code = p_city_code)
      AND (p_mode IS NULL OR mode = p_mode)
    GROUP BY session_hash
  ),
  continued AS (
    -- Sessions with page_fetch after ad (within 10 min window)
    SELECT DISTINCT af.session_hash
    FROM ad_first af
    JOIN event_logs e ON e.session_hash = af.session_hash
    WHERE e.event_name = 'page_fetch'
      AND e.created_at > af.first_ad_at
      AND e.created_at <= af.first_ad_at + INTERVAL '10 minutes'
      AND e.day_bucket >= v_start_date
  )
  SELECT COUNT(*)::integer INTO v_ad_continue_sessions FROM continued;

  -- Ad drop sessions: sessions with ad_shown but NO page_fetch after
  v_ad_drop_sessions := v_ads_shown_sessions - v_ad_continue_sessions;

  -- ============================================================
  -- RETURN RESULTS
  -- ============================================================
  RETURN QUERY SELECT
    v_sessions,
    v_pages_loaded,
    v_post_attempts,
    v_post_success,
    v_ads_shown,
    v_ads_shown_sessions,
    v_ad_continue_sessions,
    v_ad_drop_sessions,
    -- Calculated rates (avoid division by zero)
    CASE WHEN v_sessions > 0 
      THEN ROUND(v_post_success::numeric / v_sessions, 2) 
      ELSE 0 END AS posts_per_session,
    CASE WHEN v_sessions > 0 
      THEN ROUND(v_pages_loaded::numeric / v_sessions, 1) 
      ELSE 0 END AS pages_per_session,
    CASE WHEN v_ads_shown_sessions > 0 
      THEN ROUND(v_ad_continue_sessions::numeric / v_ads_shown_sessions, 2) 
      ELSE 0 END AS ad_continue_rate;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_engagement_flow(text, text, text, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.get_engagement_flow(text, text, text, text, integer) TO authenticated;

-- ============================================================
-- TEST
-- ============================================================
SELECT * FROM public.get_engagement_flow(NULL, NULL, NULL, NULL, 7);
