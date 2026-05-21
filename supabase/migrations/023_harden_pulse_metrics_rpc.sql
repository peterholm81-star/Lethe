-- ============================================================================
-- Migration: Harden get_pulse_metrics_range
-- ============================================================================
-- Purpose:
--   Convert one additional real, read-only Insights overview RPC to the
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

CREATE OR REPLACE FUNCTION public.get_pulse_metrics_range(
  p_start_ts TIMESTAMPTZ,
  p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL,
  p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (
  sessions BIGINT,
  readers BIGINT,
  posts BIGINT
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
  SELECT
    COUNT(DISTINCT el.session_hash) FILTER (WHERE el.event_name = 'session_start')::BIGINT AS sessions,
    COUNT(DISTINCT el.session_hash) FILTER (WHERE el.event_name IN ('feed_view', 'page_fetch'))::BIGINT AS readers,
    COUNT(*) FILTER (WHERE el.event_name = 'post_success')::BIGINT AS posts
  FROM public.event_logs el
  WHERE el.created_at >= p_start_ts
    AND el.created_at < p_end_ts
    AND (p_city_code IS NULL OR el.city_code = p_city_code)
    AND (p_mode IS NULL OR el.mode = p_mode)
    AND (p_region IS NULL)
    AND (p_country_code IS NULL);
END;
$$;

COMMENT ON FUNCTION public.get_pulse_metrics_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) IS
  'Admin-gated production Insights RPC for read-only pulse overview analytics. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.get_pulse_metrics_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.get_pulse_metrics_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.get_pulse_metrics_range(
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
--      SELECT * FROM public.get_pulse_metrics_range(
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
--      SELECT * FROM public.get_pulse_metrics_range(
--        now() - interval '7 days',
--        now(),
--        NULL,
--        NULL,
--        NULL,
--        NULL
--      );
--      -- expected: one aggregate pulse overview row
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
