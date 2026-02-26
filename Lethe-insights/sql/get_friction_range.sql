-- ============================================================
-- FRICTION RANGE RPC: get_friction_range
-- ============================================================
-- Calculates friction metrics (post attempts vs success/reject) from event_logs.
--
-- DEFINITIONS:
--   attempts_total = COUNT(*) WHERE post_attempt
--   success_total  = COUNT(*) WHERE post_success
--   rejected_total = attempts_total - success_total
--
-- PARAMETERS:
--   p_start_ts: Start of window (inclusive, timestamptz ISO)
--   p_end_ts:   End of window (exclusive, timestamptz ISO)
--   p_region, p_country_code, p_city_code: Lens filters (nullable)
-- ============================================================

DROP FUNCTION IF EXISTS public.get_friction_range(timestamptz, timestamptz, text, text, text);

CREATE OR REPLACE FUNCTION public.get_friction_range(
  p_start_ts timestamptz,
  p_end_ts timestamptz,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL
)
RETURNS TABLE (
  attempts_total bigint,
  success_total bigint,
  rejected_total bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempts bigint;
  v_success bigint;
  v_rejected bigint;
BEGIN
  -- Post attempts: count of post_attempt events
  SELECT COUNT(*)::bigint INTO v_attempts
  FROM event_logs
  WHERE event_name = 'post_attempt'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code);

  -- Post success: count of post_success events
  SELECT COUNT(*)::bigint INTO v_success
  FROM event_logs
  WHERE event_name = 'post_success'
    AND created_at >= p_start_ts
    AND created_at < p_end_ts
    AND (p_country_code IS NULL OR country_code = p_country_code)
    AND (p_region IS NULL OR region = p_region)
    AND (p_city_code IS NULL OR city_code = p_city_code);

  -- Rejected = attempts - success
  v_rejected := GREATEST(v_attempts - v_success, 0);

  RETURN QUERY SELECT v_attempts, v_success, v_rejected;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_friction_range(timestamptz, timestamptz, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_friction_range(timestamptz, timestamptz, text, text, text) TO authenticated;

-- ============================================================
-- NOTIFY PostgREST to reload schema
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST
-- ============================================================
SELECT * FROM public.get_friction_range(
  NOW() - INTERVAL '7 days',
  NOW(),
  NULL, NULL, NULL
);
