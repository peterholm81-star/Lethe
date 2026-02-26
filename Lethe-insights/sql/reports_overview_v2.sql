-- =============================================================================
-- RPC: get_reports_overview_v2
-- Returns aggregated KPI metrics for Reports Intelligence dashboard.
-- =============================================================================
-- 
-- AUDIT NOTE (2026-02-03):
-- - confessions.region EXISTS
-- - confessions.city_code EXISTS  
-- - confessions.created_at EXISTS
-- - confessions.country_code DOES NOT EXIST (removed from filter)
-- - confessions.updated_at DOES NOT EXIST (using created_at instead)
-- - p_country parameter kept for future compatibility but IGNORED
--
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_reports_overview_v2(text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_overview_v2(
  p_range text DEFAULT '24h',
  p_region text DEFAULT NULL,
  p_country text DEFAULT NULL,  -- IGNORED in v1 (column doesn't exist)
  p_city text DEFAULT NULL
)
RETURNS TABLE (
  reports_total bigint,
  reports_per_1k_reads numeric,
  hidden_total bigint,
  severity_score numeric,
  spike_detected boolean,
  actions_total bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz;
  v_reports bigint;
  v_reads bigint;
  v_hidden bigint;
  v_actions bigint;
  v_severity numeric;
  v_reports_per_1k numeric;
BEGIN
  -- Determine time range start
  v_start := CASE p_range
    WHEN '60m' THEN now() - interval '60 minutes'
    WHEN '24h' THEN now() - interval '24 hours'
    WHEN '7d'  THEN now() - interval '7 days'
    WHEN '30d' THEN now() - interval '30 days'
    ELSE now() - interval '24 hours'  -- default fallback
  END;

  -- ==========================================================================
  -- REPORTS TOTAL
  -- Count reports in the time range, optionally filtered by geo
  -- NOTE: p_country is IGNORED (confessions.country_code doesn't exist)
  -- ==========================================================================
  SELECT COALESCE(COUNT(*), 0)
  INTO v_reports
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND c.region = p_region)
    )
    AND (p_city IS NULL OR c.city_code = p_city);

  -- ==========================================================================
  -- READS (distinct sessions from event_logs)
  -- ==========================================================================
  SELECT COALESCE(COUNT(DISTINCT session_hash), 0)
  INTO v_reads
  FROM event_logs
  WHERE event_name = 'page_fetch'
    AND created_at >= v_start;
  -- NOTE: event_logs geo filter not applied in v1

  -- ==========================================================================
  -- REPORTS PER 1K READS
  -- ==========================================================================
  IF v_reads > 0 THEN
    v_reports_per_1k := ROUND((v_reports::numeric / v_reads) * 1000, 2);
  ELSE
    v_reports_per_1k := NULL;
  END IF;

  -- ==========================================================================
  -- HIDDEN TOTAL
  -- Count confessions that are hidden and were created in range
  -- NOTE: confessions.updated_at DOES NOT EXIST, using created_at
  -- ==========================================================================
  SELECT COALESCE(COUNT(*), 0)
  INTO v_hidden
  FROM confessions c
  WHERE c.is_hidden = true
    AND c.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND c.region = p_region)
    )
    AND (p_city IS NULL OR c.city_code = p_city);

  -- ==========================================================================
  -- ACTIONS TOTAL
  -- Filter by region/city if provided (geo stored in context jsonb)
  -- ==========================================================================
  SELECT COALESCE(COUNT(*), 0)
  INTO v_actions
  FROM moderation_actions ma
  WHERE ma.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND ((ma.context->>'region') IS NULL OR TRIM(ma.context->>'region') = '' OR UPPER(TRIM(ma.context->>'region')) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND (ma.context->>'region') = p_region)
    )
    AND (p_city IS NULL OR (ma.context->>'cityCode') = p_city);

  -- ==========================================================================
  -- SEVERITY SCORE (avg weighted by reason)
  -- Weights: THREATS=5, IDENTIFYING=5, CONTACT=4, HARASSMENT=4, SPAM=2, OTHER=1
  -- ==========================================================================
  SELECT COALESCE(
    ROUND(AVG(
      CASE UPPER(cr.reason)
        WHEN 'THREATS' THEN 5
        WHEN 'IDENTIFYING' THEN 5
        WHEN 'VIOLENCE' THEN 5
        WHEN 'SELF_HARM' THEN 5
        WHEN 'HATE' THEN 5
        WHEN 'HARASSMENT' THEN 4
        WHEN 'CONTACT' THEN 4
        WHEN 'SPAM' THEN 2
        ELSE 1
      END
    ), 1),
    0
  )
  INTO v_severity
  FROM confession_reports cr
  LEFT JOIN confessions c ON c.id = cr.confession_id
  WHERE cr.created_at >= v_start
    AND (
      p_region IS NULL 
      OR (p_region = 'Unknown' AND (c.region IS NULL OR TRIM(c.region) = '' OR UPPER(TRIM(c.region)) = 'UNKNOWN'))
      OR (p_region != 'Unknown' AND c.region = p_region)
    )
    AND (p_city IS NULL OR c.city_code = p_city);

  -- ==========================================================================
  -- RETURN
  -- ==========================================================================
  RETURN QUERY SELECT
    v_reports AS reports_total,
    v_reports_per_1k AS reports_per_1k_reads,
    v_hidden AS hidden_total,
    v_severity AS severity_score,
    false AS spike_detected,  -- v1 placeholder
    v_actions AS actions_total;
END;
$$;

-- Grant execute to authenticated users (Insights uses authenticated sessions)
GRANT EXECUTE ON FUNCTION public.get_reports_overview_v2(text, text, text, text) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- TEST QUERY (run manually to verify)
-- =============================================================================
-- SELECT * FROM public.get_reports_overview_v2('24h', NULL, NULL, NULL);
-- SELECT * FROM public.get_reports_overview_v2('7d', 'Europe', NULL, NULL);
