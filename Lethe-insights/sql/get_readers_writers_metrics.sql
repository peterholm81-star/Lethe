-- ============================================================
-- GET READERS WRITERS METRICS RPC (v1)
-- ============================================================
-- Returns readers vs writers metrics from daily_readers_writers
-- Always returns exactly 1 row (zeros if no data)
-- Uses _v1 suffix to avoid overload ambiguity
-- ============================================================

DROP FUNCTION IF EXISTS public.get_readers_writers_metrics_v1(text, text, date);

CREATE OR REPLACE FUNCTION public.get_readers_writers_metrics_v1(
  p_city   text DEFAULT 'WORLD',
  p_region text DEFAULT 'WORLD',
  p_date   date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  readers_today bigint,
  writers_today bigint,
  writer_share  numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_readers bigint;
  v_writers bigint;
  v_share   numeric;
BEGIN
  -- Get data for the requested date/city/region
  SELECT 
    drw.readers_today,
    drw.writers_today,
    drw.writer_share
  INTO v_readers, v_writers, v_share
  FROM daily_readers_writers drw
  WHERE drw.day_bucket = p_date
    AND drw.city_code = p_city
    AND drw.region = p_region
  LIMIT 1;

  -- Return zeros if no data found
  RETURN QUERY SELECT
    COALESCE(v_readers, 0)::bigint AS readers_today,
    COALESCE(v_writers, 0)::bigint AS writers_today,
    COALESCE(v_share, 0)::numeric  AS writer_share;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.get_readers_writers_metrics_v1(text, text, date) TO anon;
GRANT EXECUTE ON FUNCTION public.get_readers_writers_metrics_v1(text, text, date) TO authenticated;

-- Test (should return 100, 25, 0.25)
SELECT * FROM public.get_readers_writers_metrics_v1('WORLD', 'WORLD', '2026-02-04'::date);
