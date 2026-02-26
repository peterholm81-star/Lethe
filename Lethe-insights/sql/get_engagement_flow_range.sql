-- ============================================================
-- ENGAGEMENT FLOW RANGE RPC: get_engagement_flow_range
-- ============================================================
-- Calculates engagement metrics from event_logs for a timestamp range.
-- This replaces the days_back version with explicit time window.
--
-- DEFINITIONS (same as before):
--   sessions = COUNT(DISTINCT session_hash) WHERE session_start
--   pages_loaded = COUNT(*) WHERE page_fetch
--   post_attempts = COUNT(*) WHERE post_attempt
--   post_success = COUNT(*) WHERE post_success
--   ads_shown = COUNT(*) WHERE ad_shown
--   ads_shown_sessions = DISTINCT sessions that saw an ad
--   ad_continue_sessions = Sessions with page_fetch AFTER first ad_shown (within 10 min)
--   ad_drop_sessions = Sessions with ad_shown but NO page_fetch after
--   posts_per_session = post_success / sessions
--   pages_per_session = pages_loaded / sessions
--   ad_continue_rate = ad_continue_sessions / ads_shown_sessions
--
-- PARAMETERS:
--   p_start_ts: Start of window (inclusive, timestamptz ISO)
--   p_end_ts:   End of window (exclusive, timestamptz ISO)
--   p_region, p_country_code, p_city_code, p_mode: Lens filters (nullable)
-- ============================================================

DROP FUNCTION IF EXISTS public.get_engagement_flow_range(timestamptz, timestamptz, text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_engagement_flow_range(
  p_start_ts timestamptz,
  p_end_ts timestamptz,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL
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
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Pages loaded: count of page_fetch events
  SELECT COUNT(*)::integer INTO v_pages_loaded
  FROM event_logs
  WHERE event_name = 'page_fetch'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Post attempts
  SELECT COUNT(*)::integer INTO v_post_attempts
  FROM event_logs
  WHERE event_name = 'post_attempt'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Post success
  SELECT COUNT(*)::integer INTO v_post_success
  FROM event_logs
  WHERE event_name = 'post_success'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Ads shown (event count)
  SELECT COUNT(*)::integer INTO v_ads_shown
  FROM event_logs
  WHERE event_name = 'ad_shown'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- Ads shown sessions (distinct sessions with ad_shown)
  SELECT COUNT(DISTINCT session_hash)::integer INTO v_ads_shown_sessions
  FROM event_logs
  WHERE event_name = 'ad_shown'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code)
    AND (p_mode IS NULL OR mode = p_mode);

  -- ============================================================
  -- AD CONTINUATION ANALYSIS
  -- ============================================================
  
  WITH ad_first AS (
    SELECT 
      session_hash,
      MIN(created_at) AS first_ad_at
    FROM event_logs
    WHERE event_name = 'ad_shown'
      AND created_at >= p_start_ts
      AND created_at < p_end_ts
      AND (p_country_code IS NULL OR country_code = p_country_code)
      AND (p_region IS NULL OR region = p_region)
      AND (p_city_code IS NULL OR city_code = p_city_code)
      AND (p_mode IS NULL OR mode = p_mode)
    GROUP BY session_hash
  ),
  continued AS (
    SELECT DISTINCT af.session_hash
    FROM ad_first af
    JOIN event_logs e ON e.session_hash = af.session_hash
    WHERE e.event_name = 'page_fetch'
      AND e.created_at > af.first_ad_at
      AND e.created_at <= af.first_ad_at + INTERVAL '10 minutes'
      AND e.created_at >= p_start_ts
      AND e.created_at < p_end_ts
  )
  SELECT COUNT(*)::integer INTO v_ad_continue_sessions FROM continued;

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
GRANT EXECUTE ON FUNCTION public.get_engagement_flow_range(timestamptz, timestamptz, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_engagement_flow_range(timestamptz, timestamptz, text, text, text, text) TO authenticated;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST
-- ============================================================
SELECT * FROM public.get_engagement_flow_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL, NULL, NULL, NULL
);
