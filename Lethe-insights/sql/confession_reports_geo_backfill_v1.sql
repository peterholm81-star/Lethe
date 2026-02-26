-- =============================================================================
-- BACKFILL: Populate geo data for existing confession_reports from confessions
-- =============================================================================
--
-- PURPOSE:
--   Update existing confession_reports records that have NULL/empty geo data
--   by copying from the linked confession.
--
-- PREREQUISITE:
--   1. Run confessions_country_fields_v1.sql first (adds country/country_code to confessions)
--   2. Run confession_reports_geo_trigger_v1.sql (adds columns to confession_reports)
--
-- SAFETY:
--   - Only updates records where geo is NULL/empty/UNKNOWN
--   - Does not overwrite existing valid geo data
--   - Idempotent: safe to run multiple times
--
-- =============================================================================

-- =============================================================================
-- STEP 1: Preview what will be updated (dry run)
-- =============================================================================
-- Uncomment to see how many records would be affected:
/*
SELECT 
  COUNT(*) AS total_reports,
  COUNT(*) FILTER (WHERE cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN') AS missing_region,
  COUNT(*) FILTER (WHERE cr.city_code IS NULL OR TRIM(cr.city_code) = '' OR UPPER(TRIM(cr.city_code)) = 'UNKNOWN') AS missing_city,
  COUNT(*) FILTER (WHERE cr.country IS NULL OR TRIM(cr.country) = '' OR UPPER(TRIM(cr.country)) = 'UNKNOWN') AS missing_country,
  COUNT(*) FILTER (WHERE cr.country_code IS NULL OR TRIM(cr.country_code) = '' OR UPPER(TRIM(cr.country_code)) = 'UNKNOWN') AS missing_country_code
FROM public.confession_reports cr;
*/

-- =============================================================================
-- STEP 2: Backfill region column
-- =============================================================================
UPDATE public.confession_reports cr
SET region = c.region
FROM public.confessions c
WHERE c.id = cr.confession_id
  AND (cr.region IS NULL OR TRIM(cr.region) = '' OR UPPER(TRIM(cr.region)) = 'UNKNOWN')
  AND c.region IS NOT NULL 
  AND TRIM(c.region) != ''
  AND UPPER(TRIM(c.region)) != 'UNKNOWN';

-- =============================================================================
-- STEP 3: Backfill city_code column
-- =============================================================================
UPDATE public.confession_reports cr
SET city_code = c.city_code
FROM public.confessions c
WHERE c.id = cr.confession_id
  AND (cr.city_code IS NULL OR TRIM(cr.city_code) = '' OR UPPER(TRIM(cr.city_code)) = 'UNKNOWN')
  AND c.city_code IS NOT NULL 
  AND TRIM(c.city_code) != ''
  AND UPPER(TRIM(c.city_code)) != 'UNKNOWN';

-- =============================================================================
-- STEP 4: Backfill country column
-- =============================================================================
UPDATE public.confession_reports cr
SET country = c.country
FROM public.confessions c
WHERE c.id = cr.confession_id
  AND (cr.country IS NULL OR TRIM(cr.country) = '' OR UPPER(TRIM(cr.country)) = 'UNKNOWN')
  AND c.country IS NOT NULL 
  AND TRIM(c.country) != ''
  AND UPPER(TRIM(c.country)) != 'UNKNOWN';

-- =============================================================================
-- STEP 5: Backfill country_code column
-- =============================================================================
UPDATE public.confession_reports cr
SET country_code = c.country_code
FROM public.confessions c
WHERE c.id = cr.confession_id
  AND (cr.country_code IS NULL OR TRIM(cr.country_code) = '' OR UPPER(TRIM(cr.country_code)) = 'UNKNOWN')
  AND c.country_code IS NOT NULL 
  AND TRIM(c.country_code) != ''
  AND UPPER(TRIM(c.country_code)) != 'UNKNOWN';

-- =============================================================================
-- STEP 6: Verify results
-- =============================================================================
SELECT 
  COUNT(*) AS total_reports,
  COUNT(*) FILTER (WHERE region IS NOT NULL AND TRIM(region) != '' AND UPPER(TRIM(region)) != 'UNKNOWN') AS has_region,
  COUNT(*) FILTER (WHERE city_code IS NOT NULL AND TRIM(city_code) != '' AND UPPER(TRIM(city_code)) != 'UNKNOWN') AS has_city,
  COUNT(*) FILTER (WHERE country IS NOT NULL AND TRIM(country) != '' AND UPPER(TRIM(country)) != 'UNKNOWN') AS has_country,
  COUNT(*) FILTER (WHERE country_code IS NOT NULL AND TRIM(country_code) != '' AND UPPER(TRIM(country_code)) != 'UNKNOWN') AS has_country_code,
  ROUND(
    COUNT(*) FILTER (WHERE region IS NOT NULL AND TRIM(region) != '' AND UPPER(TRIM(region)) != 'UNKNOWN')::numeric 
    / NULLIF(COUNT(*), 0) * 100, 1
  ) AS region_pct,
  ROUND(
    COUNT(*) FILTER (WHERE city_code IS NOT NULL AND TRIM(city_code) != '' AND UPPER(TRIM(city_code)) != 'UNKNOWN')::numeric 
    / NULLIF(COUNT(*), 0) * 100, 1
  ) AS city_pct,
  ROUND(
    COUNT(*) FILTER (WHERE country IS NOT NULL AND TRIM(country) != '' AND UPPER(TRIM(country)) != 'UNKNOWN')::numeric 
    / NULLIF(COUNT(*), 0) * 100, 1
  ) AS country_pct,
  ROUND(
    COUNT(*) FILTER (WHERE country_code IS NOT NULL AND TRIM(country_code) != '' AND UPPER(TRIM(country_code)) != 'UNKNOWN')::numeric 
    / NULLIF(COUNT(*), 0) * 100, 1
  ) AS country_code_pct
FROM public.confession_reports;

-- =============================================================================
-- NOTE: If backfill shows 0%, check confessions geo data
-- =============================================================================
/*
SELECT 
  COUNT(*) AS total_confessions,
  COUNT(*) FILTER (WHERE region IS NOT NULL AND TRIM(region) != '') AS has_region,
  COUNT(*) FILTER (WHERE city_code IS NOT NULL AND TRIM(city_code) != '') AS has_city,
  COUNT(*) FILTER (WHERE country IS NOT NULL AND TRIM(country) != '') AS has_country,
  COUNT(*) FILTER (WHERE country_code IS NOT NULL AND TRIM(country_code) != '') AS has_country_code
FROM public.confessions;
*/
