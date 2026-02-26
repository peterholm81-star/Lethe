-- ============================================================
-- GET LATEST METRICS DAY RPC
-- ============================================================
-- Returns the most recent day_bucket that has actual data
-- Used for fallback when "today" has no metrics
-- ============================================================

DROP FUNCTION IF EXISTS public.get_latest_metrics_day(text, text);

CREATE OR REPLACE FUNCTION public.get_latest_metrics_day(
  p_city text DEFAULT 'WORLD',
  p_region text DEFAULT 'WORLD'
)
RETURNS TABLE (day_bucket date)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT dm.day_bucket
  FROM daily_metrics dm
  WHERE (
    dm.sessions > 0 
    OR dm.readers > 0 
    OR dm.post_success > 0
  )
  AND (p_city = 'WORLD' OR dm.city_code = p_city)
  AND (p_region = 'WORLD' OR dm.region = p_region)
  ORDER BY dm.day_bucket DESC
  LIMIT 1;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.get_latest_metrics_day(text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_latest_metrics_day(text, text) TO authenticated;

-- Test
SELECT * FROM public.get_latest_metrics_day();
