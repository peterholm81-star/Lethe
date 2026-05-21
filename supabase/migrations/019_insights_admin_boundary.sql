-- ============================================================================
-- Migration: Insights admin boundary foundation
-- ============================================================================
-- Purpose:
--   Establish the minimal production-safe admin boundary for Lethe Insights.
--
-- Security rules:
--   - Lethe remains public/anonymous.
--   - Lethe Insights is admin-only.
--   - The browser must never receive the Supabase service_role key.
--   - Admin-only RPCs should call public.is_insights_admin() before returning
--     analytics, reports, moderation, or monetization data.
--
-- This migration intentionally does NOT:
--   - wire frontend auth
--   - promote local dev shims
--   - add Insights dashboard RPCs
--   - change existing public app RPCs
--   - grant broad access to anon/authenticated roles
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    UUID PRIMARY KEY,
  role       TEXT NOT NULL DEFAULT 'admin',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.admin_users IS
  'Production allowlist for Lethe Insights administrators. Browser clients must never receive service_role.';

COMMENT ON COLUMN public.admin_users.user_id IS
  'Supabase Auth user id. This value is compared against auth.uid().';

COMMENT ON COLUMN public.admin_users.role IS
  'Initial admin role label. Later migrations may introduce stricter role checks.';

COMMENT ON COLUMN public.admin_users.created_at IS
  'Timestamp when the admin allowlist entry was created.';

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- No direct table access is granted to anon/authenticated users. Admin checks go
-- through the SECURITY DEFINER helper below, and bootstrap/admin maintenance
-- should be performed with service-role or SQL owner privileges.
REVOKE ALL ON TABLE public.admin_users FROM anon;
REVOKE ALL ON TABLE public.admin_users FROM authenticated;

CREATE OR REPLACE FUNCTION public.is_insights_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users au
    WHERE au.user_id = auth.uid()
  );
$$;

COMMENT ON FUNCTION public.is_insights_admin() IS
  'Returns true when the current authenticated Supabase user is allowlisted for Lethe Insights. Does not expose service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke first, then
-- grant only the role that can actually have a user identity.
REVOKE ALL ON FUNCTION public.is_insights_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_insights_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_insights_admin() TO authenticated;

-- ============================================================================
-- Verification notes (run manually in local/staging, not as migration logic)
-- ============================================================================
--
-- 1. No authenticated user:
--    The helper itself returns false when auth.uid() is null.
--
--      SELECT public.is_insights_admin();
--
-- 2. Anon REST user:
--    Anon should not be granted EXECUTE. Calling the RPC as anon should fail
--    with a permission error, which is stricter than returning false.
--
-- 3. Authenticated non-admin:
--    Sign in as a normal Supabase user that is not in public.admin_users.
--
--      SELECT public.is_insights_admin();
--      -- expected: false
--
-- 4. Authenticated admin:
--    Insert the authenticated user's auth.uid() using SQL owner/service-role
--    privileges, then call the helper as that user.
--
--      INSERT INTO public.admin_users (user_id, role)
--      VALUES ('00000000-0000-0000-0000-000000000000', 'admin');
--
--      SELECT public.is_insights_admin();
--      -- expected: true for that authenticated user
--
-- 5. Direct table access:
--    Anon and ordinary authenticated users should not be able to select from
--    public.admin_users directly.
-- ============================================================================
