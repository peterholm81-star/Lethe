-- ============================================================
-- PULSE Metrics RPC: get_pulse_metrics
-- ============================================================
-- Calculates daily pulse metrics from event_logs.
--
-- Returns:
--   - sessions_today: COUNT(DISTINCT session_hash) where session_start
--   - readers_today: COUNT(DISTINCT session_hash) where page_fetch
--   - posts_today: COUNT(*) where post_success
--
-- Filters: country_code, region, city_code, mode (all optional)
-- Date: p_date (defaults to CURRENT_DATE)
-- ============================================================

-- Drop all existing variants to avoid "not unique" error
DROP FUNCTION IF EXISTS public.get_pulse_metrics();
DROP FUNCTION IF EXISTS public.get_pulse_metrics(text, text, date);
DROP FUNCTION IF EXISTS public.get_pulse_metrics(date, text, text, text, text);

-- ============================================================
-- Parameterized version (core logic)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_pulse_metrics(
  p_date date DEFAULT CURRENT_DATE,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_mode text DEFAULT NULL
)
RETURNS TABLE (
  sessions_today integer,
  readers_today integer,
  posts_today integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    -- Sessions: distinct session_hash with session_start event
    (SELECT COUNT(DISTINCT session_hash)::integer
     FROM event_logs
     WHERE event_name = 'session_start'
       AND day_bucket = p_date
       AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
       AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
       AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
       AND (p_mode IS NULL OR mode = p_mode)
    ) AS sessions_today,
    
    -- Readers: distinct session_hash with page_fetch event
    (SELECT COUNT(DISTINCT session_hash)::integer
     FROM event_logs
     WHERE event_name = 'page_fetch'
       AND day_bucket = p_date
       AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
       AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
       AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
       AND (p_mode IS NULL OR mode = p_mode)
    ) AS readers_today,
    
    -- Posts: count of post_success events
    (SELECT COUNT(*)::integer
     FROM event_logs
     WHERE event_name = 'post_success'
       AND day_bucket = p_date
       AND (p_country_code IS NULL OR UPPER(TRIM(country_code)) = UPPER(TRIM(p_country_code)))
       AND (p_region IS NULL OR UPPER(TRIM(region)) = UPPER(TRIM(p_region)))
       AND (p_city_code IS NULL OR UPPER(TRIM(city_code)) = UPPER(TRIM(p_city_code)))
       AND (p_mode IS NULL OR mode = p_mode)
    ) AS posts_today;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics(date, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics(date, text, text, text, text) TO authenticated;

-- ============================================================
-- TEST QUERIES
-- ============================================================
SELECT '--- Pulse (global, today) ---' AS test;
SELECT * FROM public.get_pulse_metrics();

SELECT '--- Pulse (Europe, today) ---' AS test;
SELECT * FROM public.get_pulse_metrics(CURRENT_DATE, 'Europe', NULL, NULL, NULL);

SELECT '--- Pulse (UK, today) ---' AS test;
SELECT * FROM public.get_pulse_metrics(CURRENT_DATE, NULL, 'UK', NULL, NULL);

SELECT '--- Pulse (Europe/UK/LON, today) ---' AS test;
SELECT * FROM public.get_pulse_metrics(CURRENT_DATE, 'Europe', 'UK', 'LON', NULL);
