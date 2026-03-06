-- ============================================================
-- TRENDS V1: Period comparison + daily trendline RPCs
-- ============================================================
-- Source: event_logs (same as get_pulse_metrics_range, etc.)
-- Event names: session_start, page_fetch, post_success, ad_shown
-- ============================================================

-- ============================================================
-- RPC 1: get_trends_comparison_v1
-- ============================================================
-- Compares two adjacent windows of p_days length.
-- current  = (p_end_date - p_days + 1) .. p_end_date
-- previous = (p_end_date - 2*p_days + 1) .. (p_end_date - p_days)
--
-- scope: 'global'  → one row per metric
--        'country' → one row per metric per country_code
--
-- Returns metric_key in {sessions, reads, posts, ads_shown}
-- ============================================================

DROP FUNCTION IF EXISTS public.get_trends_comparison_v1(text, text, int, date);

CREATE OR REPLACE FUNCTION public.get_trends_comparison_v1(
  p_scope text DEFAULT 'global',
  p_region text DEFAULT NULL,
  p_days int DEFAULT 7,
  p_end_date date DEFAULT current_date
)
RETURNS TABLE (
  scope_key   text,
  metric_key  text,
  current_value numeric,
  previous_value numeric,
  delta_abs   numeric,
  delta_pct   numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cur_start date := p_end_date - p_days + 1;
  v_cur_end   date := p_end_date + 1;       -- exclusive
  v_prev_start date := p_end_date - 2 * p_days + 1;
  v_prev_end   date := p_end_date - p_days + 1; -- exclusive
BEGIN
  RETURN QUERY
  WITH raw AS (
    SELECT
      CASE WHEN p_scope = 'country' THEN UPPER(TRIM(country_code)) ELSE 'GLOBAL' END AS sk,
      event_name,
      session_hash,
      CASE
        WHEN created_at >= v_cur_start::timestamptz AND created_at < v_cur_end::timestamptz THEN 'cur'
        WHEN created_at >= v_prev_start::timestamptz AND created_at < v_prev_end::timestamptz THEN 'prev'
      END AS period
    FROM event_logs
    WHERE created_at >= v_prev_start::timestamptz
      AND created_at < v_cur_end::timestamptz
      AND event_name IN ('session_start', 'page_fetch', 'post_success', 'ad_shown')
      AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
  ),
  agg AS (
    SELECT
      sk,
      period,
      CASE event_name
        WHEN 'session_start' THEN 'sessions'
        WHEN 'page_fetch'    THEN 'reads'
        WHEN 'post_success'  THEN 'posts'
        WHEN 'ad_shown'      THEN 'ads_shown'
      END AS mk,
      CASE event_name
        WHEN 'session_start' THEN COUNT(DISTINCT session_hash)
        ELSE COUNT(*)
      END AS val
    FROM raw
    WHERE period IS NOT NULL
    GROUP BY sk, period, event_name
  ),
  pivoted AS (
    SELECT
      sk,
      mk,
      SUM(CASE WHEN period = 'cur'  THEN val ELSE 0 END)::numeric AS cv,
      SUM(CASE WHEN period = 'prev' THEN val ELSE 0 END)::numeric AS pv
    FROM agg
    GROUP BY sk, mk
  )
  SELECT
    p.sk       AS scope_key,
    p.mk       AS metric_key,
    p.cv       AS current_value,
    p.pv       AS previous_value,
    (p.cv - p.pv) AS delta_abs,
    CASE WHEN p.pv > 0
      THEN ROUND(((p.cv - p.pv) / p.pv) * 100, 1)
      ELSE NULL
    END AS delta_pct
  FROM pivoted p
  WHERE p.cv > 0 OR p.pv > 0
  ORDER BY p.sk, p.mk;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trends_comparison_v1(text, text, int, date)
  TO anon, authenticated;

-- ============================================================
-- RPC 2: get_trends_trendline_v1
-- ============================================================
-- Returns daily values for specified metrics over p_days,
-- for charting trendlines.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_trends_trendline_v1(text, int, date);

CREATE OR REPLACE FUNCTION public.get_trends_trendline_v1(
  p_region text DEFAULT NULL,
  p_days int DEFAULT 30,
  p_end_date date DEFAULT current_date
)
RETURNS TABLE (
  day         date,
  metric_key  text,
  value       numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date := p_end_date - p_days + 1;
  v_end   date := p_end_date + 1;
BEGIN
  RETURN QUERY

  -- Sessions (distinct session_hash)
  SELECT d.db::date, 'sessions'::text, COUNT(DISTINCT e.session_hash)::numeric
  FROM generate_series(v_start::date, p_end_date::date, '1 day'::interval) AS d(db)
  LEFT JOIN event_logs e
    ON DATE(e.created_at AT TIME ZONE 'UTC') = d.db::date
    AND e.event_name = 'session_start'
    AND (p_region IS NULL OR UPPER(TRIM(e.region)) = UPPER(TRIM(p_region)))
  GROUP BY d.db::date

  UNION ALL

  -- Posts
  SELECT d.db::date, 'posts'::text, COUNT(e.id)::numeric
  FROM generate_series(v_start::date, p_end_date::date, '1 day'::interval) AS d(db)
  LEFT JOIN event_logs e
    ON DATE(e.created_at AT TIME ZONE 'UTC') = d.db::date
    AND e.event_name = 'post_success'
    AND (p_region IS NULL OR UPPER(TRIM(e.region)) = UPPER(TRIM(p_region)))
  GROUP BY d.db::date

  ORDER BY 1, 2;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trends_trendline_v1(text, int, date)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST
-- ============================================================
-- SELECT * FROM get_trends_comparison_v1('global', NULL, 7, current_date);
-- SELECT * FROM get_trends_comparison_v1('country', NULL, 7, current_date);
-- SELECT * FROM get_trends_trendline_v1(NULL, 30, current_date);
