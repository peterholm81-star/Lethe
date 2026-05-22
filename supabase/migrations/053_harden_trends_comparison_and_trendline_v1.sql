-- =============================================================================
-- Migration 053: Harden public.get_trends_comparison_v1 and
--                         public.get_trends_trendline_v1
--
-- Phase: Production Hardening — MEDIUM-risk Trends analytics read RPCs
--
-- These two functions are batched because they are called together in
-- useTrendsV1.ts (3 parallel RPC calls in fetchOne) and useTrendsSummaryV1.ts,
-- and both operate on the same event_logs data for the Trends dashboard section.
--
-- Both are aggregate-only (no raw confession text, no individual user data).
-- They expose platform-wide engagement trends which must be admin-only.
--
-- =============================================================================
-- RPC 1: get_trends_comparison_v1
-- =============================================================================
--
-- Returns current-vs-previous period comparison metrics per scope/metric pair,
-- used by the Trends "Comparison" panels.
--
-- plpgsql shadowing risk:
--   Output columns scope_key and metric_key share names with unqualified
--   column references inside the inner CTEs (scopes, agg, pivot). All internal
--   aliases are renamed: scope_key → sk, metric_key → mk, value → val,
--   cur → cur_val, prev → prev_val. The "scopes" CTE is renamed evt_scopes.
--   All positional mapping to RETURNS TABLE is preserved.
--
-- Frontend contract preserved (useTrendsV1.ts, useTrendsSummaryV1.ts):
--   - Same name: get_trends_comparison_v1
--   - Same parameters with same defaults:
--       p_scope    text DEFAULT 'global'
--       p_region   text DEFAULT NULL
--       p_days     integer DEFAULT 7
--       p_end_date date DEFAULT CURRENT_DATE
--   - Same return columns (multi-row):
--       scope_key      text
--       metric_key     text
--       current_value  numeric
--       previous_value numeric
--       delta_abs      numeric
--       delta_pct      numeric   (nullable — NULL when prev = 0)
--   - Empty result → normalizeRows(data ?? []) → [] — handled gracefully
--
-- =============================================================================
-- RPC 2: get_trends_trendline_v1
-- =============================================================================
--
-- Returns a daily time-series of session/read/post/ads_shown counts for the
-- selected window/region, used by the Trends trendline chart.
--
-- plpgsql shadowing risk:
--   Output columns metric_key and value share names with CTE column aliases.
--   Internal aliases renamed: days CTE → date_series, metric_key → mk,
--   value → val. The final SELECT maps d→day, mk→metric_key, val→value
--   positionally.
--
-- Frontend contract preserved (useTrendsV1.ts):
--   - Same name: get_trends_trendline_v1
--   - Same parameters with same defaults:
--       p_region   text DEFAULT NULL
--       p_days     integer DEFAULT 30
--       p_end_date date DEFAULT CURRENT_DATE
--   - Same return columns (multi-row):
--       day        date
--       metric_key text
--       value      numeric
--   - Empty result → normalizeTrendline(data ?? []) → [] — handled gracefully
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RPC 1: get_trends_comparison_v1
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trends_comparison_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 7,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  scope_key      TEXT,
  metric_key     TEXT,
  current_value  NUMERIC,
  previous_value NUMERIC,
  delta_abs      NUMERIC,
  delta_pct      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — normalizeRows(data ?? [])
  -- evaluates to [] in the frontend.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Internal aliases (sk, mk, val, cur_val, prev_val) avoid plpgsql output
  -- variable shadowing of scope_key, metric_key, value, current_value, etc.
  -- All SELECT columns map positionally to the RETURNS TABLE declaration.
  RETURN QUERY
  WITH bounds AS (
    SELECT
      p_end_date - (p_days - 1)       AS cur_start,
      p_end_date                       AS cur_end,
      p_end_date - (p_days * 2 - 1)   AS prev_start,
      p_end_date - p_days              AS prev_end
  ),
  evt_scopes AS (
    -- Renamed from "scopes" to avoid any CTE name collision with output vars
    SELECT
      CASE WHEN p_scope = 'country' THEN e.country_code
           ELSE COALESCE(p_region, 'global')
      END AS sk,
      e.*
    FROM public.event_logs e
    WHERE (p_region IS NULL OR e.region = p_region OR e.country_code = p_region)
      AND (p_scope <> 'country' OR e.country_code IS NOT NULL)
  ),
  agg AS (
    SELECT x.sk, x.mk, x.period, x.val
    FROM (
      SELECT
        m.sk,
        m.mk,
        CASE WHEN m.day_bucket BETWEEN b.cur_start AND b.cur_end
             THEN 'cur' ELSE 'prev'
        END AS period,
        CASE
          WHEN m.mk = 'sessions' THEN count(DISTINCT m.session_hash)::NUMERIC
          ELSE count(*)::NUMERIC
        END AS val
      FROM (
        SELECT sk, day_bucket, session_hash, 'sessions' AS mk FROM evt_scopes WHERE event_name = 'session_start'
        UNION ALL
        SELECT sk, day_bucket, session_hash, 'reads'    AS mk FROM evt_scopes WHERE event_name IN ('feed_view','page_fetch')
        UNION ALL
        SELECT sk, day_bucket, session_hash, 'posts'    AS mk FROM evt_scopes WHERE event_name = 'post_success'
        UNION ALL
        SELECT sk, day_bucket, session_hash, 'ads_shown' AS mk FROM evt_scopes WHERE event_name = 'ad_shown'
      ) m, bounds b
      WHERE m.day_bucket BETWEEN b.prev_start AND b.cur_end
      GROUP BY m.sk, m.mk,
               CASE WHEN m.day_bucket BETWEEN b.cur_start AND b.cur_end
                    THEN 'cur' ELSE 'prev' END
    ) x
  ),
  pivot AS (
    SELECT
      a.sk,
      a.mk,
      COALESCE(sum(a.val) FILTER (WHERE a.period = 'cur'),  0) AS cur_val,
      COALESCE(sum(a.val) FILTER (WHERE a.period = 'prev'), 0) AS prev_val
    FROM agg a
    GROUP BY a.sk, a.mk
  )
  SELECT
    pv.sk,                                                         -- → scope_key
    pv.mk,                                                         -- → metric_key
    pv.cur_val,                                                    -- → current_value
    pv.prev_val,                                                   -- → previous_value
    pv.cur_val - pv.prev_val,                                      -- → delta_abs
    CASE WHEN pv.prev_val > 0
         THEN (pv.cur_val - pv.prev_val) * 100.0 / pv.prev_val
         ELSE NULL
    END                                                            -- → delta_pct
  FROM pivot pv
  ORDER BY pv.mk, pv.cur_val DESC;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_comparison_v1(TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_comparison_v1(TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_comparison_v1(TEXT, TEXT, INTEGER, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC 2: get_trends_trendline_v1
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trends_trendline_v1(
  p_region   TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 30,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  day        DATE,
  metric_key TEXT,
  value      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — normalizeTrendline(data ?? [])
  -- evaluates to [] in the frontend.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Renamed: "days" CTE → "date_series" (avoids shadowing the p_days param
  -- column name pattern from migration 049 lesson). Internal metric_key → mk,
  -- value → val. All SELECT columns map positionally to RETURNS TABLE.
  RETURN QUERY
  WITH date_series AS (
    SELECT generate_series(
      p_end_date - (p_days - 1),
      p_end_date,
      interval '1 day'
    )::DATE AS d
  ),
  filtered AS (
    SELECT el.*
    FROM public.event_logs el
    WHERE (p_region IS NULL OR el.region = p_region OR el.country_code = p_region)
  ),
  metrics AS (
    SELECT ds.d, 'sessions' AS mk, count(DISTINCT e.session_hash)::NUMERIC AS val
    FROM date_series ds
    LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name = 'session_start'
    GROUP BY ds.d
    UNION ALL
    SELECT ds.d, 'reads', count(e.*)::NUMERIC
    FROM date_series ds
    LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name IN ('feed_view','page_fetch')
    GROUP BY ds.d
    UNION ALL
    SELECT ds.d, 'posts', count(e.*)::NUMERIC
    FROM date_series ds
    LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name = 'post_success'
    GROUP BY ds.d
    UNION ALL
    SELECT ds.d, 'ads_shown', count(e.*)::NUMERIC
    FROM date_series ds
    LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name = 'ad_shown'
    GROUP BY ds.d
  )
  SELECT m.d, m.mk, m.val   -- positional: d→day, mk→metric_key, val→value
  FROM metrics m
  ORDER BY m.d, m.mk;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_trendline_v1(TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_trendline_v1(TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_trendline_v1(TEXT, INTEGER, DATE) TO authenticated;
