-- =============================================================================
-- RPC: get_reports_spike_explain_v1
-- Returns spike detection with explanation (top reason, location, delta).
-- =============================================================================
--
-- SPIKE DETECTION:
-- - Compares recent window vs previous window
-- - window_hours based on p_days: 1d->6h, 7d->24h, 30d->72h
-- - Spike = pct_increase >= 50% AND delta >= 3 AND prev_reports >= 5
--
-- OUTPUT:
-- - spike_detected: boolean
-- - window_hours: size of comparison window
-- - recent/prev timestamps
-- - recent/prev/delta report counts
-- - pct_increase
-- - top_reason, top_region, top_city from recent window
--
-- SCHEMA NOTES:
-- - Reports are in confession_reports table
-- - confession_reports.city_code exists
-- - confession_reports does NOT have region/country_code directly
-- - confessions.region exists, confessions.country_code does NOT exist
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_spike_explain_v1(int, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_spike_explain_v1(
  p_days int DEFAULT 7,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- Not used (no country_code in confessions)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  spike_detected boolean,
  window_hours int,
  recent_start timestamptz,
  recent_end timestamptz,
  prev_start timestamptz,
  prev_end timestamptz,
  recent_reports int,
  prev_reports int,
  delta_reports int,
  pct_increase numeric,
  top_reason text,
  top_region text,
  top_city text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_hours int;
  v_recent_end timestamptz := now();
  v_recent_start timestamptz;
  v_prev_end timestamptz;
  v_prev_start timestamptz;
BEGIN
  -- Auth check: require authenticated user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access denied: authentication required';
  END IF;

  -- Determine window size based on p_days
  v_window_hours :=
    CASE
      WHEN p_days <= 1 THEN 6    -- 6h window for 1 day view
      WHEN p_days <= 7 THEN 24   -- 24h window for 7 day view
      ELSE 72                     -- 72h window for 30 day view
    END;

  -- Calculate time windows
  v_recent_start := v_recent_end - make_interval(hours => v_window_hours);
  v_prev_end := v_recent_start;
  v_prev_start := v_prev_end - make_interval(hours => v_window_hours);

  RETURN QUERY
  WITH 
  -- Base reports with normalized reason and geo data
  base AS (
    SELECT
      cr.id,
      cr.created_at,
      LOWER(TRIM(COALESCE(cr.reason, 'other'))) AS reason_norm,
      initcap(LOWER(TRIM(COALESCE(cr.reason, 'other')))) AS reason_display,
      NULLIF(TRIM(cr.city_code), '') AS city_code,
      c.region
    FROM confession_reports cr
    LEFT JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_prev_start  -- Include both windows
      -- Geo filters (p_region='Unknown' matches NULL/empty/UNKNOWN)
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      AND (p_city IS NULL OR cr.city_code = p_city)
      -- p_country is ignored (no country_code column in confessions)
  ),
  
  -- Recent window reports
  recent AS (
    SELECT * FROM base
    WHERE created_at >= v_recent_start AND created_at < v_recent_end
  ),
  
  -- Previous window reports
  prev AS (
    SELECT * FROM base
    WHERE created_at >= v_prev_start AND created_at < v_prev_end
  ),
  
  -- Count totals
  counts AS (
    SELECT
      (SELECT COUNT(*) FROM recent)::int AS recent_reports,
      (SELECT COUNT(*) FROM prev)::int AS prev_reports
  ),
  
  -- Top reason in recent window
  top_reason_cte AS (
    SELECT reason_display AS reason_val
    FROM recent
    GROUP BY reason_display
    ORDER BY COUNT(*) DESC, reason_display ASC
    LIMIT 1
  ),
  
  -- Top region in recent window
  top_region_cte AS (
    SELECT COALESCE(region, 'Unknown') AS region_val
    FROM recent
    GROUP BY COALESCE(region, 'Unknown')
    ORDER BY COUNT(*) DESC, COALESCE(region, 'Unknown') ASC
    LIMIT 1
  ),
  
  -- Top city in recent window
  top_city_cte AS (
    SELECT COALESCE(city_code, '—') AS city_val
    FROM recent
    GROUP BY COALESCE(city_code, '—')
    ORDER BY COUNT(*) DESC, COALESCE(city_code, '—') ASC
    LIMIT 1
  ),
  
  -- Compute delta and percentage
  computed AS (
    SELECT
      c.recent_reports,
      c.prev_reports,
      (c.recent_reports - c.prev_reports)::int AS delta_reports,
      CASE
        WHEN c.prev_reports = 0 THEN NULL
        ELSE ROUND(((c.recent_reports - c.prev_reports)::numeric / c.prev_reports::numeric) * 100, 1)
      END AS pct_increase
    FROM counts c
  )
  
  SELECT
    -- Spike detected if: pct >= 50% AND delta >= 3 AND prev >= 5
    (
      (COALESCE(comp.pct_increase, 0) >= 50)
      AND (comp.delta_reports >= 3)
      AND (comp.prev_reports >= 5)
    ) AS spike_detected,
    v_window_hours AS window_hours,
    v_recent_start AS recent_start,
    v_recent_end AS recent_end,
    v_prev_start AS prev_start,
    v_prev_end AS prev_end,
    comp.recent_reports,
    comp.prev_reports,
    comp.delta_reports,
    COALESCE(comp.pct_increase, 0)::numeric AS pct_increase,
    (SELECT trc.reason_val FROM top_reason_cte trc) AS top_reason,
    (SELECT trg.region_val FROM top_region_cte trg) AS top_region,
    (SELECT tcc.city_val FROM top_city_cte tcc) AS top_city
  FROM computed comp;
END;
$$;

-- Grant execute to authenticated users (read-only metrics, no admin required)
GRANT EXECUTE ON FUNCTION public.get_reports_spike_explain_v1(int, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_spike_explain_v1(7, NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_spike_explain_v1(1, NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_spike_explain_v1(30, 'Europe', NULL, NULL);
