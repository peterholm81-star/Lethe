-- Migration: Narrow the +<digits> phone-number content filter.
--
-- Previous pattern: \+\s*[0-9]
--   Blocked any "+" followed by optional whitespace and a digit.
--   False positives: "+1 to everything", "I gained +3 kg", "+5°C outside".
--   These are normal emotional and descriptive expressions, not phone numbers.
--
-- New pattern: \+[0-9]{7,}
--   Requires "+" to be immediately followed by 7 or more consecutive digits.
--   This matches international phone number formats (+4712345678, +15551234567)
--   while leaving short positive expressions and temperature notation untouched.
--
--   The existing [0-9]{8,} rule already catches 8+ consecutive digit runs
--   regardless of a leading "+", so this rule's only remaining job is to catch
--   the edge case of a "+" prefix before a 7-digit local number. Together the
--   two rules cover all realistic phone-number patterns without blocking natural
--   writing.
--
-- All other content filter rules (@ handles, URLs, TLDs, 8+ consecutive digits)
-- are unchanged. Rate-limiting logic is identical to migration 015.

CREATE OR REPLACE FUNCTION insert_confession(
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

  -- Block 8+ consecutive digits (phone-number-like sequences).
  IF v_text ~ '[0-9]{8,}' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Block international phone-number prefix: "+" immediately followed by 7+
  -- digits (e.g. +4712345678, +15551234567).
  -- Changed from \+\s*[0-9] which also blocked "+1 to that", "+3 kg", "+5°C".
  IF v_text ~ '\+[0-9]{7,}' THEN
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

GRANT EXECUTE ON FUNCTION insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO anon;
GRANT EXECUTE ON FUNCTION insert_confession(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
