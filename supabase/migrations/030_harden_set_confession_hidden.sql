-- =============================================================================
-- Migration 030: Harden public.set_confession_hidden
--
-- Phase: Production Hardening Phase 1 — Critical Admin Write RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of set_confession_hidden
--   with a production-safe, admin-gated write RPC.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive RAISE EXCEPTION (insufficient_privilege)
--     not a silent no-op — write RPCs must fail loudly for non-admins
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--
-- Frontend contract preserved:
--   - Same name: set_confession_hidden
--   - Same parameters: (p_confession_id uuid, p_hidden boolean DEFAULT true)
--   - Same return type: void
--   - Frontend (useReportsInbox.ts) checks only the error field; a raised
--     exception propagates correctly as a Supabase RPC error
--
-- Production safety:
--   - Writes only to public.confessions.is_hidden for the given confession id
--   - Does not expose raw data
--   - Does not affect public feed RPCs or insert_confession
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_confession_hidden(
  p_confession_id UUID,
  p_hidden        BOOLEAN DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive an explicit permission error — write
  -- RPCs must never silently no-op.
  IF NOT public.is_insights_admin() THEN
    RAISE EXCEPTION 'permission denied: admin access required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.confessions
  SET is_hidden = p_hidden
  WHERE id = p_confession_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to hide or unhide confessions.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.set_confession_hidden(UUID, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_confession_hidden(UUID, BOOLEAN) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_confession_hidden(UUID, BOOLEAN) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT public.set_confession_hidden('00000000-0000-0000-0000-000000000001', true);
--    -- Expected: ERROR 42501 permission denied for function set_confession_hidden
--
-- 2. Authenticated non-admin blocked by admin gate:
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"non-admin-uuid","role":"authenticated"}';
--    SELECT public.set_confession_hidden('00000000-0000-0000-0000-000000000001', true);
--    -- Expected: ERROR 42501 permission denied: admin access required
--
-- 3. Authenticated admin succeeds:
--    INSERT INTO public.admin_users (user_id) VALUES ('admin-test-uuid');
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"admin-test-uuid","role":"authenticated"}';
--    SELECT public.set_confession_hidden('<real-confession-id>', true);
--    -- Expected: success (no error), confession.is_hidden updated to true
--    DELETE FROM public.admin_users WHERE user_id = 'admin-test-uuid';
-- =============================================================================
