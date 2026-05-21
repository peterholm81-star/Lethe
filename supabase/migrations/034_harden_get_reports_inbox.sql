-- =============================================================================
-- Migration 034: Harden public.get_reports_inbox
--
-- Phase: Production Hardening Phase 2 — HIGH-risk read RPCs (raw content)
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of get_reports_inbox
--   with a production-safe, admin-gated read RPC.
--
--   This RPC returns raw confession text (confession_text) and report details
--   (details). That content is acceptable only for authenticated Insights
--   admins who need it to perform moderation. Anon and authenticated
--   non-admins must receive zero rows, not an error.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive an empty result set (RETURN)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--   - Language changed from sql to plpgsql to support the admin gate;
--     query body, return type, and column order are preserved exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_inbox
--   - Same parameters: (p_limit integer DEFAULT 50,
--                        p_only_unhandled boolean DEFAULT true)
--   - Same return columns and types (all 12 columns in same order):
--       report_id uuid
--       report_created_at timestamptz
--       reason text
--       details text
--       report_city_code text
--       confession_id uuid
--       confession_region text
--       confession_text text
--       confession_is_hidden boolean
--       handled boolean
--       handled_at timestamptz
--       handled_by text
--   - Frontend (useReportsInbox.ts) handles an empty array gracefully:
--       setRows((data as ReportRow[]) ?? []) → renders empty inbox
--
-- Production safety:
--   - Raw confession text and report details are exposed only to admins
--   - Anon access is blocked by grants before the function body executes
--   - Non-admin authenticated users receive zero rows (not an error)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_inbox(
  p_limit          INTEGER DEFAULT 50,
  p_only_unhandled BOOLEAN DEFAULT true
)
RETURNS TABLE(
  report_id            UUID,
  report_created_at    TIMESTAMPTZ,
  reason               TEXT,
  details              TEXT,
  report_city_code     TEXT,
  confession_id        UUID,
  confession_region    TEXT,
  confession_text      TEXT,
  confession_is_hidden BOOLEAN,
  handled              BOOLEAN,
  handled_at           TIMESTAMPTZ,
  handled_by           TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — raw moderation data must
  -- not be visible outside the admin boundary.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.created_at,
    r.reason,
    r.details,
    c.city_code,
    c.id,
    c.region,
    c.text,
    COALESCE(c.is_hidden, false),
    COALESCE(r.handled, r.status <> 'open'),
    r.handled_at,
    r.handled_by
  FROM public.reports r
  LEFT JOIN public.confessions c ON c.id = r.confession_id
  WHERE (NOT p_only_unhandled OR r.status = 'open')
  ORDER BY r.created_at DESC
  LIMIT p_limit;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read the moderation inbox.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_reports_inbox(INTEGER, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_inbox(INTEGER, BOOLEAN) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_inbox(INTEGER, BOOLEAN) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_reports_inbox();
--    -- Expected: ERROR 42501 permission denied for function get_reports_inbox
--
-- 2. Authenticated non-admin receives zero rows:
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"non-admin-uuid","role":"authenticated"}';
--    SELECT count(*) FROM public.get_reports_inbox();
--    -- Expected: 0
--
-- 3. Authenticated admin receives moderation inbox rows:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    -- Set JWT claims to that uuid, then:
--    SELECT count(*) FROM public.get_reports_inbox();
--    -- Expected: > 0 (if reports exist)
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
