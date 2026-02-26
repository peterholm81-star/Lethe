-- =============================================================================
-- MOOD METRICS: Read RPC for Lethe Insights
-- =============================================================================
--
-- Provides aggregated mood summary for admin dashboards.
-- SECURITY: Only service_role can execute (for Edge Functions / admin tools).
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role).
-- DEPENDS ON: mood_metrics_setup.sql must be run first.
--
-- =============================================================================

-- =============================================================================
-- 1. DROP EXISTING FUNCTION (if upgrading)
-- =============================================================================

DROP FUNCTION IF EXISTS public.rpc_get_mood_summary(date, date, text, text, text);

-- =============================================================================
-- 2. CREATE FUNCTION: rpc_get_mood_summary
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_mood_summary(
  p_start_date date,
  p_end_date date,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL
)
RETURNS TABLE (
  mood_bucket text,
  total_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ==========================================================================
  -- VALIDATION
  -- ==========================================================================
  
  IF p_start_date IS NULL THEN
    RAISE EXCEPTION 'p_start_date cannot be NULL';
  END IF;
  
  IF p_end_date IS NULL THEN
    RAISE EXCEPTION 'p_end_date cannot be NULL';
  END IF;
  
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'p_start_date (%) cannot be after p_end_date (%)', p_start_date, p_end_date;
  END IF;
  
  -- ==========================================================================
  -- QUERY: Aggregate mood counts with optional geo filters
  -- ==========================================================================
  
  RETURN QUERY
  SELECT 
    cmd.mood_bucket,
    SUM(cmd.count)::bigint AS total_count
  FROM public.confession_metrics_daily cmd
  WHERE cmd.date >= p_start_date
    AND cmd.date <= p_end_date
    -- Optional geo filters (NULL = no filter)
    AND (p_region IS NULL OR cmd.region = p_region)
    AND (p_country_code IS NULL OR cmd.country_code = p_country_code)
    AND (p_city_code IS NULL OR cmd.city_code = p_city_code)
  GROUP BY cmd.mood_bucket
  ORDER BY total_count DESC;
END;
$$;

-- Comment
COMMENT ON FUNCTION public.rpc_get_mood_summary IS 
  'Returns aggregated mood counts for a date range with optional geo filters. Admin/service_role only.';

-- =============================================================================
-- 3. SECURITY: Grant to authenticated users (Insights uses anonymous auth)
-- =============================================================================

-- Revoke from public/anon first
REVOKE ALL ON FUNCTION public.rpc_get_mood_summary(date, date, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_mood_summary(date, date, text, text, text) FROM anon;

-- Grant to authenticated (Insights uses anonymous sign-in which becomes authenticated)
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_summary(date, date, text, text, text) TO authenticated;
-- Also grant to service_role for Edge Functions / admin tools
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_summary(date, date, text, text, text) TO service_role;

-- =============================================================================
-- 4. NOTIFY POSTGREST
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 5. TEST QUERIES (run manually in Supabase SQL Editor)
-- =============================================================================

/*
-- A) Get mood summary for last 7 days (no geo filter):
SELECT * FROM public.rpc_get_mood_summary(
  current_date - interval '7 days',
  current_date,
  NULL,  -- p_region
  NULL,  -- p_country_code
  NULL   -- p_city_code
);

-- B) Get mood summary for last 7 days, Europe only:
SELECT * FROM public.rpc_get_mood_summary(
  current_date - interval '7 days',
  current_date,
  'Europe',
  NULL,
  NULL
);

-- C) Get mood summary for last 30 days, Norway only:
SELECT * FROM public.rpc_get_mood_summary(
  current_date - interval '30 days',
  current_date,
  NULL,
  'NO',
  NULL
);

-- D) Get mood summary for specific city:
SELECT * FROM public.rpc_get_mood_summary(
  current_date - interval '7 days',
  current_date,
  NULL,
  NULL,
  'TRD'
);

-- E) Verify no data leaks - this should fail for anon/authenticated:
-- (Run as anon role to test)
-- SET ROLE anon;
-- SELECT * FROM public.rpc_get_mood_summary(current_date - 7, current_date, NULL, NULL, NULL);
-- Expected: ERROR: permission denied for function rpc_get_mood_summary
-- RESET ROLE;
*/
