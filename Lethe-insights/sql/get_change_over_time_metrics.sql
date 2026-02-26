-- ============================================================
-- GET CHANGE OVER TIME METRICS RPC (v2)
-- ============================================================
-- Returns daily metrics for investor-grade KPIs:
--   1. sessions       = unique app sessions per day
--   2. posts          = successful posts per day
--   3. post_rate      = posts / sessions (conversion rate)
--   4. pages_loaded   = pagination events per day (load more clicks)
--   5. pages_per_sess = pages_loaded / sessions (engagement depth)
--
-- Default: last 7 days. Custom: p_from to p_to (inclusive)
-- Zero-fills days with no data.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_change_over_time_metrics(text, text, int, date, date);

CREATE OR REPLACE FUNCTION public.get_change_over_time_metrics(
  p_city   text DEFAULT 'WORLD',
  p_region text DEFAULT 'WORLD',
  p_days   int  DEFAULT 7,
  p_from   date DEFAULT NULL,
  p_to     date DEFAULT NULL
)
RETURNS TABLE (
  day_bucket       date,
  sessions         bigint,
  posts            bigint,
  post_rate        numeric,
  pages_loaded     bigint,
  pages_per_session numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city   text;
  v_region text;
  v_start  date;
  v_end    date;
BEGIN
  -- Normalize null params to 'WORLD'
  v_city   := COALESCE(p_city, 'WORLD');
  v_region := COALESCE(p_region, 'WORLD');

  -- Determine date range
  IF p_from IS NOT NULL AND p_to IS NOT NULL THEN
    v_start := p_from;
    v_end   := p_to;
  ELSE
    v_end   := CURRENT_DATE;
    v_start := CURRENT_DATE - (p_days - 1);
  END IF;

  RETURN QUERY
  WITH date_series AS (
    SELECT d.day::date AS day
    FROM generate_series(v_start, v_end, '1 day'::interval) AS d(day)
  ),
  -- Get sessions and posts from daily_metrics
  daily_data AS (
    SELECT 
      dm.day_bucket,
      COALESCE(dm.sessions, 0)::bigint AS sessions,
      COALESCE(dm.post_success, 0)::bigint AS posts
    FROM daily_metrics dm
    WHERE dm.day_bucket >= v_start 
      AND dm.day_bucket <= v_end
      AND dm.city_code = v_city
      AND dm.region = v_region
  ),
  -- Count page_fetch events from event_logs
  page_events AS (
    SELECT 
      el.day_bucket,
      COUNT(*)::bigint AS pages_loaded
    FROM event_logs el
    WHERE el.event_name = 'page_fetch'
      AND el.day_bucket >= v_start
      AND el.day_bucket <= v_end
    GROUP BY el.day_bucket
  )
  SELECT
    ds.day AS day_bucket,
    COALESCE(dd.sessions, 0)::bigint AS sessions,
    COALESCE(dd.posts, 0)::bigint AS posts,
    CASE 
      WHEN COALESCE(dd.sessions, 0) > 0 
      THEN ROUND(COALESCE(dd.posts, 0)::numeric / dd.sessions::numeric, 4)
      ELSE 0::numeric
    END AS post_rate,
    COALESCE(pe.pages_loaded, 0)::bigint AS pages_loaded,
    CASE 
      WHEN COALESCE(dd.sessions, 0) > 0 
      THEN ROUND(COALESCE(pe.pages_loaded, 0)::numeric / dd.sessions::numeric, 2)
      ELSE 0::numeric
    END AS pages_per_session
  FROM date_series ds
  LEFT JOIN daily_data dd ON dd.day_bucket = ds.day
  LEFT JOIN page_events pe ON pe.day_bucket = ds.day
  ORDER BY ds.day ASC;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.get_change_over_time_metrics(text, text, int, date, date) TO anon;
GRANT EXECUTE ON FUNCTION public.get_change_over_time_metrics(text, text, int, date, date) TO authenticated;

-- Test
SELECT * FROM public.get_change_over_time_metrics('WORLD', 'WORLD', 7, NULL, NULL);
