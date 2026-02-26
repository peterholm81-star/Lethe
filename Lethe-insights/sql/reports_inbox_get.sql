-- ============================================================
-- RPC: get_reports_inbox
-- ============================================================
-- Returns reports with confession data for admin moderation.
-- Matches schema: confessions.text, confessions.region
-- ============================================================

DROP FUNCTION IF EXISTS public.get_reports_inbox(text, text, int, int);
DROP FUNCTION IF EXISTS public.get_reports_inbox(int, bool);

CREATE OR REPLACE FUNCTION public.get_reports_inbox(
  p_limit int DEFAULT 50,
  p_only_unhandled bool DEFAULT true
)
RETURNS TABLE (
  report_id uuid,
  report_created_at timestamptz,
  reason text,
  details text,
  report_city_code text,
  confession_id uuid,
  confession_region text,
  confession_text text,
  confession_is_hidden boolean,
  handled boolean,
  handled_at timestamptz,
  handled_by uuid
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

  RETURN QUERY
  SELECT 
    r.id AS report_id,
    r.created_at AS report_created_at,
    r.reason,
    r.details,
    r.city_code AS report_city_code,
    r.confession_id,
    COALESCE(c.region, '')::text AS confession_region,
    COALESCE(c.text, '')::text AS confession_text,
    COALESCE(c.is_hidden, false) AS confession_is_hidden,
    COALESCE(r.handled, false) AS handled,
    r.handled_at,
    r.handled_by
  FROM confession_reports r
  LEFT JOIN confessions c ON c.id = r.confession_id
  WHERE 
    (NOT p_only_unhandled OR COALESCE(r.handled, false) = false)
  ORDER BY r.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.get_reports_inbox(int, bool) TO anon;
GRANT EXECUTE ON FUNCTION public.get_reports_inbox(int, bool) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Test
-- SELECT * FROM public.get_reports_inbox(50, true);
