-- ============================================================
-- DIAGNOSE AND FIX CHANGE OVER TIME DATA ALIGNMENT
-- ============================================================

-- 1) Inspect daily_metrics columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'daily_metrics'
ORDER BY ordinal_position;

-- 2) Inspect daily_readers_writers columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'daily_readers_writers'
ORDER BY ordinal_position;

-- 3) Side-by-side comparison: which days have data in each table?
SELECT 
  COALESCE(dm.day_bucket, drw.day_bucket) AS day_bucket,
  dm.sessions,
  dm.readers AS dm_readers,
  dm.post_success AS dm_posts,
  drw.readers_today AS drw_readers,
  drw.writers_today AS drw_writers,
  drw.writer_share AS drw_writer_share
FROM daily_metrics dm
FULL OUTER JOIN daily_readers_writers drw 
  ON dm.day_bucket = drw.day_bucket 
  AND dm.city_code = drw.city_code 
  AND dm.region = drw.region
WHERE (dm.city_code = 'WORLD' OR dm.city_code IS NULL)
  AND (dm.region = 'WORLD' OR dm.region IS NULL)
  AND (drw.city_code = 'WORLD' OR drw.city_code IS NULL)
  AND (drw.region = 'WORLD' OR drw.region IS NULL)
ORDER BY day_bucket DESC
LIMIT 10;

-- ============================================================
-- FIX: Sync daily_readers_writers with daily_metrics dates
-- ============================================================

-- Insert missing rows into daily_readers_writers based on daily_metrics
-- Compute writer_share as post_success / readers (writers = people who posted)
INSERT INTO daily_readers_writers (day_bucket, city_code, region, readers_today, writers_today, writer_share)
SELECT 
  dm.day_bucket,
  dm.city_code,
  dm.region,
  dm.readers AS readers_today,
  dm.post_success AS writers_today,  -- Assuming post_success = number of writers
  CASE 
    WHEN dm.readers > 0 THEN ROUND(dm.post_success::numeric / dm.readers::numeric, 4)
    ELSE 0
  END AS writer_share
FROM daily_metrics dm
WHERE dm.city_code = 'WORLD' AND dm.region = 'WORLD'
  AND NOT EXISTS (
    SELECT 1 FROM daily_readers_writers drw 
    WHERE drw.day_bucket = dm.day_bucket 
      AND drw.city_code = dm.city_code 
      AND drw.region = dm.region
  )
ON CONFLICT (day_bucket, city_code, region) DO NOTHING;

-- ============================================================
-- VERIFY: Check alignment after fix
-- ============================================================
SELECT 
  COALESCE(dm.day_bucket, drw.day_bucket) AS day_bucket,
  dm.sessions,
  dm.readers AS dm_readers,
  dm.post_success AS dm_posts,
  drw.readers_today AS drw_readers,
  drw.writers_today AS drw_writers,
  drw.writer_share
FROM daily_metrics dm
FULL OUTER JOIN daily_readers_writers drw 
  ON dm.day_bucket = drw.day_bucket 
  AND dm.city_code = drw.city_code 
  AND dm.region = drw.region
WHERE dm.city_code = 'WORLD' AND dm.region = 'WORLD'
ORDER BY day_bucket DESC
LIMIT 10;

-- ============================================================
-- TEST: Run get_change_over_time_metrics after fix
-- ============================================================
SELECT * FROM public.get_change_over_time_metrics('WORLD', 'WORLD', 7, NULL, NULL);
