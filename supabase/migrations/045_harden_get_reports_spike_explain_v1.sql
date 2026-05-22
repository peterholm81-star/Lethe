-- =============================================================================
-- Migration 045: Harden public.get_reports_spike_explain_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_spike_explain_v1
--   with a production-safe, admin-gated aggregate read RPC.
--
--   This migration also fixes a pre-existing shape mismatch: the old DB function
--   returned a multi-row per-reason breakdown (reason, current_count,
--   previous_count, delta_pct) but the frontend hook (useReportsSpikeExplain.ts)
--   has always read only rpcData[0] and expected a single aggregate spike-summary
--   row (spike_detected, window_hours, recent_reports, prev_reports,
--   delta_reports, pct_increase, top_reason, top_region, top_city). All spike
--   fields were silently null before this migration.
--
-- New aggregate logic (current window vs equal-length previous window):
--   - recent_reports: count in [now - p_days, now]
--   - prev_reports:   count in [now - 2*p_days, now - p_days]
--   - delta_reports:  recent - prev
--   - pct_increase:   (delta / prev) * 100, null when prev = 0
--   - spike_detected: recent > prev (any increase flags a spike)
--   - window_hours:   p_days * 24 (duration label for the UI)
--   - top_reason/region/city: most common value in current window, null if none
--
-- Security changes applied:
--   - DROP + CREATE (return type changes; CREATE OR REPLACE is not permitted)
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); frontend sets
--     spike state to null gracefully (useReportsSpikeExplain.ts line 125)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--
-- Frontend contract (useReportsSpikeExplain.ts):
--   - Same name: get_reports_spike_explain_v1
--   - Same parameters with same defaults:
--       p_days    integer DEFAULT 7
--       p_region  text    DEFAULT NULL
--       p_country text    DEFAULT NULL
--       p_city    text    DEFAULT NULL
--   - Corrected single aggregate row matching frontend expectations:
--       spike_detected boolean
--       window_hours   integer
--       recent_reports bigint
--       prev_reports   bigint
--       delta_reports  bigint
--       pct_increase   numeric  (nullable — null when prev = 0)
--       top_reason     text     (nullable)
--       top_region     text     (nullable)
--       top_city       text     (nullable)
-- =============================================================================

-- DROP required because return type changes from multi-row per-reason to
-- single aggregate row. No other RPCs or views depend on this function.
DROP FUNCTION IF EXISTS public.get_reports_spike_explain_v1(INTEGER, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_reports_spike_explain_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  spike_detected BOOLEAN,
  window_hours   INTEGER,
  recent_reports BIGINT,
  prev_reports   BIGINT,
  delta_reports  BIGINT,
  pct_increase   NUMERIC,
  top_reason     TEXT,
  top_region     TEXT,
  top_city       TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — spike anomaly intelligence
  -- must not be visible outside the admin boundary.
  -- The frontend sets spike state to null on empty result.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH window_reports AS (
    -- All reports in the current window with geo context for top-N lookups
    SELECT r.reason, cf.region, cf.city_code
    FROM public.reports r
    LEFT JOIN public.confessions cf ON cf.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR cf.region       = p_region)
      AND (p_country IS NULL OR cf.country_code = p_country)
      AND (p_city    IS NULL OR cf.city_code    = p_city)
  ),
  prev_count AS (
    -- Equal-length preceding window for spike comparison
    SELECT count(*) AS c
    FROM public.reports r
    LEFT JOIN public.confessions cf ON cf.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days * 2)
      AND r.created_at <  now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR cf.region       = p_region)
      AND (p_country IS NULL OR cf.country_code = p_country)
      AND (p_city    IS NULL OR cf.city_code    = p_city)
  ),
  totals AS (
    SELECT
      count(*)                     AS recent,
      (SELECT c FROM prev_count)   AS prev
    FROM window_reports
  )
  SELECT
    -- Spike detected when current window has more reports than previous window
    (totals.recent > COALESCE(totals.prev, 0))::BOOLEAN,
    -- Window size expressed in hours for the UI label
    p_days * 24,
    totals.recent,
    COALESCE(totals.prev, 0),
    totals.recent - COALESCE(totals.prev, 0),
    -- Percent increase; null when previous window was empty (no baseline)
    CASE WHEN totals.prev > 0
         THEN ROUND((totals.recent - totals.prev) * 100.0 / totals.prev, 2)
         ELSE NULL
    END,
    -- Most common reason in the current window
    (SELECT reason   FROM window_reports
     GROUP BY reason   ORDER BY count(*) DESC LIMIT 1),
    -- Most common region in the current window
    (SELECT region   FROM window_reports WHERE region   IS NOT NULL
     GROUP BY region   ORDER BY count(*) DESC LIMIT 1),
    -- Most common city in the current window
    (SELECT city_code FROM window_reports WHERE city_code IS NOT NULL
     GROUP BY city_code ORDER BY count(*) DESC LIMIT 1)
  FROM totals;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read moderation spike analysis.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_spike_explain_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_spike_explain_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_spike_explain_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;
