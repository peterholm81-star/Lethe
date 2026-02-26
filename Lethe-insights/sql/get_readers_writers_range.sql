-- ============================================================
-- READERS VS WRITERS RANGE RPC: get_readers_writers_range
-- ============================================================
-- Returns readers vs writers metrics for a timestamp range.
--
-- DEFINITIONS:
--   readers = COUNT(DISTINCT session_hash) WHERE event_name='page_fetch'
--   writers = COUNT(DISTINCT session_hash) WHERE event_name='post_success'
--   writer_share = writers / readers (0..1)
--
-- PARAMETERS:
--   p_start_ts: Start of window (inclusive, timestamptz ISO)
--   p_end_ts:   End of window (exclusive, timestamptz ISO)
--   p_region, p_country_code, p_city_code, p_mode: Lens filters (nullable)
-- ============================================================

DROP FUNCTION IF EXISTS public.get_readers_writers_range(timestamptz, timestamptz, text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_readers_writers_range(
  p_start_ts timestamptz,
  p_end_ts timestamptz,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL
)
RETURNS TABLE (
  readers bigint,
  writers bigint,
  writer_share numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_readers bigint;
  v_writers bigint;
BEGIN
  -- Readers: distinct sessions that loaded at least one page
  SELECT COUNT(DISTINCT session_hash) INTO v_readers
  FROM event_logs
  WHERE event_name = 'page_fetch'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
    AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
    AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
    AND (p_mode IS NULL OR mode = p_mode);

  -- Writers: distinct sessions that posted successfully
  SELECT COUNT(DISTINCT session_hash) INTO v_writers
  FROM event_logs
  WHERE event_name = 'post_success'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
    AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
    AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
    AND (p_mode IS NULL OR mode = p_mode);

  RETURN QUERY SELECT
    v_readers,
    v_writers,
    CASE WHEN v_readers > 0 
      THEN ROUND(v_writers::numeric / v_readers, 3)
      ELSE 0::numeric
    END AS writer_share;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_readers_writers_range(timestamptz, timestamptz, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_readers_writers_range(timestamptz, timestamptz, text, text, text, text) TO authenticated;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST
-- ============================================================
SELECT * FROM public.get_readers_writers_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL, NULL, NULL, NULL
);
