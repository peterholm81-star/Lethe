-- ============================================================
-- REPORTS GEO V1 - City Code for Reports
-- ============================================================
-- Run this in Supabase SQL Editor (as service role)
--
-- PURPOSE:
-- Enables city_code on confession_reports by:
-- 1. Creating an RPC for report creation with city_code
-- 2. Providing a backfill function for existing reports
--
-- ARCHITECTURE NOTE:
-- In Lethe, city_code values come from the backend geo service
-- when fetching the feed (setGeoDimensions in analytics.ts).
-- The place_cache table stores place name lookups (query -> lat/lng),
-- NOT city code lookups. Therefore, v1 validation is simple:
-- - We trust city_code from client (it came from our backend)
-- - We sanitize and normalize it
-- - We optionally check it matches known values from event_logs
--
-- Future v2 could add a city_codes lookup table for strict validation.
-- ============================================================

-- ============================================================
-- 1. HAVERSINE DISTANCE FUNCTION (for future use / backfill)
-- ============================================================
-- Calculates distance in meters between two lat/lng points.
-- Used when PostGIS is not available.

DROP FUNCTION IF EXISTS public.haversine_distance_m(double precision, double precision, double precision, double precision);

CREATE OR REPLACE FUNCTION public.haversine_distance_m(
  lat1 double precision,
  lng1 double precision,
  lat2 double precision,
  lng2 double precision
)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  R constant double precision := 6371000; -- Earth radius in meters
  dlat double precision;
  dlng double precision;
  a double precision;
  c double precision;
BEGIN
  -- Handle nulls
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;

  -- Convert to radians
  dlat := radians(lat2 - lat1);
  dlng := radians(lng2 - lng1);
  
  -- Haversine formula
  a := sin(dlat / 2) * sin(dlat / 2) +
       cos(radians(lat1)) * cos(radians(lat2)) *
       sin(dlng / 2) * sin(dlng / 2);
  c := 2 * atan2(sqrt(a), sqrt(1 - a));
  
  RETURN R * c;
END;
$$;

-- ============================================================
-- 2. RPC: CREATE CONFESSION REPORT V1 (with city_code)
-- ============================================================
-- This replaces direct INSERT into confession_reports.
--
-- Validation rules (v1 - simple):
-- - Sanitize/normalize city_code (uppercase, trim)
-- - If empty or whitespace-only -> NULL
-- - Trust the value (it came from our backend geo service)
--
-- Note: We NEVER reject the report. Invalid city_code = NULL.

DROP FUNCTION IF EXISTS public.create_confession_report_v1(uuid, text, text, text, double precision, double precision, jsonb);

CREATE OR REPLACE FUNCTION public.create_confession_report_v1(
  p_confession_id uuid,
  p_reason text,
  p_details text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_context jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city_code_clean text := NULL;
  v_report_id uuid;
BEGIN
  -- =========================================
  -- SANITIZE CITY_CODE (v1: trust but clean)
  -- =========================================
  IF p_city_code IS NOT NULL THEN
    v_city_code_clean := UPPER(TRIM(p_city_code));
    -- Reject obviously invalid values
    IF v_city_code_clean = '' OR LENGTH(v_city_code_clean) > 50 THEN
      v_city_code_clean := NULL;
    END IF;
  END IF;

  -- =========================================
  -- INSERT REPORT
  -- =========================================
  INSERT INTO confession_reports (
    confession_id,
    reason,
    details,
    city_code,
    created_at
  ) VALUES (
    p_confession_id,
    p_reason,
    p_details,
    v_city_code_clean,
    now()
  )
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$$;

-- Grant execute to anon/authenticated (RLS still applies to underlying table)
GRANT EXECUTE ON FUNCTION public.create_confession_report_v1(uuid, text, text, text, double precision, double precision, jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.create_confession_report_v1(uuid, text, text, text, double precision, double precision, jsonb) TO authenticated;

-- ============================================================
-- 3. BACKFILL FUNCTION: Fill missing city_codes on old reports
-- ============================================================
-- Uses confession's city_code (if available) to backfill report's city_code.
-- Call manually: SELECT backfill_report_city_codes_v1();
--
-- NOTE: This assumes confessions table has city_code column.
-- If confessions don't have city_code, this won't help much.

DROP FUNCTION IF EXISTS public.backfill_report_city_codes_v1(integer);

CREATE OR REPLACE FUNCTION public.backfill_report_city_codes_v1(
  p_batch_limit integer DEFAULT 1000
)
RETURNS TABLE (
  reports_checked bigint,
  reports_updated bigint,
  reports_skipped bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_checked bigint := 0;
  v_updated bigint := 0;
  v_skipped bigint := 0;
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Update reports with missing city_code by copying from confession
  -- (if confession has city_code)
  WITH updates AS (
    UPDATE confession_reports r
    SET city_code = UPPER(TRIM(c.city_code))
    FROM confessions c
    WHERE r.confession_id = c.id
      AND r.city_code IS NULL
      AND c.city_code IS NOT NULL
      AND TRIM(c.city_code) <> ''
    RETURNING r.id
  )
  SELECT COUNT(*) INTO v_updated FROM updates;

  -- Count remaining unhandled
  SELECT COUNT(*) INTO v_skipped
  FROM confession_reports
  WHERE city_code IS NULL;

  v_checked := v_updated + v_skipped;
  
  RETURN QUERY SELECT v_checked, v_updated, v_skipped;
END;
$$;

-- Grant execute to admin only (function has internal admin check too)
GRANT EXECUTE ON FUNCTION public.backfill_report_city_codes_v1(integer) TO authenticated;

-- ============================================================
-- NOTIFY POSTGREST
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION QUERIES (run manually)
-- ============================================================
-- Check recent reports with city_code:
-- SELECT city_code, count(*) 
-- FROM confession_reports 
-- WHERE created_at > now() - interval '24 hours' 
-- GROUP BY 1 ORDER BY 2 DESC;

-- Test the RPC (replace with real confession_id):
-- SELECT create_confession_report_v1(
--   'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'::uuid,  -- confession_id
--   'SPAM',                                         -- reason
--   'Test report',                                  -- details
--   'OSL',                                          -- city_code
--   NULL,                                           -- lat (optional)
--   NULL                                            -- lng (optional)
-- );

-- Run backfill (admin only):
-- SELECT * FROM backfill_report_city_codes_v1(1000);
