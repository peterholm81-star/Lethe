-- =============================================================================
-- RPC: get_reports_hotspots_v1
-- Returns top cities by report density (reports per 1k reads) for geo analysis.
-- =============================================================================
--
-- DEFINITIONS:
--   - reports_count: Number of reports in the period for that city
--   - reads_count: Distinct page_fetch sessions in the period for that city
--   - reports_per_1k: (reports_count / reads_count) * 1000
--   - top_reason: Most common report reason for that city
--
-- DATA SOURCES:
--   - Reports: confession_reports + confessions (for city_code)
--   - Reads: event_logs WHERE event_name = 'page_fetch'
--
-- V1.1: Excludes "Unknown" cities from ranking, adds data quality coverage fields
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_hotspots_v1(int, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_hotspots_v1(
  p_days int DEFAULT 7,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL  -- Reserved for future (not used in v1)
)
RETURNS TABLE (
  city_code text,
  city_label text,
  region text,
  country text,
  reports_count int,
  reads_count int,
  reports_per_1k numeric,
  top_reason text,
  top_reason_count int,
  -- Data quality coverage (same for all rows)
  total_reports_count int,
  unknown_reports_count int,
  unknown_reports_pct numeric,
  total_reads_count int,
  unknown_reads_count int,
  unknown_reads_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_total_reports int;
  v_unknown_reports int;
  v_total_reads int;
  v_unknown_reads int;
BEGIN
  -- Auth check (admin only)
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Calculate time window
  v_start := now() - (p_days || ' days')::interval;

  -- ==========================================================================
  -- CALCULATE DATA QUALITY TOTALS
  -- ==========================================================================
  
  -- Total reports in period (p_region='Unknown' matches NULL/empty/UNKNOWN)
  SELECT COUNT(*)::int INTO v_total_reports
  FROM confession_reports cr
  JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND c.region = p_region)
    );

  -- Unknown reports (city_code is null/empty/unknown)
  SELECT COUNT(*)::int INTO v_unknown_reports
  FROM confession_reports cr
  JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND c.region = p_region)
    )
    AND (c.city_code IS NULL OR TRIM(c.city_code) = '' OR UPPER(TRIM(c.city_code)) = 'UNKNOWN');

  -- Total reads in period
  SELECT COUNT(DISTINCT session_hash)::int INTO v_total_reads
  FROM event_logs el
  WHERE el.event_name = 'page_fetch'
    AND el.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (el.region IS NULL OR TRIM(el.region) = '' OR UPPER(TRIM(el.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND el.region = p_region)
    );

  -- Unknown reads (city_code is null/empty/unknown)
  SELECT COUNT(DISTINCT session_hash)::int INTO v_unknown_reads
  FROM event_logs el
  WHERE el.event_name = 'page_fetch'
    AND el.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (el.region IS NULL OR TRIM(el.region) = '' OR UPPER(TRIM(el.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND el.region = p_region)
    )
    AND (el.city_code IS NULL OR TRIM(el.city_code) = '' OR UPPER(TRIM(el.city_code)) = 'UNKNOWN');

  RETURN QUERY
  WITH
  -- ==========================================================================
  -- REPORTS per city (EXCLUDING unknown)
  -- ==========================================================================
  city_reports AS (
    SELECT
      TRIM(c.city_code) AS city_code,
      COALESCE(NULLIF(TRIM(c.region), ''), 'Unknown') AS region,
      COUNT(*)::int AS reports_count
    FROM confession_reports cr
    JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_start
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      -- Exclude unknown city_code
      AND c.city_code IS NOT NULL 
      AND TRIM(c.city_code) != ''
      AND UPPER(TRIM(c.city_code)) != 'UNKNOWN'
    GROUP BY 
      TRIM(c.city_code),
      COALESCE(NULLIF(TRIM(c.region), ''), 'Unknown')
    HAVING COUNT(*) > 0
  ),

  -- ==========================================================================
  -- READS per city (EXCLUDING unknown)
  -- ==========================================================================
  city_reads AS (
    SELECT
      TRIM(el.city_code) AS city_code,
      COUNT(DISTINCT el.session_hash)::int AS reads_count
    FROM event_logs el
    WHERE el.event_name = 'page_fetch'
      AND el.created_at >= v_start
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (el.region IS NULL OR TRIM(el.region) = '' OR UPPER(TRIM(el.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND el.region = p_region)
      )
      -- Exclude unknown city_code
      AND el.city_code IS NOT NULL
      AND TRIM(el.city_code) != ''
      AND UPPER(TRIM(el.city_code)) != 'UNKNOWN'
    GROUP BY TRIM(el.city_code)
  ),

  -- ==========================================================================
  -- TOP REASON per city (EXCLUDING unknown)
  -- ==========================================================================
  top_reasons AS (
    SELECT DISTINCT ON (city_code)
      TRIM(c.city_code) AS city_code,
      initcap(COALESCE(NULLIF(LOWER(TRIM(cr.reason)), ''), 'other')) AS top_reason,
      COUNT(*)::int AS reason_count
    FROM confession_reports cr
    JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_start
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      -- Exclude unknown city_code
      AND c.city_code IS NOT NULL
      AND TRIM(c.city_code) != ''
      AND UPPER(TRIM(c.city_code)) != 'UNKNOWN'
    GROUP BY 
      TRIM(c.city_code),
      LOWER(TRIM(cr.reason))
    ORDER BY 
      TRIM(c.city_code),
      COUNT(*) DESC
  ),

  -- ==========================================================================
  -- COMBINE: Join reports + reads + reasons
  -- ==========================================================================
  combined AS (
    SELECT
      rep.city_code,
      rep.city_code AS city_label,
      rep.region,
      NULL::text AS country,
      rep.reports_count,
      rd.reads_count,
      CASE 
        WHEN rd.reads_count IS NOT NULL AND rd.reads_count > 0 
        THEN ROUND((rep.reports_count::numeric / rd.reads_count) * 1000, 2)
        ELSE NULL
      END AS reports_per_1k,
      tr.top_reason,
      tr.reason_count AS top_reason_count
    FROM city_reports rep
    LEFT JOIN city_reads rd ON rd.city_code = rep.city_code
    LEFT JOIN top_reasons tr ON tr.city_code = rep.city_code
  )

  -- ==========================================================================
  -- RETURN: Top 10 cities + data quality coverage
  -- ==========================================================================
  SELECT
    comb.city_code,
    comb.city_label,
    comb.region,
    comb.country,
    comb.reports_count,
    comb.reads_count,
    comb.reports_per_1k,
    comb.top_reason,
    comb.top_reason_count,
    -- Data quality (same for all rows)
    v_total_reports AS total_reports_count,
    v_unknown_reports AS unknown_reports_count,
    CASE WHEN v_total_reports > 0 
      THEN ROUND((v_unknown_reports::numeric / v_total_reports) * 100, 1)
      ELSE 0
    END AS unknown_reports_pct,
    v_total_reads AS total_reads_count,
    v_unknown_reads AS unknown_reads_count,
    CASE WHEN v_total_reads > 0 
      THEN ROUND((v_unknown_reads::numeric / v_total_reads) * 100, 1)
      ELSE 0
    END AS unknown_reads_pct
  FROM combined comb
  ORDER BY 
    COALESCE(comb.reports_per_1k, 0) DESC,
    comb.reports_count DESC
  LIMIT 10;
END;
$$;

-- Grant execute to authenticated users (admin check is in function)
GRANT EXECUTE ON FUNCTION public.get_reports_hotspots_v1(int, text, text) TO authenticated;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_hotspots_v1(7, NULL, NULL);
-- SELECT * FROM public.get_reports_hotspots_v1(30, 'Europe', NULL);
