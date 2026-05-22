-- =============================================================================
-- Migration 037: Harden public.get_reports_escalated_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation/admin read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of
--   get_reports_escalated_v1 with a production-safe, admin-gated read RPC.
--
--   This RPC exposes the escalated moderation queue: reports that are either
--   aged open (>12 hours) or explicitly escalated via moderation_actions.
--   It joins on moderation_actions (LATERAL) to surface the latest action
--   type and timestamp. While it returns no raw confession text, it reveals
--   operational moderation workflow state that must remain admin-only.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive an empty result set (RETURN)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--   - Language changed from sql to plpgsql to support the admin gate;
--     all JOIN/LATERAL logic, return columns, and ordering are preserved
--
-- Frontend contract preserved:
--   - Same name: get_reports_escalated_v1
--   - Same parameters (all six, with same defaults):
--       p_days integer DEFAULT 7
--       p_region text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city text DEFAULT NULL
--       p_limit integer DEFAULT 20
--       p_offset integer DEFAULT 0
--   - Same return columns and types (all 10 columns in same order):
--       report_id uuid
--       confession_id uuid
--       reason text
--       region text
--       country_code text
--       city_code text
--       created_at timestamptz
--       hours_open numeric
--       latest_action text
--       latest_action_at timestamptz
--   - Frontend (useReportsEscalated.ts) handles an empty array gracefully
--
-- Production safety:
--   - No raw confession text is returned
--   - Escalation and moderation workflow state exposed only to authenticated admins
--   - Anon access is blocked by grants before the function body executes
--   - Non-admin authenticated users receive zero rows (not an error)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_escalated_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL,
  p_limit   INTEGER DEFAULT 20,
  p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE(
  report_id        UUID,
  confession_id    UUID,
  reason           TEXT,
  region           TEXT,
  country_code     TEXT,
  city_code        TEXT,
  created_at       TIMESTAMPTZ,
  hours_open       NUMERIC,
  latest_action    TEXT,
  latest_action_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — escalation queue data
  -- must not be visible outside the admin boundary.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.confession_id,
    r.reason,
    c.region,
    c.country_code,
    c.city_code,
    r.created_at,
    EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600,
    COALESCE(a.action_type, 'ESCALATE'),
    COALESCE(a.created_at, r.created_at)
  FROM public.reports r
  LEFT JOIN public.confessions c ON c.id = r.confession_id
  LEFT JOIN LATERAL (
    SELECT ma.action_type, ma.created_at
    FROM public.moderation_actions ma
    WHERE ma.report_id = r.id
    ORDER BY ma.created_at DESC
    LIMIT 1
  ) a ON true
  WHERE (
      (r.status = 'open' AND r.created_at < now() - INTERVAL '12 hours')
      OR COALESCE(a.action_type, '') = 'ESCALATE'
    )
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
-- Anon users must not be able to read the escalated moderation queue.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_reports_escalated_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_escalated_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_escalated_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_reports_escalated_v1();
--    -- Expected: ERROR 42501 permission denied for function
--
-- 2. Authenticated non-admin receives zero rows:
--    SET LOCAL ROLE authenticated;
--    SELECT count(*) FROM public.get_reports_escalated_v1();
--    -- Expected: 0
--
-- 3. Authenticated admin receives escalated queue rows:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    SELECT count(*) FROM public.get_reports_escalated_v1(365);
--    -- Expected: > 0 if aged-open or ESCALATE-flagged reports exist
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
