-- ============================================================
-- CHANGE OVER TIME RANGE RPC: get_change_over_time_range
-- ============================================================
-- Returns daily metrics for a timestamp range (for charting).
--
-- DEFINITIONS (per day):
--   day_bucket = DATE(created_at AT TIME ZONE 'UTC')
--   sessions = COUNT(DISTINCT session_hash) WHERE session_start
--   posts = COUNT(*) WHERE post_success
--   post_rate = posts / sessions
--   pages_loaded = COUNT(*) WHERE page_fetch
--   pages_per_session = pages_loaded / sessions
--
-- PARAMETERS:
--   p_start_ts: Start of window (inclusive, timestamptz ISO)
--   p_end_ts:   End of window (exclusive, timestamptz ISO)
--   p_region, p_country_code, p_city_code, p_mode: Lens filters (nullable)
--
-- RETURNS: One row per day, ordered by day ascending
-- ============================================================

DROP FUNCTION IF EXISTS public.get_change_over_time_range(timestamptz, timestamptz, text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_change_over_time_range(
  p_start_ts timestamptz,
  p_end_ts timestamptz,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL
)
RETURNS TABLE (
  day_bucket date,
  sessions integer,
  posts integer,
  post_rate numeric,
  pages_loaded integer,
  pages_per_session numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH daily_sessions AS (
    SELECT 
      DATE(created_at AT TIME ZONE 'UTC') AS db,
      COUNT(DISTINCT session_hash)::integer AS cnt
    FROM event_logs
    WHERE event_name = 'session_start'
      AND created_at >= p_start_ts
      AND created_at < p_end_ts
      AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
      AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
      AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
      AND (p_mode IS NULL OR mode = p_mode)
    GROUP BY DATE(created_at AT TIME ZONE 'UTC')
  ),
  daily_posts AS (
    SELECT 
      DATE(created_at AT TIME ZONE 'UTC') AS db,
      COUNT(*)::integer AS cnt
    FROM event_logs
    WHERE event_name = 'post_success'
      AND created_at >= p_start_ts
      AND created_at < p_end_ts
      AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
      AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
      AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
      AND (p_mode IS NULL OR mode = p_mode)
    GROUP BY DATE(created_at AT TIME ZONE 'UTC')
  ),
  daily_pages AS (
    SELECT 
      DATE(created_at AT TIME ZONE 'UTC') AS db,
      COUNT(*)::integer AS cnt
    FROM event_logs
    WHERE event_name = 'page_fetch'
      AND created_at >= p_start_ts
      AND created_at < p_end_ts
      AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
      AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
      AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
      AND (p_mode IS NULL OR mode = p_mode)
    GROUP BY DATE(created_at AT TIME ZONE 'UTC')
  ),
  all_days AS (
    SELECT db FROM daily_sessions
    UNION SELECT db FROM daily_posts
    UNION SELECT db FROM daily_pages
  )
  SELECT 
    ad.db AS day_bucket,
    COALESCE(ds.cnt, 0) AS sessions,
    COALESCE(dp.cnt, 0) AS posts,
    CASE WHEN COALESCE(ds.cnt, 0) > 0 
      THEN ROUND(COALESCE(dp.cnt, 0)::numeric / ds.cnt, 3)
      ELSE 0::numeric
    END AS post_rate,
    COALESCE(dpa.cnt, 0) AS pages_loaded,
    CASE WHEN COALESCE(ds.cnt, 0) > 0 
      THEN ROUND(COALESCE(dpa.cnt, 0)::numeric / ds.cnt, 1)
      ELSE 0::numeric
    END AS pages_per_session
  FROM all_days ad
  LEFT JOIN daily_sessions ds ON ds.db = ad.db
  LEFT JOIN daily_posts dp ON dp.db = ad.db
  LEFT JOIN daily_pages dpa ON dpa.db = ad.db
  ORDER BY ad.db ASC;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_change_over_time_range(timestamptz, timestamptz, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_change_over_time_range(timestamptz, timestamptz, text, text, text, text) TO authenticated;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST
-- ============================================================
SELECT * FROM public.get_change_over_time_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL, NULL, NULL, NULL
);
