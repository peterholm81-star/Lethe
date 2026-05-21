-- ============================================================================
-- Migration: Insights RPC admin pattern example
-- ============================================================================
-- Purpose:
--   Add one non-critical, production-safe Insights RPC that demonstrates the
--   future admin protection pattern without changing existing dashboard
--   contracts or public Lethe app behavior.
--
-- This intentionally does NOT gate current Insights dashboard shims, public feed
-- RPCs, posting RPCs, report submission RPCs, or monetization write paths.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_insights_event_log_summary_example()
RETURNS TABLE (
  total_events    BIGINT,
  latest_event_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Read-only Insights RPCs may return a safe null payload to authenticated
  -- non-admins. Write/action RPCs should raise insufficient_privilege instead.
  IF NOT public.is_insights_admin() THEN
    total_events := NULL;
    latest_event_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    COUNT(*)::BIGINT AS total_events,
    MAX(el.created_at) AS latest_event_at
  FROM public.event_logs el;
END;
$$;

COMMENT ON FUNCTION public.get_insights_event_log_summary_example() IS
  'Non-critical example Insights RPC showing SECURITY DEFINER, explicit search_path, admin gating, and least-privilege grants. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.get_insights_event_log_summary_example() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_insights_event_log_summary_example() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_insights_event_log_summary_example() TO authenticated;

-- ============================================================================
-- Verification notes (run manually in local/staging)
-- ============================================================================
--
-- 1. Anon REST caller:
--    Expected: permission denied because anon has no EXECUTE grant.
--
-- 2. Authenticated non-admin:
--    Expected: one row with NULL total_events and NULL latest_event_at.
--
--      SELECT * FROM public.get_insights_event_log_summary_example();
--
-- 3. Authenticated admin:
--    Insert auth.uid() into public.admin_users using SQL owner/service-role
--    privileges, then call as that authenticated user.
--
--      SELECT * FROM public.get_insights_event_log_summary_example();
--      -- expected: aggregate event count and latest event timestamp
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
