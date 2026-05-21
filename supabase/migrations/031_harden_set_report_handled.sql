-- =============================================================================
-- Migration 031: Harden public.set_report_handled
--
-- Phase: Production Hardening Phase 1 — Critical Admin Write RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of set_report_handled
--   with a production-safe, admin-gated write RPC.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive RAISE EXCEPTION (insufficient_privilege,
--     SQLSTATE 42501) — write RPCs must fail loudly for non-admins
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--
-- Frontend contract preserved:
--   - Same name: set_report_handled
--   - Same parameters: (p_report_id uuid, p_handled boolean DEFAULT true)
--   - Same return type: void
--   - Frontend (useReportsInbox.ts) checks only the error field; a raised
--     exception propagates correctly as a Supabase RPC error
--
-- Body improvement vs dev-seed:
--   - handled_by is set to auth.uid()::text (the real admin's user ID) instead
--     of the hardcoded 'local-dev' string used in the local dev shim.
--     This is production-correct and fully transparent to the frontend.
--
-- Production safety:
--   - Writes only to public.reports for the given report id
--   - Touches only: handled, handled_at, handled_by, status columns
--   - Does not read or expose confession text or coordinates
--   - Does not affect public feed RPCs, insert_confession, or other tables
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_report_handled(
  p_report_id UUID,
  p_handled   BOOLEAN DEFAULT true
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

  UPDATE public.reports
  SET
    handled    = p_handled,
    handled_at = CASE WHEN p_handled THEN now()            ELSE NULL END,
    handled_by = CASE WHEN p_handled THEN auth.uid()::text ELSE NULL END,
    status     = CASE WHEN p_handled THEN 'reviewed'       ELSE 'open' END
  WHERE id = p_report_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to close or reopen reports.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.set_report_handled(UUID, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_report_handled(UUID, BOOLEAN) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_report_handled(UUID, BOOLEAN) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT public.set_report_handled('00000000-0000-0000-0000-000000000001', true);
--    -- Expected: ERROR 42501 permission denied for function set_report_handled
--
-- 2. Authenticated non-admin blocked by admin gate (SQLSTATE 42501):
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"non-admin-uuid","role":"authenticated"}';
--    SELECT public.set_report_handled('00000000-0000-0000-0000-000000000001', true);
--    -- Expected: ERROR 42501 permission denied: admin access required
--
-- 3. Authenticated admin succeeds:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    -- Set JWT claims to that uuid, then:
--    SELECT public.set_report_handled('<real-report-id>', true);
--    -- Expected: success, report.status = 'reviewed', handled_by = '<admin-uuid>'
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
