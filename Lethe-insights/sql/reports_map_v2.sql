-- =============================================================================
-- RPC: get_reports_map_v2
-- Returns geo markers for report activity visualization on map.
-- =============================================================================
--
-- AUDIT NOTE (2026-02-03):
-- - confessions.region EXISTS
-- - confessions.city_code EXISTS
-- - confessions.lat, lng EXISTS
-- - confessions.created_at EXISTS
-- - confessions.is_hidden EXISTS
-- - confessions.country_code DOES NOT EXIST (p_country ignored)
-- - confessions.updated_at DOES NOT EXIST
-- - Groups by city_code + region for marker points
--
-- FIX (2026-02-03): Rewrote to use CTEs to avoid "ungrouped column" error
-- FIX (2026-02-03): Normalized top_reason (case-insensitive, initcap display)
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_map_v2(text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_map_v2(
  p_range text DEFAULT '24h',
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- IGNORED in v1 (column doesn't exist)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  markers jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_markers jsonb;
BEGIN
  -- Determine time range start
  v_start := CASE p_range
    WHEN '60m' THEN now() - interval '60 minutes'
    WHEN '24h' THEN now() - interval '24 hours'
    WHEN '7d'  THEN now() - interval '7 days'
    WHEN '30d' THEN now() - interval '30 days'
    ELSE now() - interval '24 hours'  -- default fallback
  END;

  -- ==========================================================================
  -- BUILD MARKERS ARRAY using CTEs to avoid correlated subquery issues
  -- ==========================================================================
  WITH
  -- CTE 1: Base reports with normalized city/region/reason
  report_base AS (
    SELECT
      COALESCE(NULLIF(TRIM(c.city_code), ''), 'unknown') AS city_code,
      COALESCE(NULLIF(TRIM(c.region), ''), 'Unknown') AS region,
      c.lat,
      c.lng,
      c.is_hidden,
      -- Normalize reason: lowercase, trimmed
      LOWER(TRIM(cr.reason)) AS reason_norm
    FROM confession_reports cr
    JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_start
      AND c.lat IS NOT NULL
      AND c.lng IS NOT NULL
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      AND (p_city IS NULL OR c.city_code = p_city)
  ),
  -- CTE 2: Top reason per city_code + region (normalized + initcap for display)
  top_reasons AS (
    SELECT DISTINCT ON (city_code, region)
      city_code,
      region,
      initcap(COALESCE(NULLIF(reason_norm, ''), 'other')) AS top_reason
    FROM (
      SELECT
        city_code,
        region,
        reason_norm,
        COUNT(*) AS reason_count
      FROM report_base
      GROUP BY city_code, region, reason_norm
    ) reason_counts
    ORDER BY city_code, region, reason_count DESC
  ),
  -- CTE 3: Aggregated markers
  marker_agg AS (
    SELECT
      rb.city_code,
      rb.region,
      ROUND(AVG(rb.lat)::numeric, 4) AS lat,
      ROUND(AVG(rb.lng)::numeric, 4) AS lng,
      COUNT(*)::bigint AS reports,
      COUNT(*) FILTER (WHERE rb.is_hidden = true)::bigint AS hidden
    FROM report_base rb
    GROUP BY rb.city_code, rb.region
  )
  -- Final select: join aggregates with top reasons
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'city_code', ma.city_code,
        'region', ma.region,
        'lat', ma.lat,
        'lng', ma.lng,
        'reports', ma.reports,
        'hidden', ma.hidden,
        'top_reason', tr.top_reason
      )
      ORDER BY ma.reports DESC
    ),
    '[]'::jsonb
  )
  INTO v_markers
  FROM marker_agg ma
  LEFT JOIN top_reasons tr
    ON tr.city_code = ma.city_code
    AND tr.region = ma.region
  WHERE ma.lat IS NOT NULL AND ma.lng IS NOT NULL;

  -- ==========================================================================
  -- RETURN (always 1 row)
  -- ==========================================================================
  RETURN QUERY SELECT v_markers;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_reports_map_v2(text, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_map_v2('24h'::text, NULL::text, NULL::text, NULL::text);
-- SELECT * FROM public.get_reports_map_v2('7d'::text, 'Europe'::text, NULL::text, NULL::text);
-- SELECT * FROM public.get_reports_map_v2('30d'::text, NULL::text, NULL::text, NULL::text);
