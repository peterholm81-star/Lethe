-- =============================================================================
-- Migration 062: insert_confession — return resolved geo fields
-- =============================================================================
-- Phase D: The RPC already resolves city_code/region/country_code onto the
-- confessions row (migration 061). This migration extends the RETURNS TABLE
-- to expose those three fields to callers.
--
-- The frontend uses the returned geo to:
--   1. Pass city_code/region/country_code into post_success event_logs row
--   2. Cache geo in-memory (geoContextRef) for subsequent logEvent calls
--      in the same session (feed_view, etc.)
--
-- Nothing else changes:
--   - Same parameters
--   - Same validation / content filter / rate limiting
--   - Same geo lookup logic (100 km max radius, NULL on miss)
--   - NULL geo still produces a valid confession
--   - All existing callers that ignore the new columns are unaffected
-- =============================================================================

-- Drop all overloads cleanly (same pattern as migration 061).
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
  id            UUID,
  text          TEXT,
  created_at    TIMESTAMPTZ,
  expires_at    TIMESTAMPTZ,
  lat           DOUBLE PRECISION,
  lng           DOUBLE PRECISION,
  city_code     TEXT,
  region        TEXT,
  country_code  TEXT
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
  -- Geo enrichment
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
  -- Any failure leaves geo as NULL and never aborts the insert.
  -- ==========================================================================

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    BEGIN
      SELECT gc.city_code, gc.region, gc.country_code
      INTO   v_city_code, v_region, v_country_code
      FROM   public.geo_cities gc
      ORDER BY
        6371.0 * acos(
          LEAST(1.0,
            cos(radians(p_lat))  * cos(radians(gc.lat))
            * cos(radians(gc.lng) - radians(p_lng))
            + sin(radians(p_lat)) * sin(radians(gc.lat))
          )
        )
      LIMIT 1;

      -- Reject match if the nearest city exceeds 100 km.
      IF v_city_code IS NOT NULL THEN
        DECLARE
          v_dist_km DOUBLE PRECISION;
        BEGIN
          SELECT 6371.0 * acos(
                   LEAST(1.0,
                     cos(radians(p_lat))  * cos(radians(gc.lat))
                     * cos(radians(gc.lng) - radians(p_lng))
                     + sin(radians(p_lat)) * sin(radians(gc.lat))
                   )
                 )
          INTO   v_dist_km
          FROM   public.geo_cities gc
          WHERE  gc.city_code = v_city_code;

          IF v_dist_km > 100.0 THEN
            v_city_code    := NULL;
            v_region       := NULL;
            v_country_code := NULL;
          END IF;
        END;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_city_code    := NULL;
      v_region       := NULL;
      v_country_code := NULL;
    END;
  END IF;

  -- ==========================================================================
  -- INSERT
  -- ==========================================================================

  INSERT INTO public.confessions (
    text, lat, lng, expires_at, is_hidden, user_id,
    region, country_code, city_code
  ) VALUES (
    v_text, p_lat, p_lng,
    now() + interval '24 hours',
    false, v_user_id,
    v_region, v_country_code, v_city_code
  )
  RETURNING confessions.id INTO v_inserted_id;

  -- Return all fields including the resolved geo.
  RETURN QUERY
  SELECT
    c.id, c.text, c.created_at, c.expires_at, c.lat, c.lng,
    c.city_code, c.region, c.country_code
  FROM public.confessions c
  WHERE c.id = v_inserted_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
  TO anon;
GRANT EXECUTE ON FUNCTION public.insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)
  TO authenticated;
