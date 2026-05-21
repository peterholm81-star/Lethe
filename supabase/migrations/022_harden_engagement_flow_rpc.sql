-- ============================================================================
-- Migration: Harden get_engagement_flow_range
-- ============================================================================
-- Purpose:
--   Convert one additional real, read-only Insights analytics RPC to the
--   production-safe admin model. This preserves the existing frontend RPC name,
--   parameters, and return columns while preventing anon access in production.
--
-- Scope:
--   - aggregate analytics only
--   - no public app/feed RPCs
--   - no moderation writes
--   - no monetization writes
--   - no frontend contract changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_engagement_flow_range(
  p_start_ts TIMESTAMPTZ,
  p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL,
  p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (
  sessions BIGINT,
  pages_loaded BIGINT,
  post_attempts BIGINT,
  post_success BIGINT,
  ads_shown BIGINT,
  ads_shown_sessions BIGINT,
  ad_continue_sessions BIGINT,
  ad_drop_sessions BIGINT,
  posts_per_session NUMERIC,
  pages_per_session NUMERIC,
  ad_continue_rate NUMERIC
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
  WITH events AS (
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
      COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'session_start') AS a_sessions,
      COUNT(*) FILTER (WHERE e.event_name = 'page_fetch') AS a_pages_loaded,
      COUNT(*) FILTER (WHERE e.event_name = 'post_attempt') AS a_post_attempts,
      COUNT(*) FILTER (WHERE e.event_name = 'post_success') AS a_post_success,
      COUNT(*) FILTER (WHERE e.event_name = 'ad_shown') AS a_ads_shown,
      COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'ad_shown') AS a_ads_shown_sessions,
      COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'continue_after_ad') AS a_ad_continue_sessions,
      COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'drop_after_ad') AS a_ad_drop_sessions
    FROM events e
  )
  SELECT
    a.a_sessions::BIGINT AS sessions,
    a.a_pages_loaded::BIGINT AS pages_loaded,
    a.a_post_attempts::BIGINT AS post_attempts,
    a.a_post_success::BIGINT AS post_success,
    a.a_ads_shown::BIGINT AS ads_shown,
    a.a_ads_shown_sessions::BIGINT AS ads_shown_sessions,
    a.a_ad_continue_sessions::BIGINT AS ad_continue_sessions,
    a.a_ad_drop_sessions::BIGINT AS ad_drop_sessions,
    CASE
      WHEN a.a_sessions > 0 THEN a.a_post_success::NUMERIC / a.a_sessions
      ELSE 0
    END AS posts_per_session,
    CASE
      WHEN a.a_sessions > 0 THEN a.a_pages_loaded::NUMERIC / a.a_sessions
      ELSE 0
    END AS pages_per_session,
    CASE
      WHEN a.a_ads_shown_sessions > 0 THEN a.a_ad_continue_sessions::NUMERIC / a.a_ads_shown_sessions
      ELSE 0
    END AS ad_continue_rate
  FROM aggregates a;
END;
$$;

COMMENT ON FUNCTION public.get_engagement_flow_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) IS
  'Admin-gated production Insights RPC for read-only engagement flow analytics. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.get_engagement_flow_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.get_engagement_flow_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.get_engagement_flow_range(
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
--      SELECT * FROM public.get_engagement_flow_range(
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
--      SELECT * FROM public.get_engagement_flow_range(
--        now() - interval '7 days',
--        now(),
--        NULL,
--        NULL,
--        NULL,
--        NULL
--      );
--      -- expected: one aggregate engagement row
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
