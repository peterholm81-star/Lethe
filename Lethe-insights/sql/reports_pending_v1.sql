-- =============================================================================
-- RPC: get_reports_pending_v1
-- Returns pending/unhandled reports with pagination and geo filtering.
-- =============================================================================
--
-- DEFINITION:
-- A report is "pending" if it has NO moderation_actions with action_type IN:
-- ('MARK_HANDLED', 'HIDE_CONFESSION', 'DISMISS_REPORT', 'ESCALATE')
-- Note: UNHIDE_CONFESSION does NOT count as closing/actioning a report.
--
-- SCHEMA NOTES:
-- - confession_reports: id, created_at, reason, details, city_code, confession_id
-- - confessions: id, region (no country_code column in this schema)
-- - moderation_actions: report_id, action_type, created_at
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_pending_v1(int, text, text, text, int, int);

CREATE OR REPLACE FUNCTION public.get_reports_pending_v1(
  p_days int DEFAULT 30,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- Not used (no country_code in confessions)
  p_city text DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  report_id text,
  confession_id text,
  reason text,
  created_at timestamptz,
  region text,
  country_code text,  -- Always NULL in current schema
  city_code text,
  hours_open numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_start timestamptz;
BEGIN
  -- Auth check: require authenticated user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access denied: authentication required';
  END IF;

  -- Calculate window start
  v_window_start := now() - (p_days || ' days')::interval;

  RETURN QUERY
  WITH 
  -- Reports that have been actioned (closed)
  actioned_reports AS (
    SELECT DISTINCT ma.report_id
    FROM moderation_actions ma
    WHERE ma.report_id IS NOT NULL
      AND ma.action_type IN ('MARK_HANDLED', 'HIDE_CONFESSION', 'DISMISS_REPORT', 'ESCALATE')
  ),
  
  -- Base reports within time window, excluding actioned ones
  pending AS (
    SELECT 
      cr.id AS report_id,
      cr.confession_id,
      COALESCE(NULLIF(TRIM(cr.reason), ''), 'Unknown') AS reason,
      cr.created_at,
      COALESCE(NULLIF(TRIM(c.region), ''), NULL) AS region,
      NULL::text AS country_code,  -- No country_code in schema
      COALESCE(NULLIF(TRIM(cr.city_code), ''), NULL) AS city_code,
      ROUND((EXTRACT(EPOCH FROM (now() - cr.created_at)) / 3600.0)::numeric, 1) AS hours_open
    FROM confession_reports cr
    LEFT JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_window_start
      -- Exclude reports that have been actioned
      AND NOT EXISTS (
        SELECT 1 FROM actioned_reports ar WHERE ar.report_id = cr.id
      )
      -- Geo filters (p_region='Unknown' matches NULL/empty/UNKNOWN)
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      AND (p_city IS NULL OR cr.city_code = p_city)
      -- p_country is ignored (no country_code column in confessions)
    ORDER BY cr.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  )
  
  SELECT
    p.report_id::text,
    p.confession_id::text,
    p.reason,
    p.created_at,
    p.region,
    p.country_code,
    p.city_code,
    p.hours_open
  FROM pending p;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_reports_pending_v1(int, text, text, text, int, int) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_pending_v1(30, NULL, NULL, NULL, 25, 0);
-- SELECT * FROM public.get_reports_pending_v1(7, 'Europe', NULL, NULL, 10, 0);
-- SELECT * FROM public.get_reports_pending_v1(7, NULL, NULL, 'TRD', 10, 0);
