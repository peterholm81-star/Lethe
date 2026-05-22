-- =============================================================================
-- Migration 055: Harden public.get_year_wheel_v1 — both overloads
--
-- Phase: Production Hardening — MEDIUM-risk seasonality analytics read RPCs
--
-- Two overloads exist (same pattern as get_trends_movers_v1 / migration 054):
--
--   Overload A (5-param): core logic. Reads event_logs + confessions, builds
--   monthly seasonality rows with session/post/mood aggregates for a rolling
--   window (default 365 days).
--
--   Overload B (6-param): thin wrapper around Overload A that accepts a
--   p_city parameter (ignored). The frontend always calls this overload
--   because scopeToRpc() always emits p_city (scopeUtils.ts line 29-32).
--
-- Both overloads must be hardened.
--
-- plpgsql shadowing risk in Overload A:
--   Output columns month_start, sessions, posts, mood_pos, mood_neg all match
--   CTE alias names inside event_months and confession_months CTEs. Internal
--   CTE column aliases renamed:
--     event_months:      month_start → em_month, sessions → em_sessions,
--                        posts → em_posts
--     confession_months: month_start → cm_month, mood_pos → cm_mood_pos,
--                        mood_neg → cm_mood_neg, count(*) → cm_total
--   All WHERE clause references use explicit table aliases (e., c.).
--   All JOIN conditions and final SELECT use qualified aliases.
--   Positional mapping to RETURNS TABLE is preserved.
--
-- Frontend contract preserved (useYearWheelV1.ts):
--   - Same name: get_year_wheel_v1 (both overloads)
--   - Frontend calls 6-param overload via scopeToRpc() + p_days + p_end_date
--   - Same return shape (multi-row):
--       month_start       date
--       sessions          bigint
--       posts             bigint
--       posts_per_session numeric  (nullable)
--       mood_pos          bigint
--       mood_neg          bigint
--       mood_balance      numeric  (nullable)
--   - Empty result → normalize(res.data ?? []) → [] — handled gracefully
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Overload A: 5-parameter core logic
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_year_wheel_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_country  TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 365,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  month_start       DATE,
  sessions          BIGINT,
  posts             BIGINT,
  posts_per_session NUMERIC,
  mood_pos          BIGINT,
  mood_neg          BIGINT,
  mood_balance      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — normalize(res.data ?? [])
  -- evaluates to [] in the frontend.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Internal CTE aliases (em_month, em_sessions, em_posts, cm_month,
  -- cm_mood_pos, cm_mood_neg, cm_total) replace the original names that
  -- match the RETURNS TABLE output variables, preventing plpgsql from
  -- misresolving unqualified column references as output variables.
  -- All JOIN conditions use qualified aliases. Positional SELECT mapping
  -- to RETURNS TABLE columns is preserved.
  RETURN QUERY
  WITH months AS (
    SELECT generate_series(
      date_trunc('month', p_end_date::TIMESTAMP - make_interval(days => p_days)),
      date_trunc('month', p_end_date::TIMESTAMP),
      interval '1 month'
    )::DATE AS m
  ),
  event_months AS (
    SELECT
      date_trunc('month', e.created_at)::DATE                                    AS em_month,
      count(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'session_start') AS em_sessions,
      count(*) FILTER (WHERE e.event_name = 'post_success')                      AS em_posts
    FROM public.event_logs e
    WHERE e.day_bucket >= p_end_date - p_days
      AND (p_region  IS NULL OR e.region       = p_region)
      AND (p_country IS NULL OR e.country_code = p_country)
    GROUP BY 1
  ),
  confession_months AS (
    SELECT
      date_trunc('month', c.created_at)::DATE                                                        AS cm_month,
      count(*) FILTER (WHERE c.emotion_bucket IN ('hopeful','calm','grateful'))                      AS cm_mood_pos,
      count(*) FILTER (WHERE c.emotion_bucket IN ('lonely','anxious','sad','tired','restless'))      AS cm_mood_neg,
      count(*)                                                                                        AS cm_total
    FROM public.confessions c
    WHERE c.created_at::DATE >= p_end_date - p_days
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
    GROUP BY 1
  )
  SELECT
    m.m,                                                                          -- → month_start
    COALESCE(e.em_sessions, 0),                                                   -- → sessions
    COALESCE(e.em_posts, 0),                                                      -- → posts
    CASE WHEN COALESCE(e.em_sessions, 0) > 0
         THEN e.em_posts::NUMERIC / e.em_sessions
         ELSE NULL
    END,                                                                          -- → posts_per_session
    COALESCE(c.cm_mood_pos, 0),                                                   -- → mood_pos
    COALESCE(c.cm_mood_neg, 0),                                                   -- → mood_neg
    CASE WHEN COALESCE(c.cm_total, 0) > 0
         THEN (c.cm_mood_pos - c.cm_mood_neg)::NUMERIC / c.cm_total
         ELSE NULL
    END                                                                           -- → mood_balance
  FROM months m
  LEFT JOIN event_months    e ON e.em_month = m.m
  LEFT JOIN confession_months c ON c.cm_month = m.m
  ORDER BY m.m;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- Overload B: 6-parameter wrapper (p_city accepted but ignored — calls Overload A)
-- This is the overload the frontend always invokes via scopeToRpc().
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_year_wheel_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_country  TEXT    DEFAULT NULL,
  p_city     TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 365,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  month_start       DATE,
  sessions          BIGINT,
  posts             BIGINT,
  posts_per_session NUMERIC,
  mood_pos          BIGINT,
  mood_neg          BIGINT,
  mood_balance      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Defence-in-depth gate at the wrapper level.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- p_city accepted for frontend compatibility, not forwarded to core logic.
  RETURN QUERY
  SELECT gyw.month_start, gyw.sessions, gyw.posts, gyw.posts_per_session,
         gyw.mood_pos, gyw.mood_neg, gyw.mood_balance
  FROM public.get_year_wheel_v1(p_scope, p_region, p_country, p_days, p_end_date) gyw;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;
