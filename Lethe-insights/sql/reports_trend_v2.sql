-- =============================================================================
-- RPC: get_reports_trend_v2
-- Returns time-bucketed report counts for trend chart in Reports Intelligence.
-- =============================================================================
--
-- AUDIT NOTE (2026-02-03):
-- - confessions.region EXISTS
-- - confessions.city_code EXISTS
-- - confessions.created_at EXISTS
-- - confessions.country_code DOES NOT EXIST (p_country ignored)
-- - confessions.updated_at DOES NOT EXIST (using created_at)
-- - Bucket rule: hour for 60m/24h, day for 7d/30d
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_trend_v2(text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_trend_v2(
  p_range text DEFAULT '24h',
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- IGNORED in v1 (column doesn't exist)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  trend jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_bucket text;
  v_label_format text;
  v_trend jsonb;
BEGIN
  -- Determine time range start
  v_start := CASE p_range
    WHEN '60m' THEN now() - interval '60 minutes'
    WHEN '24h' THEN now() - interval '24 hours'
    WHEN '7d'  THEN now() - interval '7 days'
    WHEN '30d' THEN now() - interval '30 days'
    ELSE now() - interval '24 hours'  -- default fallback
  END;

  -- Determine bucket granularity
  IF p_range IN ('60m', '24h') THEN
    v_bucket := 'hour';
    v_label_format := 'HH24:00';
  ELSE
    v_bucket := 'day';
    v_label_format := 'YYYY-MM-DD';
  END IF;

  -- ==========================================================================
  -- BUILD TREND ARRAY
  -- Group reports by time bucket, filtered by geo
  -- ==========================================================================
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'ts', r.bucket_ts,
        'label', r.bucket_label,
        'count', r.cnt
      )
      ORDER BY r.bucket_ts ASC
    ),
    '[]'::jsonb
  )
  INTO v_trend
  FROM (
    SELECT
      date_trunc(v_bucket, cr.created_at) AS bucket_ts,
      to_char(date_trunc(v_bucket, cr.created_at), v_label_format) AS bucket_label,
      COUNT(*)::bigint AS cnt
    FROM confession_reports cr
    LEFT JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_start
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      AND (p_city IS NULL OR c.city_code = p_city)
    GROUP BY date_trunc(v_bucket, cr.created_at)
    ORDER BY date_trunc(v_bucket, cr.created_at) ASC
  ) r;

  -- ==========================================================================
  -- RETURN (always 1 row)
  -- ==========================================================================
  RETURN QUERY SELECT v_trend;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_reports_trend_v2(text, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_trend_v2('24h'::text, NULL::text, NULL::text, NULL::text);
-- SELECT * FROM public.get_reports_trend_v2('7d'::text, 'Europe'::text, NULL::text, NULL::text);
-- SELECT * FROM public.get_reports_trend_v2('30d'::text, NULL::text, NULL::text, NULL::text);
