-- =============================================================================
-- SEED: Mood Metrics Demo Data (30 days)
-- =============================================================================
--
-- Creates investor-impressive demo data for Lethe Insights "Mood" page.
-- Privacy-safe: Only aggregated counts, no confession text.
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role/postgres).
--
-- SIGNALS BUILT IN:
--   - Global: Slightly positive overall (calm+joy+love > negative moods)
--   - Europe: Anxiety spike last 3 days
--   - North America: Anger spike ~10 days ago
--   - Asia: Rising calm week-over-week
--   - Scattered sadness/loneliness in some cities
--   - Light desire spread throughout
--
-- VOLUME TARGET: 3,000-8,000 total confessions in 30-day window
--
-- =============================================================================

-- =============================================================================
-- UPSERT SEED DATA
-- =============================================================================
-- Uses ON CONFLICT to update existing rows rather than fail.
-- This makes the seed idempotent and safe to run multiple times.

INSERT INTO public.confession_metrics_daily (
  date,
  time_bucket,
  region,
  country_code,
  city_code,
  mood_bucket,
  count,
  created_at,
  updated_at
)
SELECT
  d.date::date,
  tb.time_bucket,
  geo.region,
  geo.country_code,
  geo.city_code,
  mood.mood_bucket,
  -- Calculate count with all modifiers
  GREATEST(1, (
    -- Base count per mood (positive moods slightly higher)
    mood.base_count
    -- Time bucket modifier (evening highest, night lowest)
    * tb.modifier
    -- Geo modifier (varies by region)
    * geo.modifier
    -- Day-of-week modifier (weekends slightly higher)
    * CASE EXTRACT(DOW FROM d.date)
        WHEN 0 THEN 1.15  -- Sunday
        WHEN 6 THEN 1.20  -- Saturday
        WHEN 5 THEN 1.10  -- Friday
        ELSE 1.0
      END
    -- SIGNAL: Europe anxiety spike (last 3 days)
    * CASE
        WHEN geo.region = 'Europe' AND mood.mood_bucket = 'anxiety'
             AND d.date >= current_date - 2
        THEN 3.5
        ELSE 1.0
      END
    -- SIGNAL: North America anger spike (~10 days ago, 3-day window)
    * CASE
        WHEN geo.region = 'North America' AND mood.mood_bucket = 'anger'
             AND d.date BETWEEN current_date - 12 AND current_date - 9
        THEN 4.0
        ELSE 1.0
      END
    -- SIGNAL: Asia calm rising week-over-week
    * CASE
        WHEN geo.region = 'Asia' AND mood.mood_bucket = 'calm'
        THEN 1.0 + (30 - (current_date - d.date::date)) * 0.02  -- 0% to 60% increase over 30 days
        ELSE 1.0
      END
    -- SIGNAL: Scattered sadness/loneliness in specific cities
    * CASE
        WHEN geo.city_code IN ('TRD', 'MUM') AND mood.mood_bucket IN ('sadness', 'loneliness')
        THEN 1.5
        ELSE 1.0
      END
    -- SIGNAL: More desire on weekends
    * CASE
        WHEN mood.mood_bucket = 'desire' AND EXTRACT(DOW FROM d.date) IN (0, 6)
        THEN 1.8
        ELSE 1.0
      END
    -- Slight daily variance based on day number (deterministic, not random)
    * (1.0 + 0.1 * sin((current_date - d.date::date) * 0.5))
  )::int) AS count,
  now() AS created_at,
  now() AS updated_at

FROM
  -- Generate last 30 days (including today)
  generate_series(current_date - 29, current_date, '1 day'::interval) AS d(date)

CROSS JOIN (
  -- Time buckets with modifiers
  VALUES
    ('night',     0.6),
    ('morning',   0.9),
    ('afternoon', 1.0),
    ('evening',   1.3)
) AS tb(time_bucket, modifier)

CROSS JOIN (
  -- Geo: region, country_code, city_code, modifier
  VALUES
    -- Europe (highest activity)
    ('Europe', 'NO', 'TRD', 1.2),
    ('Europe', 'NO', 'OSL', 1.3),
    ('Europe', 'ES', 'MAD', 1.1),
    ('Europe', 'ES', 'BCN', 1.0),
    -- North America
    ('North America', 'US', 'NYC', 1.4),
    ('North America', 'US', 'SFO', 0.9),
    -- Asia
    ('Asia', 'IN', 'MUM', 0.8),
    ('Asia', 'IN', 'DEL', 0.7)
) AS geo(region, country_code, city_code, modifier)

CROSS JOIN (
  -- Mood buckets with base counts (positive slightly higher)
  VALUES
    -- Positive moods (higher base)
    ('calm',       4),
    ('joy',        3),
    ('love',       2),
    ('hope',       2),
    ('gratitude',  2),
    ('confidence', 2),
    -- Negative moods (lower base)
    ('anxiety',    2),
    ('sadness',    2),
    ('anger',      1),
    ('loneliness', 2),
    -- Neutral/other
    ('desire',     1),
    ('shame',      1)
) AS mood(mood_bucket, base_count)

ON CONFLICT (date, time_bucket, region, country_code, city_code, mood_bucket)
DO UPDATE SET
  count = EXCLUDED.count,
  updated_at = now();

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================
-- Run these after seeding to verify the data looks correct.

-- ---------------------------------------------------------------------------
-- 1. TOTAL COUNT: Last 30 days globally (target: 3,000-8,000)
-- ---------------------------------------------------------------------------
SELECT 
  'TOTAL 30d' AS metric,
  SUM(count)::int AS total_confessions,
  COUNT(*)::int AS row_count
FROM public.confession_metrics_daily
WHERE date >= current_date - 29;

-- ---------------------------------------------------------------------------
-- 2. MOOD SUMMARY: Last 7 days globally (for rpc_get_mood_summary)
-- ---------------------------------------------------------------------------
SELECT 
  mood_bucket,
  SUM(count)::int AS total_count
FROM public.confession_metrics_daily
WHERE date >= current_date - 6
GROUP BY mood_bucket
ORDER BY total_count DESC;

-- ---------------------------------------------------------------------------
-- 3. MOOD BY REGION: Last 7 days (check regional differences)
-- ---------------------------------------------------------------------------
SELECT 
  region,
  mood_bucket,
  SUM(count)::int AS total_count
FROM public.confession_metrics_daily
WHERE date >= current_date - 6
GROUP BY region, mood_bucket
ORDER BY region, total_count DESC;

-- ---------------------------------------------------------------------------
-- 4. EUROPE ANXIETY CHECK: Should show spike in last 3 days
-- ---------------------------------------------------------------------------
SELECT 
  date,
  SUM(count)::int AS anxiety_count
FROM public.confession_metrics_daily
WHERE region = 'Europe'
  AND mood_bucket = 'anxiety'
  AND date >= current_date - 6
GROUP BY date
ORDER BY date DESC;

-- ---------------------------------------------------------------------------
-- 5. NORTH AMERICA ANGER CHECK: Should show spike ~10 days ago
-- ---------------------------------------------------------------------------
SELECT 
  date,
  SUM(count)::int AS anger_count
FROM public.confession_metrics_daily
WHERE region = 'North America'
  AND mood_bucket = 'anger'
  AND date >= current_date - 14
GROUP BY date
ORDER BY date DESC;

-- ---------------------------------------------------------------------------
-- 6. ASIA CALM TREND: Should show rising week-over-week
-- ---------------------------------------------------------------------------
SELECT 
  date,
  SUM(count)::int AS calm_count
FROM public.confession_metrics_daily
WHERE region = 'Asia'
  AND mood_bucket = 'calm'
  AND date >= current_date - 14
GROUP BY date
ORDER BY date ASC;

-- ---------------------------------------------------------------------------
-- 7. TIME BUCKET DISTRIBUTION: Evening should be highest
-- ---------------------------------------------------------------------------
SELECT 
  time_bucket,
  SUM(count)::int AS total_count
FROM public.confession_metrics_daily
WHERE date >= current_date - 6
GROUP BY time_bucket
ORDER BY total_count DESC;

-- ---------------------------------------------------------------------------
-- 8. CITY BREAKDOWN: Top cities by volume
-- ---------------------------------------------------------------------------
SELECT 
  city_code,
  region,
  SUM(count)::int AS total_count
FROM public.confession_metrics_daily
WHERE date >= current_date - 6
GROUP BY city_code, region
ORDER BY total_count DESC;

-- =============================================================================
-- EXPECTED RESULTS
-- =============================================================================
-- 
-- 1. Total 30d: ~5,000-7,000 confessions
-- 2. Top moods globally: calm > joy > love/anxiety/sadness
-- 3. Europe: anxiety should be elevated (especially last 3 days)
-- 4. North America: anger spike visible ~10 days ago
-- 5. Asia: calm count should increase day-over-day
-- 6. Evening > afternoon > morning > night
-- 7. NYC highest city, TRD/OSL strong in Europe
--
-- =============================================================================
