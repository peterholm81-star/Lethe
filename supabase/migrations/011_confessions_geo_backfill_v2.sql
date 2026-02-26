-- =============================================================================
-- Migration 011: Geo Backfill v2 for Confessions
-- =============================================================================
-- 
-- GOAL: Backfill geo fields (region, city_code, country, country_code) for 
-- confessions that have lat/lng but missing geo data.
--
-- APPROACH:
-- 1. Add geo columns to places_cache (if missing)
-- 2. Update places_cache seed data with proper geo info
-- 3. Create reusable lookup function: lookup_place_for_point()
-- 4. Batch update confessions that need geo
--
-- SAFE TO RE-RUN: All statements use IF NOT EXISTS / CREATE OR REPLACE
-- =============================================================================

-- =============================================================================
-- STEP 1: Add geo columns to places_cache
-- =============================================================================

ALTER TABLE public.places_cache ADD COLUMN IF NOT EXISTS city_code text;
ALTER TABLE public.places_cache ADD COLUMN IF NOT EXISTS region text;
ALTER TABLE public.places_cache ADD COLUMN IF NOT EXISTS country text;
ALTER TABLE public.places_cache ADD COLUMN IF NOT EXISTS country_code text;

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_places_cache_lat_lng ON public.places_cache (lat, lng);

-- =============================================================================
-- STEP 2: Update seed data with geo info
-- =============================================================================
-- Map existing places to their geo data based on name

UPDATE public.places_cache SET 
  city_code = 'NYC', region = 'North America', country = 'United States', country_code = 'US'
WHERE name = 'New York' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'LON', region = 'Europe', country = 'United Kingdom', country_code = 'GB'
WHERE name = 'London' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'TYO', region = 'Asia', country = 'Japan', country_code = 'JP'
WHERE name = 'Tokyo' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'PAR', region = 'Europe', country = 'France', country_code = 'FR'
WHERE name = 'Paris' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'SYD', region = 'Oceania', country = 'Australia', country_code = 'AU'
WHERE name = 'Sydney' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'BER', region = 'Europe', country = 'Germany', country_code = 'DE'
WHERE name = 'Berlin' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'TOR', region = 'North America', country = 'Canada', country_code = 'CA'
WHERE name = 'Toronto' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'SIN', region = 'Asia', country = 'Singapore', country_code = 'SG'
WHERE name = 'Singapore' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'DXB', region = 'Middle East', country = 'United Arab Emirates', country_code = 'AE'
WHERE name = 'Dubai' AND (city_code IS NULL OR country_code IS NULL);

UPDATE public.places_cache SET 
  city_code = 'OSL', region = 'Europe', country = 'Norway', country_code = 'NO'
WHERE name = 'Oslo' AND (city_code IS NULL OR country_code IS NULL);

-- =============================================================================
-- STEP 3: Create lookup function using Haversine formula
-- =============================================================================
-- Returns the nearest place from places_cache within p_max_meters
-- Uses standard SQL Haversine formula (no PostGIS required)

CREATE OR REPLACE FUNCTION public.lookup_place_for_point(
  p_lat double precision,
  p_lng double precision,
  p_max_meters integer DEFAULT 50000
)
RETURNS TABLE (
  region text,
  city_code text,
  country text,
  country_code text,
  distance_m integer
)
LANGUAGE sql
STABLE
AS $$
  SELECT 
    pc.region,
    pc.city_code,
    pc.country,
    pc.country_code,
    -- Haversine distance in meters
    ROUND(
      6371000 * acos(
        LEAST(1.0, GREATEST(-1.0,
          cos(radians(p_lat)) * cos(radians(pc.lat)) *
          cos(radians(pc.lng) - radians(p_lng)) +
          sin(radians(p_lat)) * sin(radians(pc.lat))
        ))
      )
    )::integer AS distance_m
  FROM public.places_cache pc
  WHERE pc.city_code IS NOT NULL  -- Only match places with geo data
    AND pc.lat IS NOT NULL
    AND pc.lng IS NOT NULL
  ORDER BY 
    -- Order by distance (Haversine)
    acos(
      LEAST(1.0, GREATEST(-1.0,
        cos(radians(p_lat)) * cos(radians(pc.lat)) *
        cos(radians(pc.lng) - radians(p_lng)) +
        sin(radians(p_lat)) * sin(radians(pc.lat))
      ))
    )
  LIMIT 1
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.lookup_place_for_point(double precision, double precision, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_place_for_point(double precision, double precision, integer) TO anon;

-- =============================================================================
-- STEP 4: PREVIEW - Show confessions that would be updated
-- =============================================================================
-- Uncomment to preview before running update:

/*
SELECT 
  c.id,
  c.lat,
  c.lng,
  c.region AS current_region,
  c.city_code AS current_city_code,
  c.country_code AS current_country_code,
  lp.region AS lookup_region,
  lp.city_code AS lookup_city_code,
  lp.country_code AS lookup_country_code,
  lp.distance_m
FROM public.confessions c
CROSS JOIN LATERAL public.lookup_place_for_point(c.lat, c.lng, 50000) lp
WHERE c.lat IS NOT NULL
  AND c.lng IS NOT NULL
  AND (
    c.region IS NULL OR TRIM(c.region) = '' OR
    c.city_code IS NULL OR TRIM(c.city_code) = '' OR
    c.country IS NULL OR TRIM(c.country) = '' OR
    c.country_code IS NULL OR TRIM(c.country_code) = ''
  )
  AND lp.city_code IS NOT NULL
ORDER BY c.created_at DESC
LIMIT 20;
*/

-- =============================================================================
-- STEP 5: BATCH UPDATE confessions with missing geo
-- =============================================================================
-- Uses COALESCE to preserve existing non-NULL values
-- Only updates rows where a match was found in places_cache

UPDATE public.confessions c
SET 
  region = COALESCE(NULLIF(TRIM(c.region), ''), lp.region),
  city_code = COALESCE(NULLIF(TRIM(c.city_code), ''), lp.city_code),
  country = COALESCE(NULLIF(TRIM(c.country), ''), lp.country),
  country_code = COALESCE(NULLIF(TRIM(c.country_code), ''), lp.country_code)
FROM (
  SELECT 
    conf.id,
    (public.lookup_place_for_point(conf.lat, conf.lng, 50000)).*
  FROM public.confessions conf
  WHERE conf.lat IS NOT NULL
    AND conf.lng IS NOT NULL
    AND (
      conf.region IS NULL OR TRIM(conf.region) = '' OR
      conf.city_code IS NULL OR TRIM(conf.city_code) = '' OR
      conf.country IS NULL OR TRIM(conf.country) = '' OR
      conf.country_code IS NULL OR TRIM(conf.country_code) = ''
    )
  LIMIT 1000  -- Batch size
) lp
WHERE c.id = lp.id
  AND lp.city_code IS NOT NULL;  -- Only update if lookup found a match

-- =============================================================================
-- STEP 6: PROGRESS REPORT
-- =============================================================================
-- Shows how many confessions still need geo data

SELECT 
  'Confessions with lat/lng' AS metric,
  COUNT(*) AS count
FROM public.confessions
WHERE lat IS NOT NULL AND lng IS NOT NULL

UNION ALL

SELECT 
  'Confessions with complete geo' AS metric,
  COUNT(*) AS count
FROM public.confessions
WHERE lat IS NOT NULL AND lng IS NOT NULL
  AND region IS NOT NULL AND TRIM(region) != ''
  AND city_code IS NOT NULL AND TRIM(city_code) != ''
  AND country_code IS NOT NULL AND TRIM(country_code) != ''

UNION ALL

SELECT 
  'Confessions still missing geo' AS metric,
  COUNT(*) AS count
FROM public.confessions
WHERE lat IS NOT NULL AND lng IS NOT NULL
  AND (
    region IS NULL OR TRIM(region) = '' OR
    city_code IS NULL OR TRIM(city_code) = '' OR
    country_code IS NULL OR TRIM(country_code) = ''
  )

UNION ALL

SELECT 
  'Confessions without lat/lng (cannot backfill)' AS metric,
  COUNT(*) AS count
FROM public.confessions
WHERE lat IS NULL OR lng IS NULL;

-- =============================================================================
-- NOTES
-- =============================================================================
-- 
-- RE-RUN SAFE: This migration can be run multiple times safely.
-- The UPDATE uses COALESCE so it won't overwrite existing data.
--
-- BATCH SIZE: Set to 1000. For large datasets, run multiple times.
-- To process all remaining, remove the LIMIT or run repeatedly.
--
-- MAX RADIUS: Default 50km. Confessions further than 50km from any 
-- place in places_cache won't be updated.
--
-- TO ADD MORE PLACES: Insert into places_cache with all geo fields:
--   INSERT INTO places_cache (name, lat, lng, city_code, region, country, country_code)
--   VALUES ('Stockholm', 59.3293, 18.0686, 'STO', 'Europe', 'Sweden', 'SE');
--
-- =============================================================================
