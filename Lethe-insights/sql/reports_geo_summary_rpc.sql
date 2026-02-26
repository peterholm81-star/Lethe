-- ============================================================
-- RPC: get_reports_geo_summary_v1
-- ============================================================
-- Returns top cities by report count for the last N days.
-- Used for "Geo for Reports" section in ReportsPage.
--
-- Parameters:
-- - p_days int (default 7) - number of days to look back
--
-- Returns:
-- - city_code: the city code (e.g., 'TRD', 'OSL')
-- - report_count: number of reports from that city
--
-- Security (v1):
-- - Open to all authenticated users (no admin check).
-- - Returns only aggregated counts, no PII.
-- - Stricter role-based access may be added in v2 if needed.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_reports_geo_summary_v1(int);

CREATE OR REPLACE FUNCTION public.get_reports_geo_summary_v1(
  p_days int DEFAULT 7
)
RETURNS TABLE (
  city_code text,
  report_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- v1: No admin check - returns only aggregated geo data (no PII).
  -- Add role-based access in v2 if needed.

  RETURN QUERY
  SELECT
    cr.city_code,
    COUNT(*)::bigint AS report_count
  FROM confession_reports cr
  WHERE cr.created_at > now() - (p_days || ' days')::interval
    AND cr.city_code IS NOT NULL
    AND TRIM(cr.city_code) <> ''
  GROUP BY cr.city_code
  ORDER BY COUNT(*) DESC
  LIMIT 10;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_reports_geo_summary_v1(int) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Test query (run in SQL Editor after deploying)
-- ============================================================
-- SELECT * FROM public.get_reports_geo_summary_v1(7);
-- SELECT * FROM public.get_reports_geo_summary_v1(30);
