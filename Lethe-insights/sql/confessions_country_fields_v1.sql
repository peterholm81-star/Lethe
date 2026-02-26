-- =============================================================================
-- ADD COUNTRY FIELDS TO CONFESSIONS TABLE
-- =============================================================================
--
-- PURPOSE:
--   Add country and country_code columns to confessions table.
--   These will be populated by upstream geo-enrichment (e.g. from IP or city lookup).
--
-- FIELD DEFINITIONS:
--   - country: Full country name (e.g. "Norway", "Sweden", "United Kingdom")
--   - country_code: ISO 3166-1 alpha-2 code (e.g. "NO", "SE", "GB")
--
-- =============================================================================

-- Add country column (full name)
ALTER TABLE public.confessions 
  ADD COLUMN IF NOT EXISTS country text;

-- Add country_code column (ISO 3166-1 alpha-2)
ALTER TABLE public.confessions 
  ADD COLUMN IF NOT EXISTS country_code text;

-- Create indexes for filtering/grouping
CREATE INDEX IF NOT EXISTS idx_confessions_country 
  ON public.confessions (country);

CREATE INDEX IF NOT EXISTS idx_confessions_country_code 
  ON public.confessions (country_code);

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Check columns exist:
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_name = 'confessions' AND column_name IN ('country', 'country_code');
