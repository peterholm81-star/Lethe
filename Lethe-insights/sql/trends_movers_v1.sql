-- ============================================================
-- TRENDS MOVERS V1: Rising / Falling / Emerging emotion tags
-- ============================================================
-- Compares 7-day current window to 28-day baseline (normalized
-- to 7-day equivalent). Used for the "Emotion Movers" panel on
-- the Trends page.
--
-- Data source: public.event_logs
--   Filter: event_name = 'post_success', emotion_bucket IS NOT NULL
--   Geo columns: region, country_code, city_code
--
-- Deploy: paste into Supabase Dashboard → SQL Editor → Run.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_trends_movers_v1(text, text, text, text, date);

CREATE OR REPLACE FUNCTION public.get_trends_movers_v1(
  p_scope    text DEFAULT 'global',
  p_region   text DEFAULT NULL,
  p_country  text DEFAULT NULL,
  p_city     text DEFAULT NULL,
  p_end_date date DEFAULT current_date
)
RETURNS TABLE (
  tag          text,
  current_7d   integer,
  baseline_28d integer,
  delta_pct    numeric,
  status       text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_start  date := p_end_date - 6;
  v_current_end    date := p_end_date;
  v_baseline_start date := p_end_date - 34;
  v_baseline_end   date := p_end_date - 7;
  -- Emerging thresholds
  v_emerging_baseline_max integer := 2;
  v_emerging_current_min  integer := 10;
BEGIN
  RETURN QUERY

  WITH current_window AS (
    SELECT
      UPPER(TRIM(e.emotion_bucket)) AS emo,
      COUNT(*)::integer             AS cnt
    FROM event_logs e
    WHERE e.created_at >= v_current_start::timestamptz
      AND e.created_at < (v_current_end + 1)::timestamptz
      AND e.event_name = 'post_success'
      AND e.emotion_bucket IS NOT NULL
      AND TRIM(e.emotion_bucket) <> ''
      AND (
        p_scope = 'global'
        OR (p_scope = 'region'  AND UPPER(TRIM(e.region))       = UPPER(TRIM(p_region)))
        OR (p_scope = 'country' AND UPPER(TRIM(e.country_code)) = UPPER(TRIM(p_country)))
        OR (p_scope = 'city'    AND UPPER(TRIM(e.city_code))    = UPPER(TRIM(p_city)))
      )
    GROUP BY UPPER(TRIM(e.emotion_bucket))
  ),

  baseline_window AS (
    SELECT
      UPPER(TRIM(e.emotion_bucket)) AS emo,
      COUNT(*)::integer             AS cnt
    FROM event_logs e
    WHERE e.created_at >= v_baseline_start::timestamptz
      AND e.created_at < (v_baseline_end + 1)::timestamptz
      AND e.event_name = 'post_success'
      AND e.emotion_bucket IS NOT NULL
      AND TRIM(e.emotion_bucket) <> ''
      AND (
        p_scope = 'global'
        OR (p_scope = 'region'  AND UPPER(TRIM(e.region))       = UPPER(TRIM(p_region)))
        OR (p_scope = 'country' AND UPPER(TRIM(e.country_code)) = UPPER(TRIM(p_country)))
        OR (p_scope = 'city'    AND UPPER(TRIM(e.city_code))    = UPPER(TRIM(p_city)))
      )
    GROUP BY UPPER(TRIM(e.emotion_bucket))
  ),

  combined AS (
    SELECT
      COALESCE(c.emo, b.emo)        AS emo,
      COALESCE(c.cnt, 0)            AS c7,
      COALESCE(b.cnt, 0)            AS b28
    FROM current_window c
    FULL OUTER JOIN baseline_window b ON b.emo = c.emo
  )

  SELECT
    x.emo                               AS tag,
    x.c7                                AS current_7d,
    x.b28                               AS baseline_28d,
    ROUND(
      (x.c7 - (x.b28::numeric / 4.0))
      / NULLIF(x.b28::numeric / 4.0, 0)
      * 100,
      1
    )                                    AS delta_pct,
    CASE
      WHEN x.b28 <= v_emerging_baseline_max AND x.c7 >= v_emerging_current_min
        THEN 'emerging'
      WHEN x.c7 > COALESCE(NULLIF(x.b28, 0)::numeric / 4.0, 0)
        THEN 'rising'
      ELSE 'falling'
    END                                  AS status
  FROM combined x
  WHERE x.c7 > 0 OR x.b28 > 0
  ORDER BY delta_pct DESC NULLS LAST;

END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trends_movers_v1(text, text, text, text, date)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SMOKE TESTS (run manually in SQL Editor)
-- ============================================================
-- select * from public.get_trends_movers_v1('global', null, null, null, current_date);
-- select * from public.get_trends_movers_v1('region', 'Europe', null, null, current_date);
-- select * from public.get_trends_movers_v1('country', null, 'NO', null, current_date);
