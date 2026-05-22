-- =============================================================================
-- Migration 057: Harden get_insights_region_options,
--                        get_insights_country_options,
--                        get_insights_city_options
--
-- Phase: Production Hardening — LOW-risk filter helper RPCs (final batch)
--
-- These three functions populate the region / country / city filter dropdowns
-- in Lethe Insights. They expose only distinct label/code values from
-- event_logs — no counts, no confession content, no moderation data. Risk
-- is LOW but they still reveal Lethe's geo coverage and must be admin-only
-- for consistency with the rest of the hardened surface.
--
-- All three are single SELECT DISTINCT queries with no CTEs and fully
-- table-qualified column references (e.region, e.country_code, e.city_code).
-- No plpgsql output-variable shadowing risk in any of them.
--
-- Frontend contract preserved (useInsightsFilterOptions.ts):
--   - All three RPC names unchanged
--   - All signatures and defaults preserved
--   - Empty result (0 rows for non-admin) is handled gracefully at lines
--     57-58, 105-106, 159-160: ((data as T[]) || []).map(...) → [] → empty
--     filter dropdown, no error displayed to user
--
-- =============================================================================
-- get_insights_region_options
--   params: (none)
--   returns: TABLE(region text)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_insights_region_options()
RETURNS TABLE(region TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT e.region
  FROM public.event_logs e
  WHERE e.region IS NOT NULL
  ORDER BY e.region;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_insights_region_options() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_insights_region_options() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_insights_region_options() TO authenticated;

-- =============================================================================
-- get_insights_country_options
--   params: p_region text DEFAULT NULL
--   returns: TABLE(country_code text)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_insights_country_options(
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE(country_code TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT e.country_code
  FROM public.event_logs e
  WHERE e.country_code IS NOT NULL
    AND (p_region IS NULL OR e.region = p_region)
  ORDER BY e.country_code;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_insights_country_options(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_insights_country_options(TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_insights_country_options(TEXT) TO authenticated;

-- =============================================================================
-- get_insights_city_options
--   params: p_country_code text DEFAULT NULL, p_region text DEFAULT NULL
--   returns: TABLE(city_code text)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_insights_city_options(
  p_country_code TEXT DEFAULT NULL,
  p_region       TEXT DEFAULT NULL
)
RETURNS TABLE(city_code TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT e.city_code
  FROM public.event_logs e
  WHERE e.city_code IS NOT NULL
    AND (p_country_code IS NULL OR e.country_code = p_country_code)
    AND (p_region       IS NULL OR e.region       = p_region)
  ORDER BY e.city_code;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_insights_city_options(TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_insights_city_options(TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_insights_city_options(TEXT, TEXT) TO authenticated;
