-- ============================================================
-- REPORTS GEO ATTRIBUTION v1
-- ============================================================
-- Adds reliable geo attribution for confession_reports by:
-- 1. Adding city_code to confessions table
-- 2. Auto-setting city_code on confession insert from lat/lng
-- 3. Auto-copying city_code to reports on report insert
-- 4. RPC to get top reported cities
--
-- Privacy: Only stores coarse city_code (place_cache id as text).
-- No IP, no precise location beyond existing lat/lng.
-- ============================================================

-- ============================================================
-- 1. ADD city_code TO confessions
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'confessions' 
      AND column_name = 'city_code'
  ) THEN
    ALTER TABLE public.confessions ADD COLUMN city_code text;
    RAISE NOTICE 'Added city_code column to confessions';
  ELSE
    RAISE NOTICE 'city_code column already exists on confessions';
  END IF;
END $$;

-- Create index for geo queries
CREATE INDEX IF NOT EXISTS idx_confessions_city_code 
  ON public.confessions (city_code) 
  WHERE city_code IS NOT NULL;

-- ============================================================
-- 2. HELPER: Resolve city_code from lat/lng
-- ============================================================
-- Uses haversine distance (no PostGIS dependency).
-- Returns place_cache.id::text as city_code for the nearest place within 50km.

-- First ensure haversine_distance_m exists (may already exist from reports_geo_v1_setup.sql)
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
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;
  dlat := radians(lat2 - lat1);
  dlng := radians(lng2 - lng1);
  a := sin(dlat / 2) * sin(dlat / 2) +
       cos(radians(lat1)) * cos(radians(lat2)) *
       sin(dlng / 2) * sin(dlng / 2);
  c := 2 * atan2(sqrt(a), sqrt(1 - a));
  RETURN R * c;
END;
$$;

-- Resolve city_code from lat/lng by finding nearest place_cache entry within 50km
CREATE OR REPLACE FUNCTION public.resolve_city_code_from_lat_lng(
  p_lat double precision,
  p_lng double precision
)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT pc.id::text
  FROM public.place_cache pc
  WHERE pc.lat IS NOT NULL 
    AND pc.lng IS NOT NULL
    AND public.haversine_distance_m(p_lat, p_lng, pc.lat, pc.lng) <= 50000
  ORDER BY public.haversine_distance_m(p_lat, p_lng, pc.lat, pc.lng) ASC
  LIMIT 1;
$$;

-- ============================================================
-- 3. TRIGGER: Auto-set city_code on confession insert
-- ============================================================
CREATE OR REPLACE FUNCTION public.trg_set_confession_city_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only set if not already provided
  IF NEW.city_code IS NULL THEN
    -- Try to resolve from lat/lng
    IF NEW.lat IS NOT NULL AND NEW.lng IS NOT NULL THEN
      NEW.city_code := public.resolve_city_code_from_lat_lng(NEW.lat, NEW.lng);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_confession_city_code ON public.confessions;
CREATE TRIGGER trg_set_confession_city_code
  BEFORE INSERT ON public.confessions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_set_confession_city_code();

-- ============================================================
-- 4. TRIGGER: Auto-set city_code on report insert
-- ============================================================
-- Copies city_code from the referenced confession if not provided.

CREATE OR REPLACE FUNCTION public.trg_set_report_city_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_city_code text;
BEGIN
  -- Only set if not already provided
  IF NEW.city_code IS NULL AND NEW.confession_id IS NOT NULL THEN
    -- Get city_code from the referenced confession
    SELECT c.city_code INTO v_city_code
    FROM public.confessions c
    WHERE c.id = NEW.confession_id;
    
    NEW.city_code := v_city_code;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_report_city_code ON public.confession_reports;
CREATE TRIGGER trg_set_report_city_code
  BEFORE INSERT ON public.confession_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_set_report_city_code();

-- ============================================================
-- 5. RPC: Get top reported cities
-- ============================================================
-- Returns top cities by report count, with city name from place_cache.
-- Admin-only for now (Insights dashboard).

DROP FUNCTION IF EXISTS public.get_top_report_cities(int, int);

CREATE OR REPLACE FUNCTION public.get_top_report_cities(
  p_days int DEFAULT 14,
  p_limit int DEFAULT 10
)
RETURNS TABLE (
  city_code text,
  city_name text,
  reports bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cr.city_code,
    COALESCE(pc.name, cr.city_code) AS city_name,
    COUNT(*)::bigint AS reports
  FROM public.confession_reports cr
  LEFT JOIN public.place_cache pc
    ON pc.id::text = cr.city_code
  WHERE cr.created_at >= now() - make_interval(days => p_days)
    AND cr.city_code IS NOT NULL
    AND TRIM(cr.city_code) <> ''
  GROUP BY cr.city_code, pc.name
  ORDER BY COUNT(*) DESC
  LIMIT GREATEST(1, LEAST(p_limit, 50));
$$;

-- Grant to authenticated (no admin check - returns only aggregated data)
GRANT EXECUTE ON FUNCTION public.get_top_report_cities(int, int) TO authenticated;

-- ============================================================
-- 6. BACKFILL: Set city_code on existing confessions (optional)
-- ============================================================
-- Run this manually if you want to backfill existing confessions.
-- Only updates rows where city_code is null and lat/lng are available.

-- DO $$
-- DECLARE
--   v_updated int := 0;
-- BEGIN
--   UPDATE public.confessions c
--   SET city_code = public.resolve_city_code_from_lat_lng(c.lat, c.lng)
--   WHERE c.city_code IS NULL
--     AND c.lat IS NOT NULL
--     AND c.lng IS NOT NULL;
--   GET DIAGNOSTICS v_updated = ROW_COUNT;
--   RAISE NOTICE 'Backfilled city_code on % confessions', v_updated;
-- END $$;

-- ============================================================
-- NOTIFY POSTGREST
-- ============================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- TEST QUERIES (run manually after deploying)
-- ============================================================
-- Check confession city_codes:
-- SELECT city_code, count(*) FROM confessions WHERE city_code IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

-- Check report city_codes:
-- SELECT city_code, count(*) FROM confession_reports WHERE city_code IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

-- Test the RPC:
-- SELECT * FROM get_top_report_cities(14, 10);
