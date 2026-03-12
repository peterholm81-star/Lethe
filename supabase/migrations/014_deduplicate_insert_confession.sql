-- Migration: Deduplicate insert_confession overloads
--
-- Root cause of regression after 013:
--   A stale overloaded version of insert_confession (different signature,
--   created outside of migrations) was left in the database. CREATE OR REPLACE
--   in migration 013 only replaced the matching 4-param overload — it did not
--   remove the stale one. PostgREST sees multiple functions with the same name
--   and cannot resolve which to call, returning an ambiguity error that the
--   frontend does not recognise, showing "Could not save confession".
--
-- Fix:
--   1. Drop ALL overloads of insert_confession in the public schema atomically.
--   2. Recreate the single definitive version with the full write guard.
--
-- The function body, rate-limit logic, and burst-limit logic are identical
-- to migration 013. Only the cleanup step is new.

-- =============================================================================
-- STEP 1: Drop every overloaded version of insert_confession
-- =============================================================================
-- Uses pg_proc to find all overloads by name in the public schema and drops
-- each one by its fully-resolved identity (regprocedure). This handles the
-- stale overload regardless of what its argument types were.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure::TEXT AS sig
    FROM   pg_proc
    WHERE  proname        = 'insert_confession'
      AND  pronamespace   = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
  END LOOP;
END;
$$;

-- =============================================================================
-- STEP 2: Recreate the single definitive version
-- =============================================================================

CREATE FUNCTION insert_confession(
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
  v_digits_only  TEXT;
BEGIN
  -- Get current user (anonymous or authenticated)
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
  -- CONTENT FILTER: Block patterns that might identify real people
  -- ==========================================================================

  -- Block @ character (emails, social handles)
  IF position('@' IN v_text) > 0 THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Block URLs (http, https, www)
  IF v_text ~* 'https?://' OR v_text ~* '\mwww\.' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Block common TLDs
  IF v_text ~* '\.(com|net|org|no|io|co|app)\M' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Extract digits only (remove spaces, hyphens, parentheses)
  v_digits_only := regexp_replace(v_text, '[^0-9]', '', 'g');

  -- Block 8+ digits in total (phone-number pattern)
  IF length(v_digits_only) >= 8 THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Block +<digits> country code pattern (e.g., +47, +1)
  IF v_text ~ '\+\s*[0-9]' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Block two adjacent title-case words (likely a real name)
  IF v_text ~ '\m[A-Z][a-z]+\s+[A-Z][a-z]+\M' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- ==========================================================================
  -- RATE LIMITING  (only enforced when auth.uid() is available)
  -- ==========================================================================

  IF v_user_id IS NOT NULL THEN

    -- Gap check: minimum 15 seconds between any two consecutive posts.
    SELECT c.created_at INTO v_last_post
    FROM   confessions c
    WHERE  c.user_id = v_user_id
    ORDER  BY c.created_at DESC
    LIMIT  1;

    IF v_last_post IS NOT NULL AND v_last_post > now() - interval '15 seconds' THEN
      RAISE EXCEPTION 'RATE_LIMIT: Please wait before posting again';
    END IF;

    -- Burst check: maximum 3 posts within any rolling 5-minute window.
    SELECT COUNT(*) INTO v_recent_count
    FROM   confessions c
    WHERE  c.user_id    = v_user_id
      AND  c.created_at > now() - interval '5 minutes';

    IF v_recent_count >= 3 THEN
      RAISE EXCEPTION 'BURST_LIMIT: Too many posts in a short time. Come back in a few minutes.';
    END IF;

  END IF;

  -- ==========================================================================
  -- INSERT
  -- ==========================================================================

  INSERT INTO confessions (
    text,
    lat,
    lng,
    expires_at,
    is_hidden,
    user_id
  ) VALUES (
    v_text,
    p_lat,
    p_lng,
    now() + interval '24 hours',
    false,
    v_user_id
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
  FROM confessions c
  WHERE c.id = v_inserted_id;
END;
$$;

-- =============================================================================
-- STEP 3: Grant execute with fully-qualified signature (no ambiguity possible
-- now that there is exactly one overload)
-- =============================================================================
GRANT EXECUTE ON FUNCTION insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO anon;
GRANT EXECUTE ON FUNCTION insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
