-- ============================================================
-- FIX: get_reports_inbox column reference
-- ============================================================
-- The original function used COALESCE(c.confession, c.text, ...) 
-- which fails if neither column exists.
-- This fix uses only 'text' column (adjust if your column is different).
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
  -- Using 'text' column for confession content (adjust if needed)
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
    COALESCE(c.text, '') AS confession_text,
    c.created_at AS confession_created_at,
    COALESCE(c.city_code, '') AS confession_city_code,
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

-- Grants
GRANT EXECUTE ON FUNCTION public.get_reports_inbox(text, text, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_reports_inbox(text, text, int, int) TO authenticated;

-- Reload schema
NOTIFY pgrst, 'reload schema';

-- Test query (optional - check what columns exist in confessions)
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'confessions';
