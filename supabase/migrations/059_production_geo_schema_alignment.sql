-- =============================================================================
-- Migration 059: Production Geo Schema Alignment
-- =============================================================================
-- Phase B: Add missing geo columns to production schema.
--
-- This migration is SCHEMA ONLY:
--   - Adds columns safely (IF NOT EXISTS)
--   - Adds minimal indexes for future filter/aggregate queries
--   - Does NOT populate any data
--   - Does NOT add enrichment triggers or reverse geocoding
--   - Does NOT modify any RPC logic
--
-- After this migration:
--   - All Insights RPCs will execute their primary path (no exception fallback)
--   - All geo filter dropdowns will return [] instead of errors
--   - All geo aggregate RPCs will return valid empty aggregates
--   - Columns are ready to receive data once enrichment is wired (Phase C+)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- public.confessions — add geo columns
-- ---------------------------------------------------------------------------

ALTER TABLE public.confessions
  ADD COLUMN IF NOT EXISTS region       TEXT,
  ADD COLUMN IF NOT EXISTS country_code TEXT,
  ADD COLUMN IF NOT EXISTS city_code    TEXT;

-- ---------------------------------------------------------------------------
-- public.event_logs — add geo columns
-- city_code already exists (added in an earlier migration); skip it.
-- ---------------------------------------------------------------------------

ALTER TABLE public.event_logs
  ADD COLUMN IF NOT EXISTS region       TEXT,
  ADD COLUMN IF NOT EXISTS country_code TEXT;

-- ---------------------------------------------------------------------------
-- Indexes — minimal set for filter/aggregate query patterns
-- Use IF NOT EXISTS guards so replay is safe.
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS confessions_country_code_idx
  ON public.confessions (country_code)
  WHERE country_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS confessions_region_idx
  ON public.confessions (region)
  WHERE region IS NOT NULL;

CREATE INDEX IF NOT EXISTS confessions_city_code_idx
  ON public.confessions (city_code)
  WHERE city_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS event_logs_country_code_idx
  ON public.event_logs (country_code)
  WHERE country_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS event_logs_region_idx
  ON public.event_logs (region)
  WHERE region IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Comments — document that columns are schema-only placeholders for now
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN public.confessions.region IS
  'ISO region/state code for this confession. NULL until geo enrichment is enabled (Phase C).';
COMMENT ON COLUMN public.confessions.country_code IS
  'ISO 3166-1 alpha-2 country code. NULL until geo enrichment is enabled (Phase C).';
COMMENT ON COLUMN public.confessions.city_code IS
  'Internal city identifier slug. NULL until geo enrichment is enabled (Phase C).';

COMMENT ON COLUMN public.event_logs.region IS
  'ISO region/state code for this event. NULL until geo enrichment is enabled (Phase C).';
COMMENT ON COLUMN public.event_logs.country_code IS
  'ISO 3166-1 alpha-2 country code for this event. NULL until geo enrichment is enabled (Phase C).';
