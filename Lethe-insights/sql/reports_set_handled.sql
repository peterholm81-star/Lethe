-- ============================================================
-- RPC: set_report_handled
-- ============================================================
-- Marks a report as handled or unhandled (undo).
-- Admin only.
-- ============================================================

DROP FUNCTION IF EXISTS public.set_report_handled(uuid, bool);
DROP FUNCTION IF EXISTS public.mark_report_handled(uuid, text);

CREATE OR REPLACE FUNCTION public.set_report_handled(
  p_report_id uuid,
  p_handled bool DEFAULT true
)
RETURNS TABLE (
  id uuid,
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
  UPDATE confession_reports
  SET 
    handled = p_handled,
    handled_at = CASE WHEN p_handled THEN now() ELSE NULL END,
    handled_by = CASE WHEN p_handled THEN auth.uid() ELSE NULL END,
    action_taken = CASE WHEN p_handled THEN 'handled' ELSE NULL END
  WHERE confession_reports.id = p_report_id
  RETURNING 
    confession_reports.id,
    confession_reports.handled,
    confession_reports.handled_at,
    confession_reports.handled_by;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.set_report_handled(uuid, bool) TO anon;
GRANT EXECUTE ON FUNCTION public.set_report_handled(uuid, bool) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Test
-- SELECT * FROM public.set_report_handled('some-uuid', true);
