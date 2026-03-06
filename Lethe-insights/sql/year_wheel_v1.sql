-- ============================================================
-- YEAR WHEEL V1: Monthly buckets for sessions, posts & mood
-- ============================================================
-- Returns one row per calendar month within the requested
-- window (p_days back from p_end_date). Months outside the
-- data range still appear with zeroes.
--
-- Data sources:
--   Sessions + Posts: public.event_logs
--     event_name: session_start, post_success
--     Columns: created_at, session_hash, event_name,
--              region, country_code, city_code
--
--   Mood: public.confession_metrics_daily
--     Columns: date, mood_bucket, count,
--              region, country_code, city_code
--     Positive: joy, love, calm, hope, gratitude, confidence
--     Negative: anxiety, sadness, anger, loneliness, shame
--     Neutral (excluded): desire
--
-- Deploy: paste into Supabase Dashboard → SQL Editor → Run.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_year_wheel_v1(text, text, text, text, int, date);

CREATE OR REPLACE FUNCTION public.get_year_wheel_v1(
  p_scope    text    DEFAULT 'global',
  p_region   text    DEFAULT NULL,
  p_country  text    DEFAULT NULL,
  p_city     text    DEFAULT NULL,
  p_days     integer DEFAULT 365,
  p_end_date date    DEFAULT current_date
)
RETURNS TABLE (
  month_start      date,
  sessions         integer,
  posts            integer,
  posts_per_session numeric,
  mood_pos         integer,
  mood_neg         integer,
  mood_balance     numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start       date := (p_end_date - (p_days || ' days')::interval)::date;
  v_end         date := p_end_date;
  v_month_start date := date_trunc('month', v_start)::date;
  v_month_end   date := date_trunc('month', v_end)::date;

  v_positive_moods text[] := ARRAY['joy','love','calm','hope','gratitude','confidence'];
  v_negative_moods text[] := ARRAY['anxiety','sadness','anger','loneliness','shame'];
BEGIN
  RETURN QUERY

  -- Calendar spine: one row per month
  WITH months AS (
    SELECT d::date AS ms
    FROM generate_series(v_month_start, v_month_end, '1 month'::interval) AS d
  ),

  -- Sessions + posts from event_logs
  events_agg AS (
    SELECT
      date_trunc('month', e.created_at)::date AS m,
      COUNT(DISTINCT CASE WHEN e.event_name = 'session_start' THEN e.session_hash END)::integer AS sess,
      COUNT(CASE WHEN e.event_name = 'post_success' THEN 1 END)::integer AS pst
    FROM event_logs e
    WHERE e.created_at >= v_start::timestamptz
      AND e.created_at < (v_end + 1)::timestamptz
      AND e.event_name IN ('session_start', 'post_success')
      AND (
        p_scope = 'global'
        OR (p_scope = 'region'  AND UPPER(TRIM(e.region))       = UPPER(TRIM(p_region)))
        OR (p_scope = 'country' AND UPPER(TRIM(e.country_code)) = UPPER(TRIM(p_country)))
        OR (p_scope = 'city'    AND UPPER(TRIM(e.city_code))    = UPPER(TRIM(p_city)))
      )
    GROUP BY date_trunc('month', e.created_at)::date
  ),

  -- Mood from confession_metrics_daily
  mood_agg AS (
    SELECT
      date_trunc('month', cmd.date)::date AS m,
      COALESCE(SUM(CASE WHEN cmd.mood_bucket = ANY(v_positive_moods) THEN cmd.count ELSE 0 END), 0)::integer AS m_pos,
      COALESCE(SUM(CASE WHEN cmd.mood_bucket = ANY(v_negative_moods) THEN cmd.count ELSE 0 END), 0)::integer AS m_neg
    FROM confession_metrics_daily cmd
    WHERE cmd.date >= v_start
      AND cmd.date <= v_end
      AND (
        p_scope = 'global'
        OR (p_scope = 'region'  AND UPPER(TRIM(cmd.region))       = UPPER(TRIM(p_region)))
        OR (p_scope = 'country' AND UPPER(TRIM(cmd.country_code)) = UPPER(TRIM(p_country)))
        OR (p_scope = 'city'    AND UPPER(TRIM(cmd.city_code))    = UPPER(TRIM(p_city)))
      )
    GROUP BY date_trunc('month', cmd.date)::date
  )

  SELECT
    mo.ms                                                       AS month_start,
    COALESCE(ea.sess, 0)                                        AS sessions,
    COALESCE(ea.pst, 0)                                         AS posts,
    ROUND(
      COALESCE(ea.pst, 0)::numeric
        / NULLIF(COALESCE(ea.sess, 0), 0),
      3
    )                                                           AS posts_per_session,
    COALESCE(ma.m_pos, 0)                                       AS mood_pos,
    COALESCE(ma.m_neg, 0)                                       AS mood_neg,
    ROUND(
      (COALESCE(ma.m_pos, 0) - COALESCE(ma.m_neg, 0))::numeric
        / NULLIF(COALESCE(ma.m_pos, 0) + COALESCE(ma.m_neg, 0), 0),
      3
    )                                                           AS mood_balance
  FROM months mo
  LEFT JOIN events_agg ea ON ea.m = mo.ms
  LEFT JOIN mood_agg   ma ON ma.m = mo.ms
  ORDER BY mo.ms;

END;
$$;

GRANT EXECUTE ON FUNCTION public.get_year_wheel_v1(text, text, text, text, int, date)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SMOKE TESTS (run manually in SQL Editor)
-- ============================================================
-- select * from public.get_year_wheel_v1('global', null, null, null, 365, current_date);
-- select * from public.get_year_wheel_v1('region', 'Europe', null, null, 365, current_date);
-- select * from public.get_year_wheel_v1('country', null, 'NO', null, 365, current_date);
-- select * from public.get_year_wheel_v1('city', null, null, 'Oslo', 180, current_date);
