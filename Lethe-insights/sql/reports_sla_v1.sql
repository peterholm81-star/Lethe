-- =============================================================================
-- RPC: get_reports_sla_v1
-- Returns SLA metrics: time to action for reports.
-- =============================================================================
--
-- METRICS:
-- - median_minutes: Median time from report creation to first action (NULL if no actioned)
-- - p90_minutes: 90th percentile time to action (NULL if no actioned)
-- - oldest_pending_minutes: Age of oldest pending report in window (NULL if none pending)
-- - actioned_reports: Count of reports that have been actioned within window
-- - pending_reports: Count of reports still waiting for action within window
--
-- DEFINITIONS:
-- - "Actioned" = has a moderation_action with action_type IN
--   ('MARK_HANDLED', 'HIDE_CONFESSION', 'DISMISS_REPORT', 'ESCALATE')
-- - UNHIDE_CONFESSION does NOT count as actioning a report for SLA purposes
-- - All calculations are scoped to reports created within the time window
-- - Only actions that occurred WITHIN the window count for median/p90
--
-- SCHEMA NOTES:
-- - Reports are in confession_reports table
-- - confession_reports.city_code exists (geo filtering supported)
-- - confession_reports does NOT have region/country_code directly
-- - To filter by region: join via confession_reports -> confessions (c.region)
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_sla_v1(int, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_sla_v1(
  p_days int DEFAULT 30,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- Not used (no country_code in schema)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  median_minutes numeric,
  p90_minutes numeric,
  oldest_pending_minutes numeric,
  actioned_reports int,
  pending_reports int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_start timestamptz;
BEGIN
  -- Auth check: require authenticated user (read-only metrics, no admin required)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access denied: authentication required';
  END IF;

  -- Calculate window start
  v_window_start := now() - (p_days || ' days')::interval;

  RETURN QUERY
  WITH 
  -- Base reports within time window, with optional geo filters via confessions join
  base_reports AS (
    SELECT 
      cr.id AS report_id,
      cr.created_at AS report_created_at
    FROM confession_reports cr
    LEFT JOIN confessions c ON c.id = cr.confession_id
    WHERE cr.created_at >= v_window_start
      -- Geo filters (p_region='Unknown' matches NULL/empty/UNKNOWN)
      AND (
        p_region IS NULL 
        OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
        OR (p_region != 'Unknown' AND c.region = p_region)
      )
      AND (p_city IS NULL OR cr.city_code = p_city)
      -- p_country is ignored (no country_code column in schema)
  ),
  
  -- First action per report WITHIN THE WINDOW (only "actioning" action types)
  first_actions AS (
    SELECT
      ma.report_id,
      MIN(ma.created_at) AS first_action_at
    FROM moderation_actions ma
    WHERE ma.report_id IS NOT NULL
      AND ma.action_type IN ('MARK_HANDLED', 'HIDE_CONFESSION', 'DISMISS_REPORT', 'ESCALATE')
      AND ma.created_at >= v_window_start  -- Action must be within window
    GROUP BY ma.report_id
  ),
  
  -- Join reports with their first action (if any within window)
  joined AS (
    SELECT
      br.report_id,
      br.report_created_at,
      fa.first_action_at,
      CASE 
        WHEN fa.first_action_at IS NULL THEN NULL
        -- Only positive time-to-action (action after report creation)
        WHEN fa.first_action_at < br.report_created_at THEN NULL
        ELSE EXTRACT(EPOCH FROM (fa.first_action_at - br.report_created_at)) / 60.0
      END AS minutes_to_action
    FROM base_reports br
    LEFT JOIN first_actions fa ON fa.report_id = br.report_id
  ),
  
  -- Compute aggregates
  stats AS (
    SELECT
      -- Median time to action (only for actioned reports, NULL if none)
      (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY minutes_to_action)
       FROM joined
       WHERE minutes_to_action IS NOT NULL AND minutes_to_action >= 0) AS median_val,
      
      -- P90 time to action (only for actioned reports, NULL if none)
      (SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY minutes_to_action)
       FROM joined
       WHERE minutes_to_action IS NOT NULL AND minutes_to_action >= 0) AS p90_val,
      
      -- Oldest pending report age (only reports without action in window)
      (SELECT EXTRACT(EPOCH FROM (now() - report_created_at)) / 60.0
       FROM joined
       WHERE minutes_to_action IS NULL
       ORDER BY report_created_at ASC
       LIMIT 1) AS oldest_pending_val,
      
      -- Count actioned (within window)
      (SELECT COUNT(*) FROM joined WHERE minutes_to_action IS NOT NULL AND minutes_to_action >= 0) AS actioned_count,
      
      -- Count pending (no action within window)
      (SELECT COUNT(*) FROM joined WHERE minutes_to_action IS NULL) AS pending_count
  )
  
  SELECT
    -- Return NULL (not 0) if no actioned reports, so UI can show "—"
    CASE 
      WHEN s.actioned_count = 0 THEN NULL
      ELSE ROUND((s.median_val)::numeric, 1)
    END AS median_minutes,
    CASE 
      WHEN s.actioned_count = 0 THEN NULL
      ELSE ROUND((s.p90_val)::numeric, 1)
    END AS p90_minutes,
    -- Return NULL if no pending reports
    CASE 
      WHEN s.pending_count = 0 THEN NULL
      ELSE ROUND((s.oldest_pending_val)::numeric, 1)
    END AS oldest_pending_minutes,
    COALESCE(s.actioned_count, 0)::int AS actioned_reports,
    COALESCE(s.pending_count, 0)::int AS pending_reports
  FROM stats s;
END;
$$;

-- Grant execute to authenticated users (read-only metrics, no admin required)
GRANT EXECUTE ON FUNCTION public.get_reports_sla_v1(int, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_sla_v1(30, NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_sla_v1(7, 'Europe', NULL, NULL);
-- SELECT * FROM public.get_reports_sla_v1(7, NULL, NULL, 'TRD');
