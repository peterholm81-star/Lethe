-- ============================================================
-- RPC: set_reports_handled_for_confession
-- ============================================================
-- Marks ALL reports for a confession as handled or unhandled.
-- Admin only.
-- ============================================================

DROP FUNCTION IF EXISTS public.set_reports_handled_for_confession(uuid, bool);

CREATE OR REPLACE FUNCTION public.set_reports_handled_for_confession(
  p_confession_id uuid,
  p_handled bool DEFAULT true
)
RETURNS TABLE (
  updated_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  UPDATE confession_reports
  SET 
    handled = p_handled,
    handled_at = CASE WHEN p_handled THEN now() ELSE NULL END,
    handled_by = CASE WHEN p_handled THEN auth.uid() ELSE NULL END,
    action_taken = CASE WHEN p_handled THEN 'bulk_handled' ELSE NULL END
  WHERE confession_reports.confession_id = p_confession_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN QUERY SELECT v_count;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.set_reports_handled_for_confession(uuid, bool) TO anon;
GRANT EXECUTE ON FUNCTION public.set_reports_handled_for_confession(uuid, bool) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Test
-- SELECT * FROM public.set_reports_handled_for_confession('some-uuid', true);
