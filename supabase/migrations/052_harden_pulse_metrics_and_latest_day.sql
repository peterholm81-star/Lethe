-- =============================================================================
-- Migration 052: Harden public.get_pulse_metrics and
--                         public.get_latest_metrics_day
--
-- Phase: Production Hardening — MEDIUM-risk analytics/bootstrap read RPCs
--
-- These two functions are batched because they are used together in the same
-- hook (useInsightsActiveDay.ts) for dashboard bootstrap: get_pulse_metrics
-- checks if today has data, and get_latest_metrics_day finds the most recent
-- active day as a fallback. Neither exposes raw confession content but both
-- expose live operational metrics that must be admin-only.
--
-- =============================================================================
-- RPC 1: get_pulse_metrics
-- =============================================================================
--
-- Purpose:
--   Thin wrapper around get_pulse_metrics_range (already admin-gated, migration
--   023) that accepts a single date instead of a start/end range. Used by
--   useInsightsActiveDay to check whether today has any session/reader/post
--   activity.
--
-- Security note: get_pulse_metrics delegates entirely to get_pulse_metrics_range,
-- which already checks is_insights_admin() against request.jwt.claims. Even
-- without an explicit gate here, a non-admin caller would get empty results
-- from the inner call. We still add the explicit gate and REVOKE for defence-
-- in-depth and consistency with the hardening pattern.
--
-- Frontend contract preserved (useInsightsActiveDay.ts):
--   - Same name: get_pulse_metrics
--   - Same parameters:
--       p_date         date
--       p_region       text DEFAULT NULL
--       p_country_code text DEFAULT NULL
--       p_city_code    text DEFAULT NULL
--       p_mode         text DEFAULT NULL
--   - Same return shape (single-row table):
--       sessions_today bigint
--       readers_today  bigint
--       posts_today    bigint
--   - Empty result (0 rows) → unwrapRpcRow returns null → hasData = false
--     → hook falls through to get_latest_metrics_day (line 67-81)
--
-- =============================================================================
-- RPC 2: get_latest_metrics_day
-- =============================================================================
--
-- Purpose:
--   Returns max(day_bucket) from event_logs for session_start events.
--   Used by useInsightsActiveDay as a fallback when today has no data —
--   finds the most recent day that has any recorded activity.
--
-- Frontend contract preserved (useInsightsActiveDay.ts):
--   - Same name: get_latest_metrics_day
--   - Same parameters:
--       p_city   text DEFAULT NULL
--       p_region text DEFAULT NULL
--   - Same return shape (single-row table):
--       day_bucket date   (NULL if no data; unwrapRpcRow handles as null)
--   - 0 rows (admin gate) → unwrapRpcRow returns null → latestDay undefined
--     → fallback to today (line 104)
--
-- Note on plpgsql for get_latest_metrics_day: the output column "day_bucket"
-- shares a name with the event_logs column. The SELECT uses "e.day_bucket"
-- (fully qualified with table alias), so no plpgsql ambiguity occurs.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RPC 1: get_pulse_metrics
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pulse_metrics(
  p_date         DATE,
  p_region       TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code    TEXT DEFAULT NULL,
  p_mode         TEXT DEFAULT NULL
)
RETURNS TABLE(
  sessions_today BIGINT,
  readers_today  BIGINT,
  posts_today    BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — unwrapRpcRow returns null,
  -- hasData evaluates to false, hook falls through to get_latest_metrics_day.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Positional aliases (sess_count, read_count, post_count) avoid any
  -- plpgsql resolution conflict with the output variables.
  RETURN QUERY
  SELECT gpm.sessions, gpm.readers, gpm.posts
  FROM public.get_pulse_metrics_range(
    p_date::TIMESTAMPTZ,
    (p_date + 1)::TIMESTAMPTZ,
    CASE WHEN p_region = 'WORLD' THEN NULL ELSE p_region END,
    p_country_code,
    p_city_code,
    p_mode
  ) gpm;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_pulse_metrics(DATE, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_pulse_metrics(DATE, TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_pulse_metrics(DATE, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC 2: get_latest_metrics_day
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_latest_metrics_day(
  p_city   TEXT DEFAULT NULL,
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE(
  day_bucket DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — unwrapRpcRow returns null,
  -- latestDay evaluates to undefined, hook falls back to today's date
  -- (useInsightsActiveDay.ts line 104).
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- e.day_bucket is fully qualified to avoid plpgsql shadowing of the
  -- "day_bucket" output variable.
  RETURN QUERY
  SELECT max(e.day_bucket)
  FROM public.event_logs e
  WHERE e.event_name = 'session_start'
    AND (p_region IS NULL OR p_region = 'WORLD' OR e.region    = p_region)
    AND (p_city   IS NULL OR p_city   = 'WORLD' OR e.city_code = p_city);
END;
$$;

REVOKE ALL     ON FUNCTION public.get_latest_metrics_day(TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_latest_metrics_day(TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_latest_metrics_day(TEXT, TEXT) TO authenticated;
