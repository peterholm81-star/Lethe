-- ============================================================
-- PULSE METRICS RANGE RPC: get_pulse_metrics_range
-- ============================================================
-- Returns Pulse metrics (sessions, readers, posts) for a timestamp range.
-- This is the STANDARD version that matches EngagementFlow definitions.
--
-- DEFINITIONS (must match other metrics RPCs):
--   sessions = COUNT(DISTINCT session_hash) WHERE event_name='session_start'
--   readers  = COUNT(DISTINCT session_hash) WHERE event_name='page_fetch'
--   posts    = COUNT(*) WHERE event_name='post_success'
--
-- PARAMETERS:
--   p_start_ts: Start of window (inclusive, timestamptz ISO)
--   p_end_ts:   End of window (exclusive, timestamptz ISO)
--   p_region, p_country_code, p_city_code, p_mode: Lens filters (nullable)
--
-- TIME FILTERING:
--   created_at >= p_start_ts AND created_at < p_end_ts
-- ============================================================

DROP FUNCTION IF EXISTS public.get_pulse_metrics_range(timestamptz, timestamptz, text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_pulse_metrics_range(
  p_start_ts timestamptz,
  p_end_ts timestamptz,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL
)
RETURNS TABLE (
  sessions bigint,
  readers bigint,
  posts bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    -- Sessions: distinct session_hash with session_start event
    (
      SELECT COUNT(DISTINCT session_hash)
      FROM event_logs
      WHERE event_name = 'session_start'
        AND created_at >= p_start_ts
        AND created_at < p_end_ts
        AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
        AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
        AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
        AND (p_mode IS NULL OR mode = p_mode)
    )::bigint AS sessions,
    
    -- Readers: distinct session_hash with page_fetch event
    (
      SELECT COUNT(DISTINCT session_hash)
      FROM event_logs
      WHERE event_name = 'page_fetch'
        AND created_at >= p_start_ts
        AND created_at < p_end_ts
        AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
        AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
        AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
        AND (p_mode IS NULL OR mode = p_mode)
    )::bigint AS readers,
    
    -- Posts: count of post_success events
    (
      SELECT COUNT(*)
      FROM event_logs
      WHERE event_name = 'post_success'
        AND created_at >= p_start_ts
        AND created_at < p_end_ts
        AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
        AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
        AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
        AND (p_mode IS NULL OR mode = p_mode)
    )::bigint AS posts;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics_range(timestamptz, timestamptz, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics_range(timestamptz, timestamptz, text, text, text, text) TO authenticated;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST
-- ============================================================
-- Last 7 days (global)
SELECT * FROM public.get_pulse_metrics_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL, NULL, NULL, NULL
);
