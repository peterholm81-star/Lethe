-- =============================================================================
-- Migration 045a: Promote internal helper functions into the production chain
--
-- WHY THIS MIGRATION EXISTS
-- -------------------------
-- Two internal helper functions were created only in supabase/dev/large_dev_seed.sql
-- and were therefore absent from the production migration chain:
--
--   public._lethe_event_filtered(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT)
--   public._lethe_confession_filtered(DATE, DATE, TEXT, TEXT, TEXT)
--
-- Migration 046 (046_revoke_internal_helper_anon_access.sql) executes REVOKE
-- statements against both functions. On a fresh database that has never had the
-- dev seed applied, those functions do not exist and migration 046 fails with:
--
--   ERROR: function public._lethe_event_filtered(...) does not exist (SQLSTATE 42883)
--
-- This migration creates both functions as proper production-safe definitions so
-- migration 046's REVOKE succeeds on every fresh install.
--
-- FILENAME ORDERING
-- -----------------
-- This file is intentionally named "045a_..." so that it sorts between
-- "045_harden_get_reports_spike_explain_v1.sql" and
-- "046_revoke_internal_helper_anon_access.sql" in alphabetical filename order.
-- (ASCII '_' = 95 < 'a' = 97, so 045_ < 045a < 046_.)
-- Supabase CLI applies migrations in alphabetical filename order, which means:
--   ...045_ → 045a (creates helpers) → 046 (REVOKEs helpers) → 047...
--
-- PRODUCTION SCHEMA COMPATIBILITY
-- --------------------------------
-- The dev seed enriches both tables with optional geo columns:
--   event_logs:  region, country_code   (not present in base production schema)
--   confessions: region, country_code, city_code, emotion_bucket (not in base production)
--
-- The production base schema (migrations 001–018) does not include those columns.
-- Both functions are implemented in LANGUAGE plpgsql using dynamic SQL with
-- information_schema.columns checks, exactly matching the pattern established by
-- migrations 027 and 028. This allows them to:
--   - Apply successfully on a fresh production schema (no geo columns)
--   - Apply successfully on a dev schema (geo columns present from seed)
--   - Filter correctly on whatever columns are available at runtime
--
-- SECURITY NOTE
-- -------------
-- These are internal helper functions — they have no frontend callers and must
-- never be directly callable via the Supabase REST API. Migration 046 immediately
-- revokes all execute grants from PUBLIC, anon, and authenticated after this
-- migration creates them. Until migration 046 runs, these functions carry the
-- default PostgreSQL PUBLIC execute grant; that is acceptable because both
-- migrations are applied in the same transaction-per-migration sequence.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- _lethe_event_filtered
-- Purpose: filter event_logs rows by time range + optional geo/mode dimensions.
--          Used as an internal building block by analytics aggregate RPCs.
-- Returns: SETOF public.event_logs (full row, with whatever columns exist)
-- Signature must match exactly what migration 046 REVOKEs from:
--   REVOKE ... ON FUNCTION public._lethe_event_filtered(TIMESTAMPTZ,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT) ...
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._lethe_event_filtered(
  p_start_ts     TIMESTAMPTZ,
  p_end_ts       TIMESTAMPTZ,
  p_region       TEXT    DEFAULT NULL,
  p_country_code TEXT    DEFAULT NULL,
  p_city_code    TEXT    DEFAULT NULL,
  p_mode         TEXT    DEFAULT NULL
)
RETURNS SETOF public.event_logs
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  has_region       BOOLEAN;
  has_country_code BOOLEAN;
  q                TEXT;
BEGIN
  -- Detect optional geo enrichment columns.
  -- These columns exist only after the dev seed (or a future geo migration).
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'event_logs'
      AND column_name  = 'region'
  ) INTO has_region;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'event_logs'
      AND column_name  = 'country_code'
  ) INTO has_country_code;

  -- Base filter: time range, city_code, mode — always present in production schema.
  q := 'SELECT * FROM public.event_logs e
        WHERE e.created_at >= $1
          AND e.created_at <  $2
          AND ($5 IS NULL OR e.city_code = $5)
          AND ($6 IS NULL OR e.mode      = $6)';

  -- Conditionally add geo filters only when the columns exist.
  IF has_region THEN
    q := q || ' AND ($3 IS NULL OR e.region = $3)';
  END IF;

  IF has_country_code THEN
    q := q || ' AND ($4 IS NULL OR e.country_code = $4)';
  END IF;

  RETURN QUERY EXECUTE q
    USING p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode;
END;
$$;

COMMENT ON FUNCTION public._lethe_event_filtered(TIMESTAMPTZ,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT) IS
  'Internal helper: returns filtered event_logs rows for analytics aggregate RPCs. '
  'Not callable externally — migrate 046 revokes all public/anon/authenticated grants. '
  'Geo column filters (region, country_code) are applied only when those columns exist.';

-- ---------------------------------------------------------------------------
-- _lethe_confession_filtered
-- Purpose: filter confessions rows by date range + optional geo dimensions.
--          Used as an internal building block by mood analytics RPCs.
-- Returns: SETOF public.confessions (full row, with whatever columns exist)
-- Signature must match exactly what migration 046 REVOKEs from:
--   REVOKE ... ON FUNCTION public._lethe_confession_filtered(DATE,DATE,TEXT,TEXT,TEXT) ...
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._lethe_confession_filtered(
  p_start_date   DATE,
  p_end_date     DATE,
  p_region       TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code    TEXT DEFAULT NULL
)
RETURNS SETOF public.confessions
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  has_region       BOOLEAN;
  has_country_code BOOLEAN;
  has_city_code    BOOLEAN;
  q                TEXT;
BEGIN
  -- Detect optional geo enrichment columns.
  -- These columns exist only after the dev seed (or a future geo migration).
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'confessions'
      AND column_name  = 'region'
  ) INTO has_region;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'confessions'
      AND column_name  = 'country_code'
  ) INTO has_country_code;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'confessions'
      AND column_name  = 'city_code'
  ) INTO has_city_code;

  -- Base filter: date range cast — created_at is always present in production schema.
  q := 'SELECT * FROM public.confessions c
        WHERE c.created_at::DATE >= $1
          AND c.created_at::DATE <= $2';

  -- Conditionally add geo filters only when the columns exist.
  IF has_region THEN
    q := q || ' AND ($3 IS NULL OR c.region = $3)';
  END IF;

  IF has_country_code THEN
    q := q || ' AND ($4 IS NULL OR c.country_code = $4)';
  END IF;

  IF has_city_code THEN
    q := q || ' AND ($5 IS NULL OR c.city_code = $5)';
  END IF;

  RETURN QUERY EXECUTE q
    USING p_start_date, p_end_date, p_region, p_country_code, p_city_code;
END;
$$;

COMMENT ON FUNCTION public._lethe_confession_filtered(DATE,DATE,TEXT,TEXT,TEXT) IS
  'Internal helper: returns filtered confessions rows for mood analytics RPCs. '
  'Not callable externally — migration 046 revokes all public/anon/authenticated grants. '
  'Geo column filters (region, country_code, city_code) are applied only when those columns exist.';

-- ---------------------------------------------------------------------------
-- No explicit GRANT is added here.
-- PostgreSQL default grants EXECUTE to PUBLIC for newly created functions.
-- Migration 046 immediately revokes that default grant, so the window where
-- these helpers carry PUBLIC execute is limited to the migration transaction itself.
-- ---------------------------------------------------------------------------
