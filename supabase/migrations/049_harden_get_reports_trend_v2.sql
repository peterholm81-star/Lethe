-- =============================================================================
-- Migration 049: Harden public.get_reports_trend_v2
--
-- Phase: Production Hardening — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) LANGUAGE sql version of
--   get_reports_trend_v2 with a production-safe, admin-gated plpgsql RPC.
--
--   This function produces a daily time-series JSONB array of report counts
--   for the selected window/filters. It reads from public.reports joined to
--   public.confessions and exposes moderation volume trends over time —
--   operational intelligence that must not be visible to anon or non-admins.
--
-- Security changes applied:
--   - Language changed sql → plpgsql (required for the admin gate)
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows; frontend ReportsPage.tsx
--     handles empty result at line 974-976 by calling setTrendData([])
--   - REVOKE ALL FROM PUBLIC and REVOKE EXECUTE FROM anon
--   - GRANT EXECUTE TO authenticated only
--
-- Frontend contract preserved (ReportsPage.tsx):
--   - Same name: get_reports_trend_v2
--   - Same parameters with same defaults:
--       p_range   text DEFAULT '7d'
--       p_region  text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city    text DEFAULT NULL
--   - Same return shape (single-row table):
--       trend jsonb  (array of {ts, label, count} objects, one per day)
--
-- Naming note: the original SQL CTE was named "days" and the params CTE
-- exposes a column also named "days". These are distinct (table vs. column
-- reference in SQL), but to avoid any potential plpgsql resolution ambiguity
-- the date-series CTE is renamed to "date_series" in this version.
-- All query logic and output are identical to the original.
--
-- Note: calls public._lethe_reports_range_days() — safe because SECURITY
-- DEFINER functions execute as the postgres owner, bypassing grant checks.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_trend_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  trend JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — the frontend treats an empty
  -- array result as an empty trend chart (ReportsPage.tsx lines 974-976).
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH params AS (
    SELECT public._lethe_reports_range_days(p_range) AS days
  ),
  date_series AS (
    -- Renamed from "days" to avoid shadowing the "days" column in params CTE
    SELECT generate_series(
      (current_date - ((SELECT days FROM params) - 1)),
      current_date,
      interval '1 day'
    )::DATE AS d
  ),
  counts AS (
    SELECT rep.created_at::DATE AS d, count(*) AS cnt
    FROM public.reports rep
    LEFT JOIN public.confessions c ON c.id = rep.confession_id
    CROSS JOIN params p
    WHERE rep.created_at >= now() - make_interval(days => p.days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
    GROUP BY 1
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'ts',    ds.d::TEXT,
        'label', to_char(ds.d, 'Mon DD'),
        'count', COALESCE(c.cnt, 0)
      ) ORDER BY ds.d
    ),
    '[]'::jsonb
  )
  FROM date_series ds
  LEFT JOIN counts c ON c.d = ds.d;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not read moderation volume trend data.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_trend_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_trend_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_trend_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;
