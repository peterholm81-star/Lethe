-- =============================================================================
-- Seed: event_logs for Lethe Insights (Global test data)
-- =============================================================================
-- This script generates realistic test data for the past 7 days.
-- All seeded session_hash values are prefixed with 'seed_' for easy cleanup.
--
-- Run with: psql -f seed_event_logs_global.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- OPTIONAL: Uncomment to DELETE previous seed data before inserting new
-- =============================================================================
-- DELETE FROM public.event_logs WHERE session_hash LIKE 'seed_%';

-- =============================================================================
-- Configuration
-- =============================================================================
DO $$
DECLARE
  -- Date range
  v_start_date DATE := CURRENT_DATE - 6;
  v_end_date   DATE := CURRENT_DATE;
  
  -- Target sessions per day (will vary by day-of-week feel)
  v_base_sessions_per_day INT := 150;
  
  -- Geo data arrays
  v_regions TEXT[] := ARRAY['Europe', 'North America', 'South America', 'Asia', 'Oceania', 'Africa'];
  
  -- City/Country mapping (city_code, country_code, region, weight)
  -- Weight affects how often this city appears (higher = more common)
  
  -- Loop variables
  v_day DATE;
  v_sessions_today INT;
  v_session_hash TEXT;
  v_region TEXT;
  v_country_code TEXT;
  v_city_code TEXT;
  v_mode TEXT;
  v_mode_rand FLOAT;
  v_geo_rand FLOAT;
  v_base_time TIMESTAMPTZ;
  v_event_time TIMESTAMPTZ;
  v_time_bucket INT;  -- 1=morning, 2=afternoon, 3=evening, 4=night
  v_event_hour INT;
  v_page_count INT;
  v_has_post_attempt BOOLEAN;
  v_has_post_success BOOLEAN;
  v_has_ad_shown BOOLEAN;
  v_ad_time TIMESTAMPTZ;
  v_continues_after_ad BOOLEAN;
  v_post_pages_after_ad INT;
  v_i INT;
  v_hour INT;
  v_minute INT;
  
BEGIN
  -- Loop through each day
  FOR v_day IN SELECT generate_series(v_start_date, v_end_date, '1 day'::interval)::date
  LOOP
    -- Vary sessions by day (weekends slightly higher)
    v_sessions_today := v_base_sessions_per_day + (random() * 50)::int - 25;
    IF EXTRACT(DOW FROM v_day) IN (0, 6) THEN
      v_sessions_today := v_sessions_today + 30; -- Weekend boost
    END IF;
    
    -- Generate sessions for this day
    FOR v_i IN 1..v_sessions_today
    LOOP
      -- Generate unique session hash with seed_ prefix
      v_session_hash := 'seed_' || md5(random()::text || v_day::text || v_i::text || clock_timestamp()::text);
      
      -- Pick geo location (weighted distribution)
      v_geo_rand := random();
      IF v_geo_rand < 0.35 THEN
        -- Europe (35%)
        v_region := 'Europe';
        CASE (random() * 3)::int
          WHEN 0 THEN v_city_code := 'LON'; v_country_code := 'UK';
          WHEN 1 THEN v_city_code := 'PAR'; v_country_code := 'FR';
          ELSE v_city_code := 'BER'; v_country_code := 'DE';
        END CASE;
      ELSIF v_geo_rand < 0.60 THEN
        -- North America (25%)
        v_region := 'North America';
        CASE (random() * 3)::int
          WHEN 0 THEN v_city_code := 'NYC'; v_country_code := 'US';
          WHEN 1 THEN v_city_code := 'LAX'; v_country_code := 'US';
          ELSE v_city_code := 'TOR'; v_country_code := 'CA';
        END CASE;
      ELSIF v_geo_rand < 0.75 THEN
        -- Asia (15%)
        v_region := 'Asia';
        CASE (random() * 3)::int
          WHEN 0 THEN v_city_code := 'TOK'; v_country_code := 'JP';
          WHEN 1 THEN v_city_code := 'SEL'; v_country_code := 'KR';
          ELSE v_city_code := 'SIN'; v_country_code := 'SG';
        END CASE;
      ELSIF v_geo_rand < 0.85 THEN
        -- South America (10%)
        v_region := 'South America';
        IF random() < 0.6 THEN
          v_city_code := 'SAO'; v_country_code := 'BR';
        ELSE
          v_city_code := 'BUE'; v_country_code := 'AR';
        END IF;
      ELSIF v_geo_rand < 0.93 THEN
        -- Oceania (8%)
        v_region := 'Oceania';
        v_city_code := 'SYD'; v_country_code := 'AU';
      ELSE
        -- Africa (7%)
        v_region := 'Africa';
        v_city_code := 'CPT'; v_country_code := 'ZA';
      END IF;
      
      -- Pick mode (50% world, 35% near, 15% somewhere)
      v_mode_rand := random();
      IF v_mode_rand < 0.50 THEN
        v_mode := 'world';
      ELSIF v_mode_rand < 0.85 THEN
        v_mode := 'near';
      ELSE
        v_mode := 'somewhere';
      END IF;
      
      -- Generate base time for session (evening bias: 18:00-02:00 UTC spread)
      v_hour := 18 + (random() * 8)::int; -- 18-26 (wraps to next day for 24-26)
      IF v_hour >= 24 THEN
        v_hour := v_hour - 24;
      END IF;
      v_minute := (random() * 60)::int;
      v_base_time := v_day + (v_hour || ' hours')::interval + (v_minute || ' minutes')::interval + (random() * 60 || ' seconds')::interval;
      
      -- =======================================================================
      -- Helper: Determine time_bucket from event hour (INTEGER codes)
      -- 1=morning (06-12), 2=afternoon (12-18), 3=evening (18-22), 4=night (22-06)
      -- =======================================================================
      v_event_hour := EXTRACT(HOUR FROM v_base_time)::int;
      IF v_event_hour >= 6 AND v_event_hour < 12 THEN
        v_time_bucket := 1;  -- morning
      ELSIF v_event_hour >= 12 AND v_event_hour < 18 THEN
        v_time_bucket := 2;  -- afternoon
      ELSIF v_event_hour >= 18 AND v_event_hour < 22 THEN
        v_time_bucket := 3;  -- evening
      ELSIF v_event_hour >= 22 OR v_event_hour < 6 THEN
        v_time_bucket := 4;  -- night
      ELSE
        v_time_bucket := 4;  -- Safe fallback to night
      END IF;
      
      -- =======================================================================
      -- EVENT: session_start (always)
      -- =======================================================================
      INSERT INTO public.event_logs (event_name, created_at, day_bucket, time_bucket, session_hash, country_code, region, city_code, mode)
      VALUES ('session_start', v_base_time, v_day, v_time_bucket, v_session_hash, v_country_code, v_region, v_city_code, v_mode);
      
      v_event_time := v_base_time + ((random() * 5 + 1) || ' seconds')::interval;
      
      -- =======================================================================
      -- EVENT: page_fetch (1-25, skewed distribution)
      -- Most users: 3-8 pages, power users: 15-25
      -- =======================================================================
      IF random() < 0.15 THEN
        -- Power user (15%)
        v_page_count := 15 + (random() * 11)::int; -- 15-25
      ELSIF random() < 0.30 THEN
        -- Light user (30%)
        v_page_count := 1 + (random() * 3)::int; -- 1-3
      ELSE
        -- Normal user (55%)
        v_page_count := 3 + (random() * 6)::int; -- 3-8
      END IF;
      
      -- Track if we should show an ad (after 6+ pages)
      v_has_ad_shown := FALSE;
      v_ad_time := NULL;
      
      FOR v_i IN 1..v_page_count
      LOOP
        -- Recalculate time_bucket for this event (INTEGER codes)
        v_event_hour := EXTRACT(HOUR FROM v_event_time)::int;
        IF v_event_hour >= 6 AND v_event_hour < 12 THEN
          v_time_bucket := 1;  -- morning
        ELSIF v_event_hour >= 12 AND v_event_hour < 18 THEN
          v_time_bucket := 2;  -- afternoon
        ELSIF v_event_hour >= 18 AND v_event_hour < 22 THEN
          v_time_bucket := 3;  -- evening
        ELSIF v_event_hour >= 22 OR v_event_hour < 6 THEN
          v_time_bucket := 4;  -- night
        ELSE
          v_time_bucket := 4;  -- Safe fallback to night
        END IF;
        
        INSERT INTO public.event_logs (event_name, created_at, day_bucket, time_bucket, session_hash, country_code, region, city_code, mode)
        VALUES ('page_fetch', v_event_time, v_day, v_time_bucket, v_session_hash, v_country_code, v_region, v_city_code, v_mode);
        
        -- Show ad after 6th page_fetch (only once per session)
        IF v_i = 6 AND NOT v_has_ad_shown THEN
          v_ad_time := v_event_time + ((random() * 3 + 1) || ' seconds')::interval;
          
          -- Recalculate time_bucket for ad event (INTEGER codes)
          v_event_hour := EXTRACT(HOUR FROM v_ad_time)::int;
          IF v_event_hour >= 6 AND v_event_hour < 12 THEN
            v_time_bucket := 1;  -- morning
          ELSIF v_event_hour >= 12 AND v_event_hour < 18 THEN
            v_time_bucket := 2;  -- afternoon
          ELSIF v_event_hour >= 18 AND v_event_hour < 22 THEN
            v_time_bucket := 3;  -- evening
          ELSIF v_event_hour >= 22 OR v_event_hour < 6 THEN
            v_time_bucket := 4;  -- night
          ELSE
            v_time_bucket := 4;  -- Safe fallback to night
          END IF;
          
          INSERT INTO public.event_logs (event_name, created_at, day_bucket, time_bucket, session_hash, country_code, region, city_code, mode)
          VALUES ('ad_shown', v_ad_time, v_day, v_time_bucket, v_session_hash, v_country_code, v_region, v_city_code, v_mode);
          v_has_ad_shown := TRUE;
          
          -- Decide if user continues after ad (65-75% continue)
          v_continues_after_ad := random() < 0.70;
          
          IF NOT v_continues_after_ad THEN
            -- User drops after ad - stop page_fetch here
            EXIT;
          END IF;
        END IF;
        
        v_event_time := v_event_time + ((random() * 30 + 5) || ' seconds')::interval;
      END LOOP;
      
      -- =======================================================================
      -- EVENT: post_attempt (25-40% of sessions)
      -- =======================================================================
      v_has_post_attempt := random() < 0.32; -- ~32%
      
      IF v_has_post_attempt THEN
        v_event_time := v_event_time + ((random() * 20 + 10) || ' seconds')::interval;
        
        -- Recalculate time_bucket for post_attempt (INTEGER codes)
        v_event_hour := EXTRACT(HOUR FROM v_event_time)::int;
        IF v_event_hour >= 6 AND v_event_hour < 12 THEN
          v_time_bucket := 1;  -- morning
        ELSIF v_event_hour >= 12 AND v_event_hour < 18 THEN
          v_time_bucket := 2;  -- afternoon
        ELSIF v_event_hour >= 18 AND v_event_hour < 22 THEN
          v_time_bucket := 3;  -- evening
        ELSIF v_event_hour >= 22 OR v_event_hour < 6 THEN
          v_time_bucket := 4;  -- night
        ELSE
          v_time_bucket := 4;  -- Safe fallback to night
        END IF;
        
        INSERT INTO public.event_logs (event_name, created_at, day_bucket, time_bucket, session_hash, country_code, region, city_code, mode)
        VALUES ('post_attempt', v_event_time, v_day, v_time_bucket, v_session_hash, v_country_code, v_region, v_city_code, v_mode);
        
        -- =======================================================================
        -- EVENT: post_success (60-80% of attempts)
        -- =======================================================================
        v_has_post_success := random() < 0.72; -- ~72%
        
        IF v_has_post_success THEN
          v_event_time := v_event_time + ((random() * 3 + 1) || ' seconds')::interval;
          
          -- Recalculate time_bucket for post_success (INTEGER codes)
          v_event_hour := EXTRACT(HOUR FROM v_event_time)::int;
          IF v_event_hour >= 6 AND v_event_hour < 12 THEN
            v_time_bucket := 1;  -- morning
          ELSIF v_event_hour >= 12 AND v_event_hour < 18 THEN
            v_time_bucket := 2;  -- afternoon
          ELSIF v_event_hour >= 18 AND v_event_hour < 22 THEN
            v_time_bucket := 3;  -- evening
          ELSIF v_event_hour >= 22 OR v_event_hour < 6 THEN
            v_time_bucket := 4;  -- night
          ELSE
            v_time_bucket := 4;  -- Safe fallback to night
          END IF;
          
          INSERT INTO public.event_logs (event_name, created_at, day_bucket, time_bucket, session_hash, country_code, region, city_code, mode)
          VALUES ('post_success', v_event_time, v_day, v_time_bucket, v_session_hash, v_country_code, v_region, v_city_code, v_mode);
        END IF;
      END IF;
      
    END LOOP; -- sessions
    
    RAISE NOTICE 'Generated % sessions for %', v_sessions_today, v_day;
    
  END LOOP; -- days
  
  RAISE NOTICE 'Seed complete!';
END $$;

COMMIT;

-- =============================================================================
-- SANITY CHECK QUERIES (run these after seeding to verify)
-- =============================================================================

-- Verify no NULL time_bucket in seeded data
SELECT 'Rows with NULL time_bucket (should be 0)' AS check_name, 
       COUNT(*) AS count
FROM public.event_logs
WHERE session_hash LIKE 'seed_%'
  AND time_bucket IS NULL;

-- time_bucket distribution (1=morning, 2=afternoon, 3=evening, 4=night)
SELECT time_bucket,
       CASE time_bucket
         WHEN 1 THEN 'morning (06-12)'
         WHEN 2 THEN 'afternoon (12-18)'
         WHEN 3 THEN 'evening (18-22)'
         WHEN 4 THEN 'night (22-06)'
         ELSE 'unknown'
       END AS time_bucket_label,
       COUNT(*) AS count
FROM public.event_logs
WHERE session_hash LIKE 'seed_%'
GROUP BY time_bucket
ORDER BY time_bucket;

-- Total events in last 7 days
SELECT 'Total events (last 7 days)' AS metric, COUNT(*) AS value
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6;

-- Distinct sessions in last 7 days
SELECT 'Distinct sessions (last 7 days)' AS metric, COUNT(DISTINCT session_hash) AS value
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6;

-- Event counts by event_name
SELECT event_name, COUNT(*) AS count
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
GROUP BY event_name
ORDER BY count DESC;

-- Per-region session counts
SELECT region, COUNT(DISTINCT session_hash) AS sessions
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
GROUP BY region
ORDER BY sessions DESC;

-- Per-country session counts
SELECT country_code, COUNT(DISTINCT session_hash) AS sessions
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
GROUP BY country_code
ORDER BY sessions DESC;

-- Per-city session counts
SELECT city_code, COUNT(DISTINCT session_hash) AS sessions
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
GROUP BY city_code
ORDER BY sessions DESC;

-- Mode distribution
SELECT mode, COUNT(DISTINCT session_hash) AS sessions,
       ROUND(100.0 * COUNT(DISTINCT session_hash) / SUM(COUNT(DISTINCT session_hash)) OVER (), 1) AS pct
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
GROUP BY mode
ORDER BY sessions DESC;

-- Daily session trend
SELECT day_bucket, COUNT(DISTINCT session_hash) AS sessions
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
GROUP BY day_bucket
ORDER BY day_bucket;

-- Ad engagement summary
SELECT 
  'Sessions with ad_shown' AS metric,
  COUNT(DISTINCT session_hash) AS value
FROM public.event_logs
WHERE day_bucket >= CURRENT_DATE - 6
  AND event_name = 'ad_shown';

-- Post conversion funnel
SELECT 
  (SELECT COUNT(DISTINCT session_hash) FROM public.event_logs WHERE day_bucket >= CURRENT_DATE - 6) AS total_sessions,
  (SELECT COUNT(DISTINCT session_hash) FROM public.event_logs WHERE day_bucket >= CURRENT_DATE - 6 AND event_name = 'post_attempt') AS with_post_attempt,
  (SELECT COUNT(DISTINCT session_hash) FROM public.event_logs WHERE day_bucket >= CURRENT_DATE - 6 AND event_name = 'post_success') AS with_post_success;

-- =============================================================================
-- TEST: get_engagement_flow RPC
-- =============================================================================
SELECT '--- get_engagement_flow(NULL, NULL, NULL, NULL, 7) ---' AS test;
SELECT * FROM public.get_engagement_flow(NULL, NULL, NULL, NULL, 7);

-- Test with filter: Europe only
SELECT '--- get_engagement_flow(NULL, Europe, NULL, NULL, 7) ---' AS test;
SELECT * FROM public.get_engagement_flow(NULL, 'Europe', NULL, NULL, 7);

-- Test with filter: US only
SELECT '--- get_engagement_flow(US, NULL, NULL, NULL, 7) ---' AS test;
SELECT * FROM public.get_engagement_flow('US', NULL, NULL, NULL, 7);

-- Test with filter: mode = world
SELECT '--- get_engagement_flow(NULL, NULL, NULL, world, 7) ---' AS test;
SELECT * FROM public.get_engagement_flow(NULL, NULL, NULL, 'world', 7);
