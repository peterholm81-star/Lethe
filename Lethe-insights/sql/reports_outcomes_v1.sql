-- =============================================================================
-- RPC: get_reports_outcomes_v1
-- Returns outcome breakdown for actioned reports.
-- =============================================================================
--
-- METRICS:
-- - actioned_reports: Total reports with at least one qualifying action
-- - handled_reports: Reports where latest action is MARK_HANDLED
-- - hidden_reports: Reports where latest action is HIDE_CONFESSION
-- - dismissed_reports: Reports where latest action is DISMISS_REPORT
-- - escalated_reports: Reports where latest action is ESCALATE
-- - *_rate_pct: Percentage of each outcome type
--
-- DEFINITIONS:
-- - "Latest action" = most recent moderation_action per report_id
-- - UNHIDE_CONFESSION does NOT count as an outcome
-- - Rates are based on actioned_reports as denominator
--
-- SCHEMA NOTES:
-- - Reports are in confession_reports table
-- - confession_reports.city_code exists
-- - confession_reports does NOT have region/country_code directly
-- - To filter by region: join via confession_reports -> confessions (c.region)
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_outcomes_v1(int, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_outcomes_v1(
  p_days int DEFAULT 30,
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- Not used (no country_code in confessions)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  actioned_reports int,
  handled_reports int,
  hidden_reports int,
  dismissed_reports int,
  escalated_reports int,
  handled_rate_pct numeric,
  hidden_rate_pct numeric,
  dismissed_rate_pct numeric,
  escalated_rate_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Auth check: require authenticated user (read-only metrics, no admin required)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access denied: authentication required';
  END IF;

  RETURN QUERY
  WITH 
  -- Base reports within time window
  base_reports AS (
    SELECT 
      cr.id AS report_id,
      cr.created_at,
      cr.confession_id,
      cr.city_code
    FROM confession_reports cr
    WHERE cr.created_at >= now() - (p_days || ' days')::interval
  ),
  
  -- Join for geo-filter (best-effort via confessions)
  geo_reports AS (
    SELECT
      br.report_id,
      br.created_at,
      br.city_code,
      c.region
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
  
  -- All qualifying actions within time window
  actions AS (
    SELECT
      ma.report_id,
      ma.action_type,
      ma.created_at
    FROM moderation_actions ma
    WHERE ma.report_id IS NOT NULL
      AND ma.action_type IN ('MARK_HANDLED', 'HIDE_CONFESSION', 'DISMISS_REPORT', 'ESCALATE')
  ),
  
  -- Latest action per report (most recent = final outcome)
  latest_action AS (
    SELECT DISTINCT ON (a.report_id)
      a.report_id,
      a.action_type
    FROM actions a
    ORDER BY a.report_id, a.created_at DESC
  ),
  
  -- Scope to geo-filtered reports
  scoped_latest AS (
    SELECT la.report_id, la.action_type
    FROM latest_action la
    INNER JOIN geo_reports gr ON gr.report_id = la.report_id
  ),
  
  -- Count outcomes
  counts AS (
    SELECT
      COUNT(*)::int AS actioned_reports,
      COUNT(*) FILTER (WHERE action_type = 'MARK_HANDLED')::int AS handled_reports,
      COUNT(*) FILTER (WHERE action_type = 'HIDE_CONFESSION')::int AS hidden_reports,
      COUNT(*) FILTER (WHERE action_type = 'DISMISS_REPORT')::int AS dismissed_reports,
      COUNT(*) FILTER (WHERE action_type = 'ESCALATE')::int AS escalated_reports
    FROM scoped_latest
  )
  
  SELECT
    c.actioned_reports,
    c.handled_reports,
    c.hidden_reports,
    c.dismissed_reports,
    c.escalated_reports,
    CASE WHEN c.actioned_reports = 0 THEN 0
         ELSE ROUND((c.handled_reports::numeric / c.actioned_reports::numeric) * 100, 1)
    END AS handled_rate_pct,
    CASE WHEN c.actioned_reports = 0 THEN 0
         ELSE ROUND((c.hidden_reports::numeric / c.actioned_reports::numeric) * 100, 1)
    END AS hidden_rate_pct,
    CASE WHEN c.actioned_reports = 0 THEN 0
         ELSE ROUND((c.dismissed_reports::numeric / c.actioned_reports::numeric) * 100, 1)
    END AS dismissed_rate_pct,
    CASE WHEN c.actioned_reports = 0 THEN 0
         ELSE ROUND((c.escalated_reports::numeric / c.actioned_reports::numeric) * 100, 1)
    END AS escalated_rate_pct
  FROM counts c;
END;
$$;

-- Grant execute to authenticated users (read-only metrics, no admin required)
GRANT EXECUTE ON FUNCTION public.get_reports_outcomes_v1(int, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================
-- SELECT * FROM public.get_reports_outcomes_v1(30, NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_outcomes_v1(7, 'Europe', NULL, NULL);
-- SELECT * FROM public.get_reports_outcomes_v1(7, NULL, NULL, 'TRD');
