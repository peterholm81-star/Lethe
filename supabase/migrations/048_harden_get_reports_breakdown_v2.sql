-- =============================================================================
-- Migration 048: Harden public.get_reports_breakdown_v2
--
-- Phase: Production Hardening — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) LANGUAGE sql version of
--   get_reports_breakdown_v2 with a production-safe, admin-gated plpgsql RPC.
--
--   This function aggregates report reasons and top-reporting cities into two
--   JSONB arrays. It reads from public.reports joined to public.confessions,
--   which exposes operational moderation volume and geo distribution — admin
--   intelligence that must never be visible to anonymous or non-admin users.
--
-- Security changes applied:
--   - Language changed sql → plpgsql (required for the admin gate)
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows; frontend ReportsPage.tsx
--     handles empty result at line 919-924 by setting topReasons/topLocations
--     to empty arrays
--   - REVOKE ALL FROM PUBLIC and REVOKE EXECUTE FROM anon
--   - GRANT EXECUTE TO authenticated only
--
-- Frontend contract preserved (ReportsPage.tsx):
--   - Same name: get_reports_breakdown_v2
--   - Same parameters with same defaults:
--       p_range   text DEFAULT '7d'
--       p_region  text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city    text DEFAULT NULL
--   - Same return shape (single-row table):
--       top_reasons   jsonb   (array of {key, count, pct} objects, top 8 reasons)
--       top_locations jsonb   (array of {key, count, pct} objects, top 8 cities)
--
-- Note: This function calls public._lethe_reports_range_days() internally.
-- Because it runs as SECURITY DEFINER (postgres owner), the call succeeds
-- regardless of grants on that helper.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_breakdown_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  top_reasons   JSONB,
  top_locations JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — the frontend treats an empty
  -- array result as empty breakdown charts (ReportsPage.tsx lines 919-924).
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH params AS (
    SELECT public._lethe_reports_range_days(p_range) AS days
  ),
  reps AS (
    SELECT rep.reason, c.city_code AS rep_city, c.region AS rep_region, c.country_code AS rep_country
    FROM public.reports rep
    LEFT JOIN public.confessions c ON c.id = rep.confession_id
    CROSS JOIN params p
    WHERE rep.created_at >= now() - make_interval(days => p.days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
  ),
  total AS (
    SELECT count(*)::NUMERIC AS n FROM reps
  ),
  reasons AS (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'key',   x.reason,
          'count', x.cnt,
          'pct',   CASE WHEN tot.n > 0 THEN ROUND(x.cnt * 100.0 / tot.n, 1) ELSE 0 END
        ) ORDER BY x.cnt DESC
      ),
      '[]'::jsonb
    ) AS reasons_data
    FROM (SELECT reason, count(*) AS cnt FROM reps GROUP BY reason LIMIT 8) x,
         total tot
  ),
  locations AS (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'key',   x.city_code,
          'count', x.cnt,
          'pct',   CASE WHEN tot.n > 0 THEN ROUND(x.cnt * 100.0 / tot.n, 1) ELSE 0 END
        ) ORDER BY x.cnt DESC
      ),
      '[]'::jsonb
    ) AS locations_data
    FROM (SELECT COALESCE(rep_city, 'unknown') AS city_code, count(*) AS cnt
          FROM reps
          GROUP BY COALESCE(rep_city, 'unknown')
          LIMIT 8) x,
         total tot
  )
  SELECT rsn.reasons_data, loc.locations_data
  FROM reasons rsn, locations loc;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not read moderation reason/geo distribution data.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_breakdown_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_breakdown_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_breakdown_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;
