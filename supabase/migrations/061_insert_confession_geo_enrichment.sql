-- =============================================================================
-- Migration 061: insert_confession — nearest-city geo enrichment
-- =============================================================================
-- Phase C v1: When a new confession is inserted with lat/lng, attempt to
-- resolve country_code, region, city_code via a nearest-neighbor lookup
-- against public.geo_cities (25 world cities, migration 060).
--
-- Lookup strategy:
--   - Haversine formula (great-circle distance) against all rows in geo_cities
--   - Match only if closest city is within 100 km
--   - 100 km chosen deliberately: better NULL than wrong geo
--   - If lat/lng is NULL, or no city within 100 km, geo fields remain NULL
--
-- Safety guarantees:
--   - Confession insert NEVER fails because of geo lookup failure
--   - A plpgsql exception block wraps the lookup; any error → NULL geo
--   - Signature and return type are identical to migration 018
--
-- event_logs enrichment:
--   - event_logs are written directly by the frontend (analytics.ts)
--   - The client already passes city_code but not region/country_code
--   - No server-side link between insert_confession and event_logs exists
--   - Enriching event_logs.region/country_code is DEFERRED to Phase D
--     (requires frontend changes or a trigger — both out of scope here)
-- =============================================================================

-- Drop previous overloads cleanly before replacing (same pattern as 014).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure::TEXT AS sig
    FROM   pg_proc
    WHERE  proname = 'insert_confession'
      AND  pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.sig);
  END LOOP;
END
$$;

CREATE FUNCTION public.insert_confession(
  p_text        TEXT,
  p_place_label TEXT             DEFAULT NULL,
  p_lat         DOUBLE PRECISION DEFAULT NULL,
  p_lng         DOUBLE PRECISION DEFAULT NULL
)
RETURNS TABLE (
  id         UUID,
  text       TEXT,
  created_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  lat        DOUBLE PRECISION,
  lng        DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_text         TEXT;
  v_user_id      UUID;
  v_last_post    TIMESTAMPTZ;
  v_recent_count BIGINT;
  v_inserted_id  UUID;
  -- Geo enrichment variables
  v_city_code    TEXT := NULL;
  v_region       TEXT := NULL;
  v_country_code TEXT := NULL;
BEGIN
  v_user_id := auth.uid();

  -- ==========================================================================
  -- TEXT VALIDATION
  -- ==========================================================================

  v_text := btrim(p_text);

  IF v_text IS NULL OR v_text = '' THEN
    RAISE EXCEPTION 'EMPTY_TEXT: Confession text cannot be empty';
  END IF;

  IF char_length(v_text) > 120 THEN
    RAISE EXCEPTION 'TEXT_TOO_LONG: Confession must be 120 characters or less';
  END IF;

  -- ==========================================================================
  -- CONTENT FILTER
  -- ==========================================================================

  IF position('@' IN v_text) > 0 THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  IF v_text ~* 'https?://' OR v_text ~* '\mwww\.' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  IF v_text ~* '\.(com|net|org|no|io|co|app)\M' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  IF v_text ~ '[0-9]{8,}' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  IF v_text ~ '\+[0-9]{7,}' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- ==========================================================================
  -- RATE LIMITING
  -- ==========================================================================

  IF v_user_id IS NOT NULL THEN

    SELECT c.created_at INTO v_last_post
    FROM   confessions c
    WHERE  c.user_id = v_user_id
    ORDER  BY c.created_at DESC
    LIMIT  1;

    IF v_last_post IS NOT NULL AND v_last_post > now() - interval '15 seconds' THEN
      RAISE EXCEPTION 'RATE_LIMIT: Please wait before posting again';
    END IF;

    SELECT COUNT(*) INTO v_recent_count
    FROM   confessions c
    WHERE  c.user_id    = v_user_id
      AND  c.created_at > now() - interval '5 minutes';

    IF v_recent_count >= 3 THEN
      RAISE EXCEPTION 'BURST_LIMIT: Too many posts in a short time. Come back in a few minutes.';
    END IF;

  END IF;

  -- ==========================================================================
  -- GEO ENRICHMENT (nearest city within 100 km)
  -- Wrapped in its own block: any failure leaves geo as NULL, never aborts.
  -- ==========================================================================

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    BEGIN
      SELECT
        gc.city_code,
        gc.region,
        gc.country_code
      INTO
        v_city_code,
        v_region,
        v_country_code
      FROM public.geo_cities gc
      ORDER BY
        -- Haversine great-circle distance in km.
        -- LEAST(1.0, ...) guards against floating-point rounding above 1.0.
        6371.0 * acos(
          LEAST(1.0,
            cos(radians(p_lat))  * cos(radians(gc.lat))
            * cos(radians(gc.lng) - radians(p_lng))
            + sin(radians(p_lat)) * sin(radians(gc.lat))
          )
        )
      LIMIT 1;

      -- Reject the match if the nearest city is beyond 100 km.
      IF v_city_code IS NOT NULL THEN
        DECLARE
          v_dist_km DOUBLE PRECISION;
        BEGIN
          SELECT
            6371.0 * acos(
              LEAST(1.0,
                cos(radians(p_lat))  * cos(radians(gc.lat))
                * cos(radians(gc.lng) - radians(p_lng))
                + sin(radians(p_lat)) * sin(radians(gc.lat))
              )
            )
          INTO v_dist_km
          FROM public.geo_cities gc
          WHERE gc.city_code = v_city_code;

          IF v_dist_km > 100.0 THEN
            v_city_code    := NULL;
            v_region       := NULL;
            v_country_code := NULL;
          END IF;
        END;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      -- Geo lookup failed for any reason — degrade gracefully.
      v_city_code    := NULL;
      v_region       := NULL;
      v_country_code := NULL;
    END;
  END IF;

  -- ==========================================================================
  -- INSERT
  -- ==========================================================================

  INSERT INTO public.confessions (
    text,
    lat,
    lng,
    expires_at,
    is_hidden,
    user_id,
    region,
    country_code,
    city_code
  ) VALUES (
    v_text,
    p_lat,
    p_lng,
    now() + interval '24 hours',
    false,
    v_user_id,
    v_region,
    v_country_code,
    v_city_code
  )
  RETURNING confessions.id INTO v_inserted_id;

  RETURN QUERY
  SELECT
    c.id,
    c.text,
    c.created_at,
    c.expires_at,
    c.lat,
    c.lng
  FROM public.confessions c
  WHERE c.id = v_inserted_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
  TO anon;
GRANT EXECUTE ON FUNCTION public.insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
  TO authenticated;
