-- =============================================================================
-- Migration 038: Harden public.get_moderation_actions_v1
--
-- Phase: Production Hardening Phase 3 — HIGH-risk moderation/admin read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of
--   get_moderation_actions_v1 with a production-safe, admin-gated read RPC.
--
--   This RPC exposes the full moderation audit log: action types, reasons,
--   confession and report IDs, geo codes, and source metadata from the
--   context JSONB field. It is the historical record of every moderation
--   action taken and must remain visible only to authenticated Insights admins.
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
--   - Same name: get_moderation_actions_v1
--   - Same parameters (all seven, with same defaults):
--       p_days integer DEFAULT 7
--       p_region text DEFAULT NULL
--       p_country text DEFAULT NULL
--       p_city text DEFAULT NULL
--       p_action_type text DEFAULT NULL
--       p_limit integer DEFAULT 25
--       p_offset integer DEFAULT 0
--   - Same return columns and types (all 10 columns in same order):
--       id uuid
--       created_at timestamptz
--       action_type text
--       confession_id uuid
--       report_id uuid
--       reason text
--       city_code text
--       region text
--       country_code text
--       source text
--   - Frontend (useModerationActions.ts) handles an empty array gracefully
--
-- Production safety:
--   - No raw confession text is returned
--   - Moderation audit history exposed only to authenticated admin users
--   - Anon access is blocked by grants before the function body executes
--   - Non-admin authenticated users receive zero rows (not an error)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_moderation_actions_v1(
  p_days        INTEGER DEFAULT 7,
  p_region      TEXT    DEFAULT NULL,
  p_country     TEXT    DEFAULT NULL,
  p_city        TEXT    DEFAULT NULL,
  p_action_type TEXT    DEFAULT NULL,
  p_limit       INTEGER DEFAULT 25,
  p_offset      INTEGER DEFAULT 0
)
RETURNS TABLE(
  id            UUID,
  created_at    TIMESTAMPTZ,
  action_type   TEXT,
  confession_id UUID,
  report_id     UUID,
  reason        TEXT,
  city_code     TEXT,
  region        TEXT,
  country_code  TEXT,
  source        TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — moderation audit history
  -- must not be visible outside the admin boundary.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.created_at,
    a.action_type,
    a.confession_id,
    a.report_id,
    a.reason,
    c.city_code,
    c.region,
    c.country_code,
    COALESCE(a.context->>'source', 'dev_seed')
  FROM public.moderation_actions a
  LEFT JOIN public.confessions c ON c.id = a.confession_id
  WHERE a.created_at >= now() - make_interval(days => p_days)
    AND (p_region      IS NULL OR c.region       = p_region)
    AND (p_country     IS NULL OR c.country_code = p_country)
    AND (p_city        IS NULL OR c.city_code    = p_city)
    AND (p_action_type IS NULL OR a.action_type  = p_action_type)
  ORDER BY a.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read the moderation audit log.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_moderation_actions_v1(INTEGER, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_moderation_actions_v1(INTEGER, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_moderation_actions_v1(INTEGER, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_moderation_actions_v1();
--    -- Expected: ERROR 42501 permission denied for function
--
-- 2. Authenticated non-admin receives zero rows:
--    SET LOCAL ROLE authenticated;
--    SELECT count(*) FROM public.get_moderation_actions_v1();
--    -- Expected: 0
--
-- 3. Authenticated admin receives audit log rows:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    SELECT count(*) FROM public.get_moderation_actions_v1(365);
--    -- Expected: > 0 if moderation actions exist in seed
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
