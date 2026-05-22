-- =============================================================================
-- Migration 051: Harden public.get_sessions_by_country_range
--
-- Phase: Production Hardening — MEDIUM-risk analytics read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) LANGUAGE sql version of
--   get_sessions_by_country_range with a production-safe, admin-gated
--   plpgsql RPC.
--
--   This function counts distinct sessions per country from event_logs via
--   the _lethe_event_filtered helper. It is the primary data source for the
--   "Top Earning Countries" monetization panel in Lethe Insights, which
--   derives ad revenue estimates from session counts. Session geo-distribution
--   is admin-only analytics intelligence.
--
--   Note on _lethe_event_filtered: migration 046 revoked anon/authenticated
--   execute on that helper. This function is already SECURITY DEFINER (runs
--   as postgres owner), so it can call the helper regardless of those revokes.
--   The admin gate here is what closes the user-facing exposure.
--
-- Security changes applied:
--   - Language changed sql → plpgsql (required for the admin gate)
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows; frontend
--     useTopEarningCountries.ts handles empty result at line 111 by setting
--     rawData to [] → data computes to [] via useMemo
--   - REVOKE ALL FROM PUBLIC and REVOKE EXECUTE FROM anon
--   - GRANT EXECUTE TO authenticated only
--
-- Frontend contract preserved (useTopEarningCountries.ts):
--   - Same name: get_sessions_by_country_range
--   - Same parameters (no defaults on the first two; they are required):
--       p_start_ts    timestamptz
--       p_end_ts      timestamptz
--       p_region      text DEFAULT NULL
--       p_country_code text DEFAULT NULL
--       p_city_code   text DEFAULT NULL
--       p_mode        text DEFAULT NULL
--   - Same return shape (multi-row table):
--       country_code  text
--       sessions      bigint
--     ordered by sessions DESC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_sessions_by_country_range(
  p_start_ts     TIMESTAMPTZ,
  p_end_ts       TIMESTAMPTZ,
  p_region       TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code    TEXT DEFAULT NULL,
  p_mode         TEXT DEFAULT NULL
)
RETURNS TABLE(
  country_code TEXT,
  sessions     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — the frontend treats an empty
  -- result as an empty revenue table (useTopEarningCountries.ts line 111).
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- ORDER BY 2 DESC avoids any plpgsql ambiguity between the "sessions" output
  -- variable and the "sessions" alias in the SELECT (positional is unambiguous).
  RETURN QUERY
  SELECT e.country_code, count(DISTINCT e.session_hash)::BIGINT AS sess_count
  FROM public._lethe_event_filtered(
    p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode
  ) e
  WHERE e.event_name = 'session_start'
    AND e.country_code IS NOT NULL
  GROUP BY e.country_code
  ORDER BY 2 DESC;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not read session geo-distribution analytics.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_sessions_by_country_range(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_sessions_by_country_range(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_sessions_by_country_range(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) TO authenticated;
