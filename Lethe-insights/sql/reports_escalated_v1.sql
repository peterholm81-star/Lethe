-- =============================================================================
-- RPC: get_reports_escalated_v1
-- Returns reports where the latest action is ESCALATE (escalated queue).
-- =============================================================================
--
-- DEFINITION:
-- A report is in the "Escalated Queue" if its latest moderation_action 
-- has action_type = 'ESCALATE'. Once a subsequent action (Hide/Dismiss/Handled)
-- is taken, it leaves this queue.
--
-- SCHEMA NOTES:
-- - Reports are in confession_reports table
-- - confession_reports.city_code exists
-- - confession_reports does NOT have region/country_code directly
-- - To filter by region: join via confession_reports -> confessions (c.region)
--
-- DEPLOY: Run in Supabase SQL Editor (as service role).
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_escalated_v1(int, text, text, text, int, int);

CREATE OR REPLACE FUNCTION public.get_reports_escalated_v1(
  p_days int DEFAULT 30,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- Not used (no country_code in confessions)
  p_city text DEFAULT NULL,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  report_id text,
  confession_id text,
  reason text,
  region text,
  country_code text,
  city_code text,
  created_at timestamptz,
  hours_open numeric,
  latest_action text,
  latest_action_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Auth check: require authenticated user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access denied: authentication required';
  END IF;

  RETURN QUERY
  WITH 
  -- Base reports within time window
  base_reports AS (
    SELECT 
      cr.id AS report_id,
      cr.confession_id,
      COALESCE(NULLIF(TRIM(cr.reason), ''), 'Unknown') AS reason,
      cr.city_code,
      cr.created_at
    FROM confession_reports cr
    WHERE cr.created_at >= now() - (p_days || ' days')::interval
  ),
  
  -- Join for geo-filter (best-effort via confessions)
  geo_reports AS (
    SELECT
      br.report_id,
      br.confession_id,
      br.reason,
      br.city_code,
      br.created_at,
      COALESCE(NULLIF(TRIM(c.region), ''), NULL) AS region
    FROM base_reports br
    LEFT JOIN confessions c ON c.id = br.confession_id
    WHERE 1=1
      -- Geo filters (p_region='Unknown' matches NULL/empty/UNKNOWN)
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      AND (p_city IS NULL OR br.city_code = p_city)
      -- p_country is ignored (no country_code column in confessions)
  ),
  
  -- All qualifying actions (not filtered by time - any action counts)
  actions AS (
    SELECT
      ma.report_id,
      ma.action_type,
      ma.created_at AS action_at
    FROM moderation_actions ma
    WHERE ma.report_id IS NOT NULL
      AND ma.action_type IN ('MARK_HANDLED', 'HIDE_CONFESSION', 'DISMISS_REPORT', 'ESCALATE')
  ),
  
  -- Latest action per report (most recent = current state)
  latest_action AS (
    SELECT DISTINCT ON (a.report_id)
      a.report_id,
      a.action_type,
      a.action_at
    FROM actions a
    ORDER BY a.report_id, a.action_at DESC
  ),
  
  -- Filter to only ESCALATE as latest action + join geo data
  escalated AS (
    SELECT
      gr.report_id,
      gr.confession_id,
      gr.reason,
      gr.region,
      NULL::text AS country_code,  -- Not available
      gr.city_code,
      gr.created_at,
      ROUND((EXTRACT(EPOCH FROM (now() - gr.created_at)) / 3600.0)::numeric, 1) AS hours_open,
      la.action_type AS latest_action,
      la.action_at AS latest_action_at
    FROM latest_action la
    INNER JOIN geo_reports gr ON gr.report_id = la.report_id
    WHERE la.action_type = 'ESCALATE'
  )
  
  SELECT
    e.report_id::text,
    e.confession_id::text,
    e.reason,
    e.region,
    e.country_code,
    e.city_code,
    e.created_at,
    e.hours_open,
    e.latest_action,
    e.latest_action_at
  FROM escalated e
  ORDER BY e.created_at ASC  -- Oldest first (worst first = longest waiting)
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_reports_escalated_v1(int, text, text, text, int, int) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_escalated_v1(30, NULL, NULL, NULL, 20, 0);
-- SELECT * FROM public.get_reports_escalated_v1(7, 'Europe', NULL, NULL, 10, 0);
