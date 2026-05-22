-- =============================================================================
-- Migration 050: Harden public.get_reports_map_v2
--
-- Phase: Production Hardening — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) LANGUAGE sql version of
--   get_reports_map_v2 with a production-safe, admin-gated plpgsql RPC.
--
--   This function returns a JSONB array of per-city map markers, each
--   containing the city's lat/lng centroid, total report count, hidden
--   count, and top report reason. It reads from public.reports joined to
--   public.confessions (including lat/lng coordinates). This data is dense
--   moderation geo-intelligence and must be admin-only.
--
-- Security changes applied:
--   - Language changed sql → plpgsql (required for the admin gate)
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows; frontend ReportsPage.tsx
--     handles empty result at lines 1026-1028 by calling setMapMarkers([])
--   - REVOKE ALL FROM PUBLIC and REVOKE EXECUTE FROM anon
--   - GRANT EXECUTE TO authenticated only
--
-- Frontend contract preserved (ReportsPage.tsx):
--   - Same name: get_reports_map_v2
--   - Same parameters with same defaults:
--       p_range   text DEFAULT '7d'
--       p_region  text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city    text DEFAULT NULL
--   - Same return shape (single-row table):
--       markers jsonb  (array of {city_code, region, lat, lng, reports,
--                       hidden, top_reason} objects, ordered by reports DESC)
--
-- No plpgsql shadowing risk: the single output column "markers" does not
-- appear as a column name in any CTE, so all internal references are
-- unambiguous.
--
-- Note: calls public._lethe_reports_range_days() — safe because SECURITY
-- DEFINER functions execute as the postgres owner, bypassing grant checks.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_map_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  markers JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — the frontend treats an empty
  -- result as an empty map (ReportsPage.tsx lines 1026-1028).
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH params AS (
    SELECT public._lethe_reports_range_days(p_range) AS days
  ),
  reps AS (
    SELECT rep.reason, c.city_code AS rep_city, c.region AS rep_region,
           c.lat AS rep_lat, c.lng AS rep_lng, c.is_hidden
    FROM public.reports rep
    JOIN public.confessions c ON c.id = rep.confession_id
    CROSS JOIN params p
    WHERE rep.created_at >= now() - make_interval(days => p.days)
      AND c.lat IS NOT NULL
      AND c.lng IS NOT NULL
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
  ),
  city_counts AS (
    SELECT
      rep_city,
      rep_region,
      avg(rep_lat)                                             AS avg_lat,
      avg(rep_lng)                                             AS avg_lng,
      count(*)                                                 AS reps_count,
      count(*) FILTER (WHERE COALESCE(is_hidden, false))      AS hidden_count
    FROM reps
    GROUP BY rep_city, rep_region
  ),
  top_reason AS (
    SELECT DISTINCT ON (rep_city) rep_city, reason
    FROM (
      SELECT rep_city, reason, count(*) AS cnt
      FROM reps
      GROUP BY rep_city, reason
    ) x
    ORDER BY rep_city, cnt DESC
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'city_code',  cc.rep_city,
        'region',     cc.rep_region,
        'lat',        cc.avg_lat,
        'lng',        cc.avg_lng,
        'reports',    cc.reps_count,
        'hidden',     cc.hidden_count,
        'top_reason', tr.reason
      ) ORDER BY cc.reps_count DESC
    ),
    '[]'::jsonb
  )
  FROM city_counts cc
  LEFT JOIN top_reason tr ON tr.rep_city = cc.rep_city;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not read moderation geo-density / map marker data.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_map_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_map_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_map_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;
