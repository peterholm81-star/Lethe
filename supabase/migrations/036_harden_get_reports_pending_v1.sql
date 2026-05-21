-- =============================================================================
-- Migration 036: Harden public.get_reports_pending_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation/admin read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of
--   get_reports_pending_v1 with a production-safe, admin-gated read RPC.
--
--   This RPC exposes the live open moderation queue: report IDs, confession
--   IDs, reasons, creation timestamps, and geo codes. While it does not
--   return raw confession text, it reveals operational moderation state that
--   must remain admin-only.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive an empty result set (RETURN)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--   - Language changed from sql to plpgsql to support the admin gate;
--     all query logic, return columns, and ordering are preserved exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_pending_v1
--   - Same parameters (all six, with same defaults):
--       p_days integer DEFAULT 7
--       p_region text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city text DEFAULT NULL
--       p_limit integer DEFAULT 25
--       p_offset integer DEFAULT 0
--   - Same return columns and types (all 8 columns in same order):
--       report_id uuid
--       confession_id uuid
--       reason text
--       created_at timestamptz
--       region text
--       country_code text
--       city_code text
--       hours_open numeric
--   - Frontend (useReportsPending.ts) handles an empty array gracefully
--
-- Production safety:
--   - No raw confession text is returned
--   - Moderation queue state is exposed only to authenticated admin users
--   - Anon access is blocked by grants before the function body executes
--   - Non-admin authenticated users receive zero rows (not an error)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_pending_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL,
  p_limit   INTEGER DEFAULT 25,
  p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE(
  report_id    UUID,
  confession_id UUID,
  reason       TEXT,
  created_at   TIMESTAMPTZ,
  region       TEXT,
  country_code TEXT,
  city_code    TEXT,
  hours_open   NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — the live moderation queue
  -- must not be visible outside the admin boundary.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.confession_id,
    r.reason,
    r.created_at,
    c.region,
    c.country_code,
    c.city_code,
    EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600
  FROM public.reports r
  LEFT JOIN public.confessions c ON c.id = r.confession_id
  WHERE r.status = 'open'
    AND r.created_at >= now() - make_interval(days => p_days)
    AND (p_region  IS NULL OR c.region       = p_region)
    AND (p_country IS NULL OR c.country_code = p_country)
    AND (p_city    IS NULL OR c.city_code    = p_city)
  ORDER BY r.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read the open moderation queue.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_reports_pending_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_pending_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_pending_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_reports_pending_v1();
--    -- Expected: ERROR 42501 permission denied for function get_reports_pending_v1
--
-- 2. Authenticated non-admin receives zero rows:
--    SET LOCAL ROLE authenticated;
--    SELECT count(*) FROM public.get_reports_pending_v1();
--    -- Expected: 0
--
-- 3. Authenticated admin receives pending queue rows:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    SELECT count(*) FROM public.get_reports_pending_v1(30);
--    -- Expected: > 0 if open reports exist within 30 days
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
