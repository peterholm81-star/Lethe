-- =============================================================================
-- RPC: get_moderation_actions_v1
-- Returns recent moderation actions for display in Reports Intelligence.
-- =============================================================================
--
-- NOTES:
-- - moderation_actions table has: id, created_at, actor_admin_id, report_id,
--   confession_id, action_type, reason, notes, context (jsonb)
-- - Geo info (region, city_code) is stored in context jsonb
-- - Admin-only via is_admin() check
--
-- V1.1: Added p_action_type filter for Audit Log UI
-- V1.2: Normalized action_type to canonical values (hidden/dismissed/escalated/handled)
--       Accepts both canonical and legacy values in filter
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_moderation_actions_v1(int, text, text, text, int, int);
DROP FUNCTION IF EXISTS public.get_moderation_actions_v1(int, text, text, text, text, int, int);

CREATE OR REPLACE FUNCTION public.get_moderation_actions_v1(
  p_days int DEFAULT 7,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- IGNORED (kept for future)
  p_city text DEFAULT NULL,
  p_action_type text DEFAULT NULL,  -- Filter: canonical (hidden/dismissed/escalated/handled) or legacy, NULL for all
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  created_at timestamptz,
  action_type text,  -- Returns canonical: hidden/dismissed/escalated/handled/other
  confession_id uuid,
  report_id uuid,
  reason text,
  city_code text,
  region text,
  country_code text,
  source text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_canonical_filter text;
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Calculate start time
  v_start := now() - (p_days || ' days')::interval;

  -- Normalize filter to canonical (accepts both canonical and legacy)
  v_canonical_filter := CASE lower(p_action_type)
    WHEN 'hidden' THEN 'hidden'
    WHEN 'hide_confession' THEN 'hidden'
    WHEN 'hide' THEN 'hidden'
    WHEN 'dismissed' THEN 'dismissed'
    WHEN 'dismiss_report' THEN 'dismissed'
    WHEN 'dismiss' THEN 'dismissed'
    WHEN 'escalated' THEN 'escalated'
    WHEN 'escalate' THEN 'escalated'
    WHEN 'handled' THEN 'handled'
    WHEN 'mark_handled' THEN 'handled'
    WHEN 'mark_as_handled' THEN 'handled'
    ELSE NULL  -- NULL means no filter (all actions)
  END;

  RETURN QUERY
  WITH actions_canonical AS (
    SELECT
      ma.id,
      ma.created_at,
      -- Map action_type to canonical
      CASE 
        WHEN ma.action_type IN ('hidden', 'HIDE_CONFESSION', 'HIDE') THEN 'hidden'
        WHEN ma.action_type IN ('dismissed', 'DISMISS_REPORT', 'DISMISS') THEN 'dismissed'
        WHEN ma.action_type IN ('escalated', 'ESCALATE') THEN 'escalated'
        WHEN ma.action_type IN ('handled', 'MARK_HANDLED', 'MARK_AS_HANDLED') THEN 'handled'
        ELSE 'other'
      END AS action_canonical,
      ma.confession_id,
      ma.report_id,
      ma.reason,
      (ma.context->>'cityCode')::text AS city_code,
      (ma.context->>'region')::text AS region,
      (ma.context->>'countryCode')::text AS country_code,
      COALESCE((ma.context->>'source')::text, 'unknown') AS source
    FROM public.moderation_actions ma
    WHERE ma.created_at >= v_start
      -- Filter by region if provided (from context jsonb)
      AND (p_region IS NULL OR (ma.context->>'region') = p_region)
      -- Filter by city if provided (from context jsonb)
      AND (p_city IS NULL OR (ma.context->>'cityCode') = p_city)
  )
  SELECT
    ac.id,
    ac.created_at,
    ac.action_canonical AS action_type,  -- Return canonical value
    ac.confession_id,
    ac.report_id,
    ac.reason,
    ac.city_code,
    ac.region,
    ac.country_code,
    ac.source
  FROM actions_canonical ac
  WHERE (v_canonical_filter IS NULL OR ac.action_canonical = v_canonical_filter)
  ORDER BY ac.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Grant execute to authenticated users (admin check is in function)
GRANT EXECUTE ON FUNCTION public.get_moderation_actions_v1(int, text, text, text, text, int, int) TO authenticated;

-- Notify PostgREST
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually)
-- =============================================================================
-- SELECT * FROM public.get_moderation_actions_v1(7, NULL, NULL, NULL, 25, 0);
-- SELECT * FROM public.get_moderation_actions_v1(30, 'Europe', NULL, NULL, 10, 0);
