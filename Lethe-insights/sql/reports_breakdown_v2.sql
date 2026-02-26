-- =============================================================================
-- RPC: get_reports_breakdown_v2
-- Returns top reasons and top locations for Reports Intelligence dashboard.
-- =============================================================================
--
-- AUDIT NOTE (2026-02-03):
-- - confessions.region EXISTS
-- - confessions.city_code EXISTS
-- - confessions.country_code DOES NOT EXIST (p_country ignored)
-- - Uses confession_reports.created_at for time filtering
--
-- FIX (2026-02-03): Normalized reasons (case-insensitive) and improved region fallback
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_breakdown_v2(text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_breakdown_v2(
  p_range text DEFAULT '24h',
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- IGNORED (column doesn't exist)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  top_reasons jsonb,
  top_locations jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_total bigint;
  v_reasons jsonb;
  v_locations jsonb;
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
  -- COUNT TOTAL REPORTS (for percentage calculation)
  -- ==========================================================================
  SELECT COALESCE(COUNT(*), 0)
  INTO v_total
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND c.region = p_region)
    )
    AND (p_city IS NULL OR c.city_code = p_city);

  -- ==========================================================================
  -- TOP REASONS (normalized: case-insensitive, trimmed)
  -- Group by normalized reason, top 6
  -- Output: initcap for pretty display (Spam, Identifying, etc.)
  -- ==========================================================================
  IF v_total > 0 THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)::jsonb ORDER BY r.count DESC), '[]'::jsonb)
    INTO v_reasons
    FROM (
      SELECT
        initcap(COALESCE(NULLIF(LOWER(TRIM(cr.reason)), ''), 'other')) AS key,
        COUNT(*)::bigint AS count,
        ROUND((COUNT(*)::numeric / v_total) * 100, 1) AS pct
      FROM confession_reports cr
      LEFT JOIN confessions c ON c.id = cr.confession_id
      WHERE cr.created_at >= v_start
        AND (
          p_region IS NULL 
          OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
          OR (p_region != 'Unknown' AND c.region = p_region)
        )
        AND (p_city IS NULL OR c.city_code = p_city)
      GROUP BY LOWER(TRIM(cr.reason))
      ORDER BY COUNT(*) DESC
      LIMIT 6
    ) r;
  ELSE
    v_reasons := '[]'::jsonb;
  END IF;

  -- ==========================================================================
  -- TOP LOCATIONS (with improved region fallback)
  -- If p_region is NULL: group by region (top 6)
  -- If p_region is set: group by city_code (top 6)
  -- Region fallback: region -> city_code -> 'Unknown'
  -- ==========================================================================
  IF v_total > 0 THEN
    IF p_region IS NULL THEN
      -- Group by region (with fallback chain)
      SELECT COALESCE(jsonb_agg(row_to_json(r)::jsonb ORDER BY r.count DESC), '[]'::jsonb)
      INTO v_locations
      FROM (
        SELECT
          COALESCE(
            NULLIF(TRIM(c.region), ''),
            NULLIF(TRIM(c.city_code), ''),
            'Unknown'
          ) AS key,
          COUNT(*)::bigint AS count,
          ROUND((COUNT(*)::numeric / v_total) * 100, 1) AS pct
        FROM confession_reports cr
        LEFT JOIN confessions c ON c.id = cr.confession_id
        WHERE cr.created_at >= v_start
          AND (p_city IS NULL OR c.city_code = p_city)
        GROUP BY COALESCE(
          NULLIF(TRIM(c.region), ''),
          NULLIF(TRIM(c.city_code), ''),
          'Unknown'
        )
        ORDER BY COUNT(*) DESC
        LIMIT 6
      ) r;
    ELSE
      -- Group by city_code (region is already filtered)
      SELECT COALESCE(jsonb_agg(row_to_json(r)::jsonb ORDER BY r.count DESC), '[]'::jsonb)
      INTO v_locations
      FROM (
        SELECT
          COALESCE(NULLIF(TRIM(c.city_code), ''), 'Unknown') AS key,
          COUNT(*)::bigint AS count,
          ROUND((COUNT(*)::numeric / v_total) * 100, 1) AS pct
        FROM confession_reports cr
        LEFT JOIN confessions c ON c.id = cr.confession_id
        WHERE cr.created_at >= v_start
          AND c.region = p_region
          AND (p_city IS NULL OR c.city_code = p_city)
        GROUP BY COALESCE(NULLIF(TRIM(c.city_code), ''), 'Unknown')
        ORDER BY COUNT(*) DESC
        LIMIT 6
      ) r;
    END IF;
  ELSE
    v_locations := '[]'::jsonb;
  END IF;

  -- ==========================================================================
  -- RETURN (always 1 row)
  -- ==========================================================================
  RETURN QUERY SELECT v_reasons, v_locations;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_reports_breakdown_v2(text, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_breakdown_v2('24h', NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_breakdown_v2('7d', 'Europe', NULL, NULL);
-- SELECT * FROM public.get_reports_breakdown_v2('7d', 'Europe', NULL, 'TRD');
