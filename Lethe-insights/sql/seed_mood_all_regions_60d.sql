-- =============================================================================
-- SEED: Mood Metrics ALL REGIONS (60 days)
-- =============================================================================
--
-- Creates complete demo data for ALL regions so AI Observer never shows "No data".
-- Covers: Europe, North America, Asia, South America, Africa, Oceania, Middle East
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role/postgres).
--
-- CHARACTERISTICS BY REGION:
--   - Europe:       High volume, slight anxiety (urban stress)
--   - North America: Highest volume, balanced but trending positive
--   - Asia:         Medium-high, calm and hopeful
--   - South America: Medium, positive vibes (joy, gratitude)
--   - Africa:       Lower volume, hopeful and resilient
--   - Oceania:      Low volume, very calm and positive
--   - Middle East:  Medium-low, mix of hope and anxiety
--
-- VOLUME TARGETS (60 days):
--   - Total: ~15,000-25,000 confessions
--   - Realistic regional distribution
--
-- =============================================================================

-- =============================================================================
-- CLEAR EXISTING DATA (optional - comment out if you want to keep old data)
-- =============================================================================
-- DELETE FROM public.confession_metrics_daily WHERE date >= current_date - 89;

-- =============================================================================
-- UPSERT SEED DATA FOR ALL REGIONS
-- =============================================================================

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
  -- Calculate count with all modifiers (deterministic, no random)
  GREATEST(1, (
    -- Base count per mood
    mood.base_count
    -- Region volume modifier
    * geo.volume_mod
    -- Time bucket modifier (evening highest, night lowest)
    * tb.modifier
    -- City-specific modifier
    * geo.city_mod
    -- Day-of-week modifier (weekends slightly higher globally)
    * CASE EXTRACT(DOW FROM d.date)
        WHEN 0 THEN 1.12  -- Sunday
        WHEN 6 THEN 1.18  -- Saturday
        WHEN 5 THEN 1.08  -- Friday
        ELSE 1.0
      END
    -- Regional mood biases
    * CASE
        -- Europe: slight anxiety elevation
        WHEN geo.region = 'Europe' AND mood.mood_bucket = 'anxiety'
        THEN 1.25
        -- North America: slight anger
        WHEN geo.region = 'North America' AND mood.mood_bucket = 'anger'
        THEN 1.15
        -- Asia: elevated calm
        WHEN geo.region = 'Asia' AND mood.mood_bucket = 'calm'
        THEN 1.35
        -- South America: elevated joy and gratitude
        WHEN geo.region = 'South America' AND mood.mood_bucket IN ('joy', 'gratitude')
        THEN 1.40
        -- Africa: elevated hope
        WHEN geo.region = 'Africa' AND mood.mood_bucket = 'hope'
        THEN 1.45
        -- Oceania: elevated calm and love
        WHEN geo.region = 'Oceania' AND mood.mood_bucket IN ('calm', 'love')
        THEN 1.50
        -- Middle East: mix of hope and anxiety
        WHEN geo.region = 'Middle East' AND mood.mood_bucket IN ('hope', 'anxiety')
        THEN 1.20
        ELSE 1.0
      END
    -- Slight weekly cycle for variety (deterministic based on day offset)
    * (1.0 + 0.08 * sin((current_date - d.date::date) * 0.45))
    -- Monthly trend: slight positive drift (things improving)
    * (1.0 + 
        CASE WHEN mood.is_positive THEN 0.003 ELSE -0.002 END 
        * (60 - (current_date - d.date::date))
      )
  )::int) AS count,
  now() AS created_at,
  now() AS updated_at

FROM
  -- Generate last 60 days (including today) + 30 days for "previous period" comparison
  generate_series(current_date - 89, current_date, '1 day'::interval) AS d(date)

CROSS JOIN (
  -- Time buckets with activity modifiers
  VALUES
    ('night',     0.55),
    ('morning',   0.85),
    ('afternoon', 1.0),
    ('evening',   1.25)
) AS tb(time_bucket, modifier)

CROSS JOIN (
  -- All 7 regions with representative cities
  -- (region, country_code, city_code, volume_mod, city_mod)
  VALUES
    -- EUROPE (high volume) - 4 cities
    ('Europe', 'GB', 'LON', 1.8, 1.3),
    ('Europe', 'DE', 'BER', 1.8, 1.1),
    ('Europe', 'FR', 'PAR', 1.8, 1.2),
    ('Europe', 'NO', 'OSL', 1.8, 0.9),
    
    -- NORTH AMERICA (highest volume) - 4 cities
    ('North America', 'US', 'NYC', 2.0, 1.4),
    ('North America', 'US', 'LAX', 2.0, 1.2),
    ('North America', 'CA', 'TOR', 2.0, 1.0),
    ('North America', 'MX', 'MEX', 2.0, 0.8),
    
    -- ASIA (medium-high) - 4 cities
    ('Asia', 'JP', 'TYO', 1.5, 1.2),
    ('Asia', 'IN', 'MUM', 1.5, 1.1),
    ('Asia', 'SG', 'SIN', 1.5, 0.9),
    ('Asia', 'KR', 'SEL', 1.5, 1.0),
    
    -- SOUTH AMERICA (medium) - 3 cities
    ('South America', 'BR', 'SAO', 1.2, 1.2),
    ('South America', 'AR', 'BUE', 1.2, 1.0),
    ('South America', 'CO', 'BOG', 1.2, 0.9),
    
    -- AFRICA (lower volume) - 3 cities
    ('Africa', 'ZA', 'JNB', 0.8, 1.1),
    ('Africa', 'NG', 'LOS', 0.8, 1.0),
    ('Africa', 'KE', 'NBO', 0.8, 0.9),
    
    -- OCEANIA (low volume) - 2 cities
    ('Oceania', 'AU', 'SYD', 0.6, 1.2),
    ('Oceania', 'NZ', 'AKL', 0.6, 0.9),
    
    -- MIDDLE EAST (medium-low) - 3 cities
    ('Middle East', 'AE', 'DXB', 0.9, 1.2),
    ('Middle East', 'IL', 'TLV', 0.9, 1.0),
    ('Middle East', 'SA', 'RUH', 0.9, 0.8)
    
) AS geo(region, country_code, city_code, volume_mod, city_mod)

CROSS JOIN (
  -- Mood buckets with base counts and positive/negative flag
  -- (mood_bucket, base_count, is_positive)
  VALUES
    -- Positive moods (higher base)
    ('calm',       4, true),
    ('joy',        3, true),
    ('love',       3, true),
    ('hope',       3, true),
    ('gratitude',  2, true),
    ('confidence', 2, true),
    -- Negative moods (lower base)
    ('anxiety',    2, false),
    ('sadness',    2, false),
    ('anger',      1, false),
    ('loneliness', 2, false),
    ('shame',      1, false),
    -- Neutral
    ('desire',     1, false)
) AS mood(mood_bucket, base_count, is_positive)

ON CONFLICT (date, time_bucket, region, country_code, city_code, mood_bucket)
DO UPDATE SET
  count = EXCLUDED.count,
  updated_at = now();

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. ALL REGIONS CHECK: Each region should have data
-- ---------------------------------------------------------------------------
SELECT 
  '1. REGIONS' AS check_name,
  region,
  SUM(count)::int AS total_confessions,
  COUNT(DISTINCT date)::int AS days_with_data
FROM public.confession_metrics_daily
WHERE date >= current_date - 59
GROUP BY region
ORDER BY total_confessions DESC;

-- ---------------------------------------------------------------------------
-- 2. TOTAL VOLUME: Should be 15,000-25,000 for 60 days
-- ---------------------------------------------------------------------------
SELECT 
  '2. TOTAL 60d' AS check_name,
  SUM(count)::int AS total_confessions,
  COUNT(DISTINCT region)::int AS regions_count,
  MIN(date) AS oldest_date,
  MAX(date) AS newest_date
FROM public.confession_metrics_daily
WHERE date >= current_date - 59;

-- ---------------------------------------------------------------------------
-- 3. BALANCE BY REGION: All should have positive balance (0.05-0.25)
-- ---------------------------------------------------------------------------
WITH mood_totals AS (
  SELECT 
    region,
    SUM(CASE WHEN mood_bucket IN ('joy', 'love', 'calm', 'hope', 'gratitude', 'confidence') 
        THEN count ELSE 0 END) AS positive,
    SUM(CASE WHEN mood_bucket IN ('anxiety', 'sadness', 'anger', 'loneliness', 'shame') 
        THEN count ELSE 0 END) AS negative,
    SUM(count) AS total
  FROM public.confession_metrics_daily
  WHERE date >= current_date - 6
  GROUP BY region
)
SELECT 
  '3. BALANCE 7d' AS check_name,
  region,
  total AS confessions,
  ROUND((positive - negative)::numeric / NULLIF(total, 0), 3) AS balance_score,
  ROUND(positive::numeric / NULLIF(total, 0) * 100, 1) AS positive_pct,
  ROUND(negative::numeric / NULLIF(total, 0) * 100, 1) AS negative_pct
FROM mood_totals
ORDER BY balance_score DESC;

-- ---------------------------------------------------------------------------
-- 4. RPC TEST: Verify the actual RPC returns all regions
-- ---------------------------------------------------------------------------
SELECT 
  '4. RPC OUTPUT' AS check_name,
  region,
  balance_score,
  delta_balance_score,
  positive_share,
  negative_share,
  total_confessions
FROM public.rpc_get_mood_pulse_by_region(
  current_date - 6,
  current_date
)
ORDER BY total_confessions DESC;

-- =============================================================================
-- EXPECTED RESULTS
-- =============================================================================
-- 
-- 1. ALL 7 regions should appear:
--    Europe, North America, Asia, South America, Africa, Oceania, Middle East
--
-- 2. Volume ranking (approximate):
--    North America > Europe > Asia > South America > Middle East > Africa > Oceania
--
-- 3. Balance scores should all be positive (0.05 - 0.30 range)
--    Oceania highest (very calm)
--    Europe/Middle East lowest (more anxiety)
--
-- 4. No "No data" messages in AI Observer!
--
-- =============================================================================
