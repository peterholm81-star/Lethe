-- Migration: Fix overly aggressive content filters in insert_confession
--
-- Two rules caused significant false positives:
--
-- 1. DIGIT FILTER (was: count all digits in text)
--    Old behaviour: strip every non-digit character from the entire text,
--    concatenate them, then block if the resulting string is 8+ chars long.
--    Problem: "I wasted 3 years in 2019, 2020 and 2021" strips to
--    "3201920202021" (13 digits) → blocked despite no phone number present.
--    Fix: match 8+ CONSECUTIVE digits in the original text. A real phone
--    number is a run of digits; individual years, ages, and quantities are not.
--
-- 2. CAPITALIZED-WORD FILTER (was: block two adjacent title-case words)
--    Old behaviour: block any confession matching \m[A-Z][a-z]+\s+[A-Z][a-z]+\M.
--    Problem: blocks city names (New York, Los Angeles, San Francisco) and any
--    ordinary English phrase where two title-case words happen to be adjacent.
--    There is no reliable way to distinguish "John Smith" from "New York" with
--    this pattern. The existing URL, email, and phone-number filters already
--    cover the main contact-info vectors. Removing this rule eliminates the
--    false positives while keeping reporting + moderation as the safety net
--    for genuinely identifying content.
--
-- Everything else (@ handles, URLs, TLDs, country-code prefix) is unchanged.
-- Rate-limiting and burst-limit logic is identical to migration 014.

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
  -- CONTENT FILTER: Block patterns that might share contact information
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
  -- Matches a run of 8 or more digits without any intervening non-digit
  -- characters. Individual years (2019), ages (34), and quantities (3) do not
  -- form a consecutive run and are therefore not affected.
  -- Replaces the old "strip all non-digits, count total" approach which
  -- falsely blocked confessions containing several scattered numbers.
  IF v_text ~ '[0-9]{8,}' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- Block +<digits> country code pattern (e.g., +47, +1)
  IF v_text ~ '\+\s*[0-9]' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- NOTE: The two-adjacent-title-case-words rule was removed.
  -- It blocked city names (New York, Los Angeles, San Francisco) and any
  -- ordinary English phrase with two capitalised words. The URL, email, and
  -- phone-number filters above already cover the primary contact-info vectors.
  -- Reports and moderation handle genuinely identifying content.

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
