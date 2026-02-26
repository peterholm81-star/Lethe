-- ============================================================
-- RPC: get_reports_reasons_trend
-- ============================================================
-- Returns top reasons with trend data (today vs yesterday).
-- Used for "Top Reasons" section with delta and spike detection.
--
-- Parameters:
-- - p_date text (YYYY-MM-DD) - required
-- - p_city text - reserved for future (ignored in v1)
-- - p_region text - reserved for future (ignored in v1)
-- - p_limit integer - max reasons to return (default 5, max 20)
--
-- Returns:
-- - reason: the report reason
-- - count_today: reports today
-- - count_yesterday: reports yesterday
-- - delta: count_today - count_yesterday
-- - pct_change: percentage change (999 if yesterday was 0)
-- - is_spike: true if count_today >= 1.5x yesterday AND count_today >= 3
-- ============================================================

DROP FUNCTION IF EXISTS public.get_reports_reasons_trend(text, text, text, integer);

CREATE OR REPLACE FUNCTION public.get_reports_reasons_trend(
  p_date text,
  p_city text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_limit integer DEFAULT 5
)
RETURNS TABLE (
  reason text,
  count_today bigint,
  count_yesterday bigint,
  delta bigint,
  pct_change numeric,
  is_spike boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date date;
  v_yesterday date;
BEGIN
  -- Admin gate
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  v_date := p_date::date;
  v_yesterday := (p_date::date - 1);

  -- NOTE: In v1 we ignore p_city/p_region (not linked to reasons yet).
  -- Data source: confession_reports (same as Reports inbox).

  RETURN QUERY
  WITH
  today AS (
    SELECT
      COALESCE(cr.reason, 'OTHER')::text AS reason,
      COUNT(*)::bigint AS count_today
    FROM confession_reports cr
    WHERE cr.created_at::date = v_date
    GROUP BY COALESCE(cr.reason, 'OTHER')
  ),
  yesterday AS (
    SELECT
      COALESCE(cr.reason, 'OTHER')::text AS reason,
      COUNT(*)::bigint AS count_yesterday
    FROM confession_reports cr
    WHERE cr.created_at::date = v_yesterday
    GROUP BY COALESCE(cr.reason, 'OTHER')
  ),
  merged AS (
    SELECT
      COALESCE(t.reason, y.reason) AS reason,
      COALESCE(t.count_today, 0) AS count_today,
      COALESCE(y.count_yesterday, 0) AS count_yesterday
    FROM today t
    FULL OUTER JOIN yesterday y USING (reason)
  )
  SELECT
    m.reason,
    m.count_today,
    m.count_yesterday,
    (m.count_today - m.count_yesterday) AS delta,
    CASE
      WHEN m.count_yesterday = 0 AND m.count_today > 0 THEN 999
      WHEN m.count_yesterday = 0 AND m.count_today = 0 THEN 0
      ELSE ROUND(((m.count_today::numeric - m.count_yesterday::numeric) / NULLIF(m.count_yesterday::numeric, 0)) * 100, 1)
    END AS pct_change,
    (
      m.count_today >= GREATEST((m.count_yesterday * 1.5)::bigint, 1)
      AND m.count_today >= 3
    ) AS is_spike
  FROM merged m
  ORDER BY m.count_today DESC, m.reason ASC
  LIMIT GREATEST(1, LEAST(p_limit, 20));

END;
$$;

-- Grant execute to authenticated (admin check is in function)
GRANT EXECUTE ON FUNCTION public.get_reports_reasons_trend(text, text, text, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Test query (run in SQL Editor after deploying)
-- ============================================================
-- SELECT * FROM public.get_reports_reasons_trend(CURRENT_DATE::text, NULL, NULL, 5);
