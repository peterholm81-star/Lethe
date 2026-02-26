-- ============================================================
-- RPC: set_confession_hidden
-- ============================================================
-- Hides or unhides a confession.
-- Admin only.
-- ============================================================

DROP FUNCTION IF EXISTS public.set_confession_hidden(uuid, bool);
DROP FUNCTION IF EXISTS public.set_confession_hidden(uuid, boolean);

CREATE OR REPLACE FUNCTION public.set_confession_hidden(
  p_confession_id uuid,
  p_hidden boolean DEFAULT true
)
RETURNS TABLE (
  id uuid,
  is_hidden boolean
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
  UPDATE confessions
  SET is_hidden = p_hidden
  WHERE confessions.id = p_confession_id
  RETURNING confessions.id, confessions.is_hidden;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.set_confession_hidden(uuid, boolean) TO anon;
GRANT EXECUTE ON FUNCTION public.set_confession_hidden(uuid, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Test
-- SELECT * FROM public.set_confession_hidden('some-uuid', true);
