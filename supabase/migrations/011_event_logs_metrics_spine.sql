-- ============================================================================
-- Migration: 011_event_logs_metrics_spine
-- Purpose: Expand event_logs for Metrics Spine v1
-- ============================================================================
-- New columns for richer analytics dimensions:
--   dow_bucket    = day of week (0=Sunday, 6=Saturday)
--   country_code  = ISO country code (anonymized geo)
--   region        = region/state code
--   meta          = JSON for extensible metadata
-- ============================================================================

-- Add dow_bucket (day of week: 0-6)
ALTER TABLE public.event_logs
ADD COLUMN IF NOT EXISTS dow_bucket INT CHECK (dow_bucket >= 0 AND dow_bucket <= 6);

COMMENT ON COLUMN public.event_logs.dow_bucket IS 'Day of week: 0=Sunday, 6=Saturday';

-- Add country_code (ISO 2-letter)
ALTER TABLE public.event_logs
ADD COLUMN IF NOT EXISTS country_code TEXT;

COMMENT ON COLUMN public.event_logs.country_code IS 'ISO 3166-1 alpha-2 country code (no user identity)';

-- Add region (state/province)
ALTER TABLE public.event_logs
ADD COLUMN IF NOT EXISTS region TEXT;

COMMENT ON COLUMN public.event_logs.region IS 'Region/state code within country (no user identity)';

-- Add meta (JSONB for extensibility)
ALTER TABLE public.event_logs
ADD COLUMN IF NOT EXISTS meta JSONB;

COMMENT ON COLUMN public.event_logs.meta IS 'Extensible metadata as JSON (no PII)';

-- ============================================================================
-- INDEXES for Metrics Spine queries
-- ============================================================================

-- Composite index for aggregation queries by day/region/city/event
CREATE INDEX IF NOT EXISTS idx_event_logs_day_region_city_event 
ON public.event_logs (day_bucket, region, city_code, event_name);

-- Index for session-based queries
CREATE INDEX IF NOT EXISTS idx_event_logs_session_day 
ON public.event_logs (session_hash, day_bucket);

-- Index for day-of-week analysis
CREATE INDEX IF NOT EXISTS idx_event_logs_dow 
ON public.event_logs (dow_bucket, day_bucket);

-- Index for country-level queries
CREATE INDEX IF NOT EXISTS idx_event_logs_country_day 
ON public.event_logs (country_code, day_bucket);

-- ============================================================================
-- VERIFY
-- ============================================================================
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'event_logs'
ORDER BY ordinal_position;
