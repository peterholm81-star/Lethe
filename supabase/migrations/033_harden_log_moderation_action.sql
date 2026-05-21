-- =============================================================================
-- Migration 033: Harden public.log_moderation_action
--
-- Phase: Production Hardening Phase 1 — Critical Admin Write RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of
--   log_moderation_action with a production-safe, admin-gated write RPC.
--
-- Critical body change vs dev-seed:
--   The dev-seed version hardcoded:
--     is_dev_seed = true
--     dev_seed_batch = 'large-global-v1'
--   This MUST NOT reach production. Every admin action logged in production
--   must be a real audit record (is_dev_seed = false, dev_seed_batch = NULL).
--   The production version omits both columns entirely, relying on the table
--   defaults (is_dev_seed BOOLEAN NOT NULL DEFAULT false, dev_seed_batch TEXT).
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive RAISE EXCEPTION (insufficient_privilege,
--     SQLSTATE 42501) — write RPCs must fail loudly for non-admins
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--   - No generic EXCEPTION handler — SQLSTATE 42501 propagates unchanged
--
-- Frontend contract preserved:
--   - Same name: log_moderation_action
--   - Same parameters (all six, with same defaults):
--       p_action_type text
--       p_report_id   uuid DEFAULT NULL
--       p_confession_id uuid DEFAULT NULL
--       p_reason      text DEFAULT NULL
--       p_notes       text DEFAULT NULL
--       p_context     jsonb DEFAULT '{}'
--   - Same return type: uuid (the id of the inserted moderation_actions row)
--   - Frontend (useModerationActions.ts) reads data as string → actionId
--   - logModerationAction is called best-effort (.catch) in useReportsInbox
--     and useReportGroups; a non-admin 42501 is caught and silently suppressed
--     without breaking the parent action
--
-- Production safety:
--   - Writes only to public.moderation_actions
--   - Does not expose any read data
--   - Does not touch confessions, reports, or feed RPCs
--   - Inserted rows are real production audit records, not dev seed data
-- =============================================================================

CREATE OR REPLACE FUNCTION public.log_moderation_action(
  p_action_type   TEXT,
  p_report_id     UUID    DEFAULT NULL,
  p_confession_id UUID    DEFAULT NULL,
  p_reason        TEXT    DEFAULT NULL,
  p_notes         TEXT    DEFAULT NULL,
  p_context       JSONB   DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive an explicit permission error — write
  -- RPCs must never silently no-op.
  IF NOT public.is_insights_admin() THEN
    RAISE EXCEPTION 'permission denied: admin access required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Production insert: is_dev_seed and dev_seed_batch are intentionally
  -- omitted so the table defaults apply (false and NULL respectively).
  -- The dev-seed hardcodings 'is_dev_seed = true' and
  -- 'dev_seed_batch = large-global-v1' must not appear in production rows.
  INSERT INTO public.moderation_actions
    (action_type, report_id, confession_id, reason, notes, context)
  VALUES
    (p_action_type, p_report_id, p_confession_id, p_reason, p_notes,
     COALESCE(p_context, '{}'::jsonb))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to write moderation audit log entries.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.log_moderation_action(TEXT, UUID, UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.log_moderation_action(TEXT, UUID, UUID, TEXT, TEXT, JSONB) FROM anon;
GRANT  EXECUTE ON FUNCTION public.log_moderation_action(TEXT, UUID, UUID, TEXT, TEXT, JSONB) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT public.log_moderation_action('HIDE_CONFESSION');
--    -- Expected: ERROR 42501 permission denied for function log_moderation_action
--
-- 2. Authenticated non-admin blocked by admin gate (SQLSTATE 42501):
--    SET LOCAL ROLE authenticated;
--    SELECT public.log_moderation_action('HIDE_CONFESSION');
--    -- Expected: ERROR 42501 permission denied: admin access required
--
-- 3. Authenticated admin inserts a production-safe row:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    -- Set JWT claims to that uuid, then:
--    SELECT public.log_moderation_action('HIDE_CONFESSION', NULL, NULL,
--      'test', 'verify 033', '{"source":"migration_test"}');
--    -- Expected: returns a uuid; inserted row has is_dev_seed = false,
--    --           dev_seed_batch = NULL
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
--    DELETE FROM public.moderation_actions WHERE notes = 'verify 033';
-- =============================================================================
