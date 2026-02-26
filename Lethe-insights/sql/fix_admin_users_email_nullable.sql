-- ============================================================
-- FIX: Allow NULL email in admin_users for anonymous auth
-- ============================================================
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Make user_email nullable (for anonymous users who have no email)
ALTER TABLE public.admin_users
ALTER COLUMN user_email DROP NOT NULL;

-- 2. Insert the anonymous admin user
INSERT INTO public.admin_users (user_id, user_email)
VALUES ('11f8340e-94f9-46f4-876d-ecf6e680f84f', NULL)
ON CONFLICT (user_id) DO NOTHING;

-- 3. Verify the insert
SELECT * FROM public.admin_users;
