-- ============================================================
-- MODERATION ACTIONS - Robust Admin Logging v2
-- ============================================================
-- Logs all moderation actions taken in Lethe.
-- Admin-only, GDPR-safe (no PII stored).
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role).
-- NOTE: The RPC log_moderation_action is the key part. The table
--       CREATE IF NOT EXISTS won't modify an existing table.
--       If you need to add/change columns, do it manually first.
-- ============================================================

-- ============================================================
-- 1. DROP EXISTING (if upgrading from v1)
-- ============================================================
-- Uncomment if you need to replace the old table:
-- DROP TABLE IF EXISTS public.moderation_actions CASCADE;

-- ============================================================
-- 2. CREATE TABLE
-- ============================================================
-- Simplified schema: geo/meta goes into context jsonb
CREATE TABLE IF NOT EXISTS public.moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  actor_admin_id uuid NOT NULL DEFAULT auth.uid(),
  report_id uuid NULL REFERENCES public.confession_reports(id) ON DELETE SET NULL,
  confession_id uuid NULL REFERENCES public.confessions(id) ON DELETE SET NULL,
  action_type text NOT NULL,
  reason text NULL,
  notes text NULL,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Constraints
  CONSTRAINT moderation_actions_action_type_check CHECK (
    action_type IN (
      'HIDE_CONFESSION',
      'UNHIDE_CONFESSION',
      'MARK_HANDLED',
      'DISMISS_REPORT',
      'ESCALATE',
      'ADD_NOTE'
    )
  ),
  CONSTRAINT moderation_actions_target_check CHECK (
    (report_id IS NOT NULL) OR (confession_id IS NOT NULL)
  )
);

-- Comment for documentation
COMMENT ON TABLE public.moderation_actions IS 
  'Audit log of all moderation actions. Admin-only, GDPR-safe.';

-- ============================================================
-- 3. INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_moderation_actions_created_at
  ON public.moderation_actions (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_moderation_actions_action_type
  ON public.moderation_actions (action_type);

CREATE INDEX IF NOT EXISTS idx_moderation_actions_confession_id
  ON public.moderation_actions (confession_id)
  WHERE confession_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_moderation_actions_report_id
  ON public.moderation_actions (report_id)
  WHERE report_id IS NOT NULL;

-- NOTE: actor_admin_id may not exist in older table versions
-- CREATE INDEX IF NOT EXISTS idx_moderation_actions_actor
--   ON public.moderation_actions (actor_admin_id);

-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE public.moderation_actions ENABLE ROW LEVEL SECURITY;

-- Policy: Only admin can SELECT
DROP POLICY IF EXISTS moderation_actions_select ON public.moderation_actions;
CREATE POLICY moderation_actions_select ON public.moderation_actions
  FOR SELECT
  USING (is_admin(auth.uid()));

-- Policy: Only admin can INSERT
DROP POLICY IF EXISTS moderation_actions_insert ON public.moderation_actions;
CREATE POLICY moderation_actions_insert ON public.moderation_actions
  FOR INSERT
  WITH CHECK (is_admin(auth.uid()));

-- No UPDATE or DELETE policies (immutable audit log)

-- ============================================================
-- 5. RPC: log_moderation_action
-- ============================================================
-- Logs a moderation action. Admin-only, returns the new action ID.
-- Uses p_context jsonb to store geo info and any additional metadata.

-- Drop old signatures
DROP FUNCTION IF EXISTS public.log_moderation_action(uuid, uuid, text, text, text, text, text, int, text, jsonb);
DROP FUNCTION IF EXISTS public.log_moderation_action(text, uuid, uuid, text, text, jsonb);
DROP FUNCTION IF EXISTS public.log_moderation_action(text, uuid, uuid, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.log_moderation_action(
  p_action_type text,
  p_report_id uuid DEFAULT NULL,
  p_confession_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_context jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_confession_id uuid;
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Validate action_type
  IF p_action_type IS NULL OR p_action_type NOT IN (
    'HIDE_CONFESSION',
    'UNHIDE_CONFESSION',
    'MARK_HANDLED',
    'DISMISS_REPORT',
    'ESCALATE',
    'ADD_NOTE'
  ) THEN
    RAISE EXCEPTION 'Invalid action_type: %', COALESCE(p_action_type, 'NULL');
  END IF;

  -- Validate target (at least one must be provided)
  IF p_report_id IS NULL AND p_confession_id IS NULL THEN
    RAISE EXCEPTION 'At least one of report_id or confession_id must be provided';
  END IF;

  -- Resolve confession_id: use provided value, or lookup from report
  v_confession_id := p_confession_id;
  
  IF v_confession_id IS NULL AND p_report_id IS NOT NULL THEN
    -- Lookup confession_id from the report
    SELECT cr.confession_id INTO v_confession_id
    FROM public.confession_reports cr
    WHERE cr.id = p_report_id;
    
    -- If still null, that's OK - table allows it as long as report_id is set
  END IF;

  -- Insert the action
  INSERT INTO public.moderation_actions (
    report_id,
    confession_id,
    action_type,
    reason,
    notes,
    context
  ) VALUES (
    p_report_id,
    v_confession_id,
    p_action_type,
    p_reason,
    p_notes,
    COALESCE(p_context, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Grant execute to authenticated users (admin check is in function)
GRANT EXECUTE ON FUNCTION public.log_moderation_action(text, uuid, uuid, text, text, jsonb) TO authenticated;

-- ============================================================
-- 6. NOTIFY POSTGREST
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST QUERIES (run manually after deploying)
-- ============================================================
-- View recent actions:
-- SELECT * FROM public.moderation_actions ORDER BY created_at DESC LIMIT 20;

-- Test the RPC (replace UUIDs with real ones):
-- SELECT public.log_moderation_action(
--   'HIDE_CONFESSION',                       -- p_action_type
--   NULL,                                    -- p_report_id
--   'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'::uuid, -- p_confession_id
--   'Violated guidelines',                   -- p_reason
--   'User notified',                         -- p_notes
--   '{"source": "reports_inbox", "cityCode": "TRD", "region": "Europe"}'::jsonb -- p_context
-- );

-- Count actions by type:
-- SELECT action_type, count(*) FROM public.moderation_actions GROUP BY 1 ORDER BY 2 DESC;

-- Count actions by admin:
-- SELECT actor_admin_id, count(*) FROM public.moderation_actions GROUP BY 1 ORDER BY 2 DESC;
