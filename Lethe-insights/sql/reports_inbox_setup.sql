-- ============================================================
-- REPORTS INBOX SETUP - Moderation v1 for Lethe Insights
-- ============================================================
-- Run this in Supabase SQL Editor (as service role)
-- 
-- MANUAL STEP AFTER RUNNING:
-- Insert your user_id into admin_users:
--   INSERT INTO admin_users (user_id) VALUES ('YOUR-USER-ID-HERE');
-- ============================================================

-- ============================================================
-- 1. ADMIN USERS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id uuid PRIMARY KEY,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- 2. IS_ADMIN HELPER FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_admin(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = p_uid
  );
$$;

-- ============================================================
-- 3. CONFESSION REPORTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.confession_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  confession_id uuid NOT NULL,
  reason text NOT NULL,
  details text NULL,
  city_code text NULL,
  created_at timestamptz DEFAULT now(),
  handled boolean DEFAULT false,
  handled_at timestamptz NULL,
  handled_by uuid NULL,
  action_taken text NULL
);

-- Create index for common queries
CREATE INDEX IF NOT EXISTS idx_confession_reports_handled 
  ON public.confession_reports (handled, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_confession_reports_confession_id 
  ON public.confession_reports (confession_id);

-- ============================================================
-- 4. ADD is_hidden TO confessions (if not exists)
-- ============================================================
-- Note: This assumes table is named 'confessions'. Adjust if different.
DO $$
BEGIN
  -- Try confessions_live first
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'confessions_live') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'confessions_live' AND column_name = 'is_hidden'
    ) THEN
      ALTER TABLE public.confessions_live ADD COLUMN is_hidden boolean NOT NULL DEFAULT false;
    END IF;
  -- Fall back to confessions
  ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'confessions') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'confessions' AND column_name = 'is_hidden'
    ) THEN
      ALTER TABLE public.confessions ADD COLUMN is_hidden boolean NOT NULL DEFAULT false;
    END IF;
  END IF;
END $$;

-- ============================================================
-- 5. RLS POLICIES
-- ============================================================

-- Enable RLS on admin_users
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Admin users: only admins can see/modify (bootstrap: insert via SQL editor)
DROP POLICY IF EXISTS admin_users_select ON public.admin_users;
CREATE POLICY admin_users_select ON public.admin_users
  FOR SELECT USING (is_admin(auth.uid()));

DROP POLICY IF EXISTS admin_users_insert ON public.admin_users;
CREATE POLICY admin_users_insert ON public.admin_users
  FOR INSERT WITH CHECK (is_admin(auth.uid()));

DROP POLICY IF EXISTS admin_users_delete ON public.admin_users;
CREATE POLICY admin_users_delete ON public.admin_users
  FOR DELETE USING (is_admin(auth.uid()));

-- Enable RLS on confession_reports
ALTER TABLE public.confession_reports ENABLE ROW LEVEL SECURITY;

-- Anyone can INSERT reports (but we validate via app)
DROP POLICY IF EXISTS confession_reports_insert ON public.confession_reports;
CREATE POLICY confession_reports_insert ON public.confession_reports
  FOR INSERT WITH CHECK (true);

-- Only admin can SELECT reports
DROP POLICY IF EXISTS confession_reports_select ON public.confession_reports;
CREATE POLICY confession_reports_select ON public.confession_reports
  FOR SELECT USING (is_admin(auth.uid()));

-- Only admin can UPDATE reports
DROP POLICY IF EXISTS confession_reports_update ON public.confession_reports;
CREATE POLICY confession_reports_update ON public.confession_reports
  FOR UPDATE USING (is_admin(auth.uid()));

-- Only admin can DELETE reports
DROP POLICY IF EXISTS confession_reports_delete ON public.confession_reports;
CREATE POLICY confession_reports_delete ON public.confession_reports
  FOR DELETE USING (is_admin(auth.uid()));

-- ============================================================
-- 6. RPC: GET REPORTS INBOX
-- ============================================================
DROP FUNCTION IF EXISTS public.get_reports_inbox(text, text, int, int);

CREATE OR REPLACE FUNCTION public.get_reports_inbox(
  p_status text DEFAULT 'open',
  p_city text DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  report_id uuid,
  confession_id uuid,
  reason text,
  details text,
  report_city_code text,
  report_created_at timestamptz,
  handled boolean,
  handled_at timestamptz,
  handled_by uuid,
  action_taken text,
  confession_text text,
  confession_created_at timestamptz,
  confession_city_code text,
  confession_is_hidden boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Query reports with confession data
  -- Note: Adjust 'confessions' to your actual table name if different
  RETURN QUERY
  SELECT 
    r.id AS report_id,
    r.confession_id,
    r.reason,
    r.details,
    r.city_code AS report_city_code,
    r.created_at AS report_created_at,
    r.handled,
    r.handled_at,
    r.handled_by,
    r.action_taken,
    COALESCE(c.confession, c.text, '') AS confession_text,
    c.created_at AS confession_created_at,
    COALESCE(c.city_code, c.city, '') AS confession_city_code,
    COALESCE(c.is_hidden, false) AS confession_is_hidden
  FROM confession_reports r
  LEFT JOIN confessions c ON c.id = r.confession_id
  WHERE 
    (p_status = 'all' OR 
     (p_status = 'open' AND r.handled = false) OR 
     (p_status = 'handled' AND r.handled = true))
    AND (p_city IS NULL OR r.city_code = p_city)
  ORDER BY 
    r.handled ASC,
    r.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- ============================================================
-- 7. RPC: MARK REPORT HANDLED
-- ============================================================
DROP FUNCTION IF EXISTS public.mark_report_handled(uuid, text);

CREATE OR REPLACE FUNCTION public.mark_report_handled(
  p_report_id uuid,
  p_action_taken text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  UPDATE confession_reports
  SET 
    handled = true,
    handled_at = now(),
    handled_by = auth.uid(),
    action_taken = COALESCE(p_action_taken, action_taken)
  WHERE id = p_report_id;

  RETURN FOUND;
END;
$$;

-- ============================================================
-- 8. RPC: SET CONFESSION HIDDEN
-- ============================================================
DROP FUNCTION IF EXISTS public.set_confession_hidden(uuid, boolean);

CREATE OR REPLACE FUNCTION public.set_confession_hidden(
  p_confession_id uuid,
  p_hidden boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated boolean;
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Try confessions table (adjust if your table is named differently)
  UPDATE confessions
  SET is_hidden = p_hidden
  WHERE id = p_confession_id;

  v_updated := FOUND;

  -- If not found, try confessions_live
  IF NOT v_updated THEN
    UPDATE confessions_live
    SET is_hidden = p_hidden
    WHERE id = p_confession_id;
    v_updated := FOUND;
  END IF;

  RETURN v_updated;
END;
$$;

-- ============================================================
-- 9. GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_reports_inbox(text, text, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_reports_inbox(text, text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_report_handled(uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.mark_report_handled(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_confession_hidden(uuid, boolean) TO anon;
GRANT EXECUTE ON FUNCTION public.set_confession_hidden(uuid, boolean) TO authenticated;

-- ============================================================
-- 10. NOTIFY POSTGREST
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- MANUAL STEP: Add yourself as admin
-- ============================================================
-- Run this after the above, replacing with your actual user_id:
--
-- INSERT INTO admin_users (user_id) 
-- VALUES ('xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx');
--
-- To find your user_id, check auth.users in Supabase dashboard
-- or use: SELECT id FROM auth.users WHERE email = 'your@email.com';

-- ============================================================
-- TEST: Create sample reports (optional)
-- ============================================================
-- INSERT INTO confession_reports (confession_id, reason, city_code)
-- VALUES 
--   ('some-confession-uuid', 'spam', 'OSL'),
--   ('another-confession-uuid', 'harassment', 'TRD');
