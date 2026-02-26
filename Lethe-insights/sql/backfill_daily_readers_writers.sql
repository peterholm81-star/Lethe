-- ============================================================
-- BACKFILL DAILY_READERS_WRITERS FROM DAILY_METRICS
-- ============================================================
-- Run this manually to sync daily_readers_writers with daily_metrics
-- for the last 30 days (or all time if you remove the date filter)
-- ============================================================

-- 1) Preview: show which rows would be inserted
SELECT 
  dm.day_bucket,
  dm.city_code,
  dm.region,
  dm.readers AS readers_today,
  dm.post_success AS writers_today,
  CASE 
    WHEN dm.readers > 0 THEN ROUND(dm.post_success::numeric / dm.readers::numeric, 4)
    ELSE 0
  END AS writer_share,
  CASE WHEN drw.day_bucket IS NULL THEN 'WILL INSERT' ELSE 'EXISTS' END AS status
FROM daily_metrics dm
LEFT JOIN daily_readers_writers drw 
  ON drw.day_bucket = dm.day_bucket 
  AND drw.city_code = dm.city_code 
  AND drw.region = dm.region
WHERE dm.day_bucket >= CURRENT_DATE - 30
ORDER BY dm.day_bucket DESC;

-- 2) Insert missing rows (upsert)
INSERT INTO daily_readers_writers (day_bucket, city_code, region, readers_today, writers_today, writer_share)
SELECT 
  dm.day_bucket,
  dm.city_code,
  dm.region,
  dm.readers AS readers_today,
  dm.post_success AS writers_today,
  CASE 
    WHEN dm.readers > 0 THEN ROUND(dm.post_success::numeric / dm.readers::numeric, 4)
    ELSE 0
  END AS writer_share
FROM daily_metrics dm
WHERE dm.day_bucket >= CURRENT_DATE - 30
ON CONFLICT (day_bucket, city_code, region) 
DO UPDATE SET
  readers_today = EXCLUDED.readers_today,
  writers_today = EXCLUDED.writers_today,
  writer_share = EXCLUDED.writer_share;

-- 3) Verify: show current state
SELECT 
  drw.day_bucket,
  drw.readers_today,
  drw.writers_today,
  drw.writer_share
FROM daily_readers_writers drw
WHERE drw.city_code = 'WORLD' AND drw.region = 'WORLD'
ORDER BY drw.day_bucket DESC
LIMIT 10;
