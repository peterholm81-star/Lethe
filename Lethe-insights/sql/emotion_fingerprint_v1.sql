-- ============================================================
-- EMOTION FINGERPRINT V1: Monthly counts per emotion bucket
-- ============================================================
-- Returns one row per month × emotion for the requested window.
-- Used to build a radar/spider chart showing how each emotion
-- waxes and wanes across the year (seasonality rhythm).
--
-- Data source: public.confession_metrics_daily
--   Columns: date, mood_bucket, count, region, country_code, city_code
--   Valid buckets: joy, love, calm, hope, gratitude, confidence,
--                  anxiety, sadness, anger, loneliness, desire, shame
--
-- Deploy: paste into Supabase Dashboard → SQL Editor → Run.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_emotion_fingerprint_v1(text, text, text, text, int, date);

CREATE OR REPLACE FUNCTION public.get_emotion_fingerprint_v1(
  p_scope    text    DEFAULT 'global',
  p_region   text    DEFAULT NULL,
  p_country  text    DEFAULT NULL,
  p_city     text    DEFAULT NULL,
  p_days     integer DEFAULT 365,
  p_end_date date    DEFAULT current_date
)
RETURNS TABLE (
  month_start date,
  emotion     text,
  count       integer
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
BEGIN
  RETURN QUERY

  WITH agg AS (
    SELECT
      date_trunc('month', cmd.date)::date AS m,
      LOWER(TRIM(cmd.mood_bucket))        AS emo,
      SUM(cmd.count)::integer             AS cnt
    FROM confession_metrics_daily cmd
    WHERE cmd.date >= v_start
      AND cmd.date <= v_end
      AND cmd.mood_bucket IS NOT NULL
      AND TRIM(cmd.mood_bucket) <> ''
      AND (
        p_scope = 'global'
        OR (p_scope = 'region'  AND UPPER(TRIM(cmd.region))       = UPPER(TRIM(p_region)))
        OR (p_scope = 'country' AND UPPER(TRIM(cmd.country_code)) = UPPER(TRIM(p_country)))
        OR (p_scope = 'city'    AND UPPER(TRIM(cmd.city_code))    = UPPER(TRIM(p_city)))
      )
    GROUP BY date_trunc('month', cmd.date)::date, LOWER(TRIM(cmd.mood_bucket))
  )

  SELECT
    a.m   AS month_start,
    a.emo AS emotion,
    a.cnt AS count
  FROM agg a
  ORDER BY a.m, a.emo;

END;
$$;

GRANT EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(text, text, text, text, int, date)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SMOKE TESTS (run manually in SQL Editor)
-- ============================================================
-- select * from public.get_emotion_fingerprint_v1('global', null, null, null, 365, current_date);
-- select * from public.get_emotion_fingerprint_v1('region', 'Europe', null, null, 365, current_date);
-- select emotion, sum(count) from public.get_emotion_fingerprint_v1('global', null, null, null, 365, current_date) group by emotion order by 2 desc;
