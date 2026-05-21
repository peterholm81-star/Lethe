-- ============================================================================
-- Migration: Harden get_change_over_time_range
-- ============================================================================
-- Purpose:
--   Convert one real, read-only Insights analytics RPC to the production-safe
--   admin model. This preserves the existing frontend RPC name, parameters, and
--   return columns while preventing anon access in production.
--
-- Scope:
--   - aggregate analytics only
--   - no public app/feed RPCs
--   - no moderation writes
--   - no monetization writes
--   - no frontend contract changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_change_over_time_range(
  p_start_ts TIMESTAMPTZ,
  p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL,
  p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (
  day_bucket DATE,
  sessions BIGINT,
  posts BIGINT,
  post_rate NUMERIC,
  pages_loaded BIGINT,
  pages_per_session NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Read-only Insights RPCs return an empty set for authenticated non-admins.
  -- Anon callers are denied by grants below before function execution.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  IF p_start_ts IS NULL OR p_end_ts IS NULL OR p_end_ts <= p_start_ts THEN
    RETURN;
  END IF;

  -- Production event_logs currently has city/mode dimensions, but not full
  -- region/country dimensions. Those filters are preserved in the signature for
  -- frontend compatibility and can be wired in a later geo-enrichment migration.
  RETURN QUERY
  WITH days AS (
    SELECT generate_series(
      date_trunc('day', p_start_ts),
      date_trunc('day', p_end_ts - interval '1 second'),
      interval '1 day'
    )::DATE AS day
  ), events AS (
    SELECT el.*
    FROM public.event_logs el
    WHERE el.created_at >= p_start_ts
      AND el.created_at < p_end_ts
      AND (p_city_code IS NULL OR el.city_code = p_city_code)
      AND (p_mode IS NULL OR el.mode = p_mode)
      AND (p_region IS NULL)
      AND (p_country_code IS NULL)
  ), aggregates AS (
    SELECT
      e.day_bucket,
      COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'session_start') AS sessions,
      COUNT(*) FILTER (WHERE e.event_name = 'post_success') AS posts,
      COUNT(*) FILTER (WHERE e.event_name = 'page_fetch') AS pages_loaded
    FROM events e
    GROUP BY e.day_bucket
  )
  SELECT
    d.day AS day_bucket,
    COALESCE(a.sessions, 0)::BIGINT AS sessions,
    COALESCE(a.posts, 0)::BIGINT AS posts,
    CASE
      WHEN COALESCE(a.sessions, 0) > 0 THEN a.posts::NUMERIC / a.sessions
      ELSE 0
    END AS post_rate,
    COALESCE(a.pages_loaded, 0)::BIGINT AS pages_loaded,
    CASE
      WHEN COALESCE(a.sessions, 0) > 0 THEN a.pages_loaded::NUMERIC / a.sessions
      ELSE 0
    END AS pages_per_session
  FROM days d
  LEFT JOIN aggregates a ON a.day_bucket = d.day
  ORDER BY d.day;
END;
$$;

COMMENT ON FUNCTION public.get_change_over_time_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) IS
  'Admin-gated production Insights RPC for read-only change-over-time analytics. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.get_change_over_time_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.get_change_over_time_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.get_change_over_time_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) TO authenticated;

-- ============================================================================
-- Verification notes (run manually in local/staging)
-- ============================================================================
--
-- 1. Anon REST caller:
--    Expected: permission denied because anon has no EXECUTE grant.
--
-- 2. Authenticated non-admin:
--    Expected: empty result set.
--
--      SELECT * FROM public.get_change_over_time_range(
--        now() - interval '7 days',
--        now(),
--        NULL,
--        NULL,
--        NULL,
--        NULL
--      );
--
-- 3. Authenticated admin:
--    Insert auth.uid() into public.admin_users using SQL owner/service-role
--    privileges, then call as that authenticated user.
--
--      SELECT * FROM public.get_change_over_time_range(
--        now() - interval '7 days',
--        now(),
--        NULL,
--        NULL,
--        NULL,
--        NULL
--      );
--      -- expected: one aggregate row per day
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
