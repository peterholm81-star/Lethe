-- Migration: Remove lat/lng from get_confess_feed response.
--
-- The feed RPC previously returned the exact GPS coordinates of each poster
-- to every client. The frontend never displays or uses these values — they
-- were only stored in component state. For a privacy-first anonymous platform,
-- broadcasting a poster's precise physical location to every reader is
-- unnecessary exposure.
--
-- lat/lng remain stored on the confessions table and are still used by the
-- Haversine WHERE clause in 'near' mode. They are simply no longer included
-- in the RETURNS TABLE or SELECT list, so they never leave the database.
--
-- The insert_confession RPC is unchanged: a user's own coordinates are
-- accepted, stored, and queried server-side only.

DROP FUNCTION IF EXISTS get_confess_feed(
  TEXT,
  INTEGER,
  TIMESTAMPTZ,
  UUID,
  DOUBLE PRECISION,
  DOUBLE PRECISION,
  INTEGER
);

CREATE OR REPLACE FUNCTION get_confess_feed(
  p_mode              TEXT             DEFAULT 'world',
  p_limit             INTEGER          DEFAULT 30,
  p_cursor_created_at TIMESTAMPTZ      DEFAULT NULL,
  p_cursor_id         UUID             DEFAULT NULL,
  p_lat               DOUBLE PRECISION DEFAULT NULL,
  p_lng               DOUBLE PRECISION DEFAULT NULL,
  p_radius_m          INTEGER          DEFAULT 10000
)
RETURNS TABLE (
  id         UUID,
  text       TEXT,
  created_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
  -- lat/lng intentionally omitted: coordinates must not leave the database
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_limit  INTEGER;
  v_radius INTEGER;
BEGIN
  v_limit  := GREATEST(10, LEAST(50, COALESCE(p_limit, 30)));
  v_radius := GREATEST(100, LEAST(50000, COALESCE(p_radius_m, 10000)));

  IF p_mode = 'near' THEN
    -- =========================================================================
    -- NEAR MODE: confessions WITH lat/lng within radius
    -- =========================================================================
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RAISE EXCEPTION 'lat and lng are required for near mode';
    END IF;

    RETURN QUERY
    SELECT
      c.id,
      c.text,
      c.created_at,
      c.expires_at
    FROM confessions c
    WHERE c.expires_at > now()
      AND COALESCE(c.is_hidden, false) = false
      AND c.lat IS NOT NULL
      AND c.lng IS NOT NULL
      AND (
        6371000 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(p_lat)) * cos(radians(c.lat)) *
            cos(radians(c.lng) - radians(p_lng)) +
            sin(radians(p_lat)) * sin(radians(c.lat))
          ))
        )
      ) <= v_radius
      AND (
        p_cursor_created_at IS NULL
        OR c.created_at < p_cursor_created_at
        OR (c.created_at = p_cursor_created_at AND c.id < p_cursor_id)
      )
    ORDER BY c.created_at DESC, c.id DESC
    LIMIT v_limit;

  ELSE
    -- =========================================================================
    -- WORLD MODE: ALL confessions (both with and without lat/lng)
    -- =========================================================================
    RETURN QUERY
    SELECT
      c.id,
      c.text,
      c.created_at,
      c.expires_at
    FROM confessions c
    WHERE c.expires_at > now()
      AND COALESCE(c.is_hidden, false) = false
      AND (
        p_cursor_created_at IS NULL
        OR c.created_at < p_cursor_created_at
        OR (c.created_at = p_cursor_created_at AND c.id < p_cursor_id)
      )
    ORDER BY c.created_at DESC, c.id DESC
    LIMIT v_limit;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION get_confess_feed TO anon;
GRANT EXECUTE ON FUNCTION get_confess_feed TO authenticated;
