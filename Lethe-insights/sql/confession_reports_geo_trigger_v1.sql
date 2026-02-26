-- =============================================================================
-- TRIGGER: Auto-populate geo data on confession_reports from confessions
-- =============================================================================
--
-- PURPOSE:
--   Copy geo fields from confessions to confession_reports on INSERT.
--   Source of truth is confessions table (populated by upstream geo-enrichment).
--
-- FIELDS COPIED:
--   - region (e.g. "Europe", "North America")
--   - city_code (e.g. "TRD", "OSL")
--   - country (e.g. "Norway", "Sweden")
--   - country_code (ISO 3166-1 alpha-2, e.g. "NO", "SE")
--
-- =============================================================================

-- =============================================================================
-- STEP 1: Add missing geo columns to confession_reports
-- =============================================================================

-- Add region column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'confession_reports' 
      AND column_name = 'region'
  ) THEN
    ALTER TABLE public.confession_reports ADD COLUMN region text NULL;
    RAISE NOTICE 'Added region column to confession_reports';
  ELSE
    RAISE NOTICE 'region column already exists in confession_reports';
  END IF;
END $$;

-- Add city_code column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'confession_reports' 
      AND column_name = 'city_code'
  ) THEN
    ALTER TABLE public.confession_reports ADD COLUMN city_code text NULL;
    RAISE NOTICE 'Added city_code column to confession_reports';
  ELSE
    RAISE NOTICE 'city_code column already exists in confession_reports';
  END IF;
END $$;

-- Add country column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'confession_reports' 
      AND column_name = 'country'
  ) THEN
    ALTER TABLE public.confession_reports ADD COLUMN country text NULL;
    RAISE NOTICE 'Added country column to confession_reports';
  ELSE
    RAISE NOTICE 'country column already exists in confession_reports';
  END IF;
END $$;

-- Add country_code column if it doesn't exist (ISO 3166-1 alpha-2)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'confession_reports' 
      AND column_name = 'country_code'
  ) THEN
    ALTER TABLE public.confession_reports ADD COLUMN country_code text NULL;
    RAISE NOTICE 'Added country_code column to confession_reports';
  ELSE
    RAISE NOTICE 'country_code column already exists in confession_reports';
  END IF;
END $$;

-- =============================================================================
-- STEP 2: Create the trigger function
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_confession_report_geo_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_region text;
  v_city_code text;
  v_country text;
  v_country_code text;
BEGIN
  -- Only fill geo if any field is missing (NULL, empty, or UNKNOWN)
  IF (NEW.region IS NULL OR TRIM(NEW.region) = '' OR UPPER(TRIM(NEW.region)) = 'UNKNOWN')
     OR (NEW.city_code IS NULL OR TRIM(NEW.city_code) = '' OR UPPER(TRIM(NEW.city_code)) = 'UNKNOWN')
     OR (NEW.country IS NULL OR TRIM(NEW.country) = '' OR UPPER(TRIM(NEW.country)) = 'UNKNOWN')
     OR (NEW.country_code IS NULL OR TRIM(NEW.country_code) = '' OR UPPER(TRIM(NEW.country_code)) = 'UNKNOWN')
  THEN
    -- Look up geo from the confession being reported
    SELECT
      c.region,
      c.city_code,
      c.country,
      c.country_code
    INTO
      v_region,
      v_city_code,
      v_country,
      v_country_code
    FROM public.confessions c
    WHERE c.id = NEW.confession_id
    LIMIT 1;

    -- Set region if missing
    IF NEW.region IS NULL OR TRIM(NEW.region) = '' OR UPPER(TRIM(NEW.region)) = 'UNKNOWN' THEN
      NEW.region := v_region;
    END IF;

    -- Set city_code if missing
    IF NEW.city_code IS NULL OR TRIM(NEW.city_code) = '' OR UPPER(TRIM(NEW.city_code)) = 'UNKNOWN' THEN
      NEW.city_code := v_city_code;
    END IF;

    -- Set country if missing
    IF NEW.country IS NULL OR TRIM(NEW.country) = '' OR UPPER(TRIM(NEW.country)) = 'UNKNOWN' THEN
      NEW.country := v_country;
    END IF;

    -- Set country_code if missing
    IF NEW.country_code IS NULL OR TRIM(NEW.country_code) = '' OR UPPER(TRIM(NEW.country_code)) = 'UNKNOWN' THEN
      NEW.country_code := v_country_code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- STEP 3: Create the trigger
-- =============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_set_confession_report_geo_v1 ON public.confession_reports;

-- Create trigger on INSERT
CREATE TRIGGER trg_set_confession_report_geo_v1
  BEFORE INSERT ON public.confession_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.set_confession_report_geo_v1();

-- =============================================================================
-- STEP 4: Create indexes for better query performance
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_confession_reports_region 
  ON public.confession_reports (region);
CREATE INDEX IF NOT EXISTS idx_confession_reports_city_code 
  ON public.confession_reports (city_code);
CREATE INDEX IF NOT EXISTS idx_confession_reports_country 
  ON public.confession_reports (country);
CREATE INDEX IF NOT EXISTS idx_confession_reports_country_code 
  ON public.confession_reports (country_code);

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- After running this script:
-- 1. Check columns exist:
--    SELECT column_name FROM information_schema.columns 
--    WHERE table_name = 'confession_reports' 
--      AND column_name IN ('region', 'city_code', 'country', 'country_code');
--
-- 2. Check trigger exists:
--    SELECT trigger_name FROM information_schema.triggers 
--    WHERE event_object_table = 'confession_reports';
--
-- 3. Test by inserting a report (geo should be auto-populated from confession)
