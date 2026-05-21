-- =============================================================================
-- Migration 032: Harden public.set_reports_handled_for_confession
--
-- Phase: Production Hardening Phase 1 — Critical Admin Write RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of
--   set_reports_handled_for_confession with a production-safe, admin-gated
--   write RPC.
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
--   - Same name: set_reports_handled_for_confession
--   - Same parameters: (p_confession_id uuid, p_handled boolean DEFAULT true)
--   - Same return type: TABLE(updated_count integer)
--   - updated_count is the plpgsql output column; GET DIAGNOSTICS sets it and
--     RETURN NEXT emits it exactly as in the dev-seed version
--   - Frontend (useReportGroups.ts) checks error first; on success it reads
--     data[0].updated_count with a safe fallback to 0
--   - On non-admin RAISE EXCEPTION the frontend receives error != null and
--     returns { success: false } — handled correctly without frontend changes
--
-- Body improvement vs dev-seed:
--   - handled_by is set to auth.uid()::text (the real admin's user ID) instead
--     of the hardcoded 'local-dev' string used in the local dev shim.
--
-- Production safety:
--   - Bulk-updates only public.reports rows matching the given confession_id
--   - Touches only: handled, handled_at, handled_by, status columns
--   - Does not read or expose confession text, coordinates, or report content
--   - Does not affect public feed RPCs, insert_confession, or other tables
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_reports_handled_for_confession(
  p_confession_id UUID,
  p_handled       BOOLEAN DEFAULT true
)
RETURNS TABLE(updated_count INTEGER)
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
  WHERE confession_id = p_confession_id;

  -- updated_count is the output column declared in RETURNS TABLE above.
  -- GET DIAGNOSTICS assigns ROW_COUNT to it; RETURN NEXT emits the row.
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to bulk-close reports.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.set_reports_handled_for_confession(UUID, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_reports_handled_for_confession(UUID, BOOLEAN) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_reports_handled_for_confession(UUID, BOOLEAN) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.set_reports_handled_for_confession(
--      '00000000-0000-0000-0000-000000000001');
--    -- Expected: ERROR 42501 permission denied for function
--
-- 2. Authenticated non-admin blocked by admin gate (SQLSTATE 42501):
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"non-admin-uuid","role":"authenticated"}';
--    SELECT * FROM public.set_reports_handled_for_confession(
--      '00000000-0000-0000-0000-000000000001');
--    -- Expected: ERROR 42501 permission denied: admin access required
--
-- 3. Authenticated admin succeeds and returns updated_count:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    -- Set JWT claims to that uuid, then:
--    SELECT * FROM public.set_reports_handled_for_confession('<confession-id>');
--    -- Expected: one row with updated_count = N (number of reports updated)
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
