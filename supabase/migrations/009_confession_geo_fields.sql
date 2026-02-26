-- Migration: Add geo fields to insert_confession RPC
-- Stores region, city_code, country, country_code when posting a confession
-- These come from the client's session geo (determined by edge function on app start)
--
-- IMPORTANT: This migration drops the old 4-arg function and creates a new 8-arg function.
-- The new function has DEFAULT NULL for geo params, so callers can still use 4 args.

-- =============================================================================
-- ENSURE GEO COLUMNS EXIST ON CONFESSIONS
-- =============================================================================

ALTER TABLE confessions ADD COLUMN IF NOT EXISTS region text;
ALTER TABLE confessions ADD COLUMN IF NOT EXISTS city_code text;
ALTER TABLE confessions ADD COLUMN IF NOT EXISTS country text;
ALTER TABLE confessions ADD COLUMN IF NOT EXISTS country_code text;

-- Indexes for geo filtering/grouping
CREATE INDEX IF NOT EXISTS idx_confessions_region ON confessions (region);
CREATE INDEX IF NOT EXISTS idx_confessions_city_code ON confessions (city_code);
CREATE INDEX IF NOT EXISTS idx_confessions_country ON confessions (country);
CREATE INDEX IF NOT EXISTS idx_confessions_country_code ON confessions (country_code);

-- =============================================================================
-- DROP OLD FUNCTION (must use exact signature)
-- =============================================================================
-- The old function has signature: (text, text, double precision, double precision)
-- We drop it so we can create a single function with geo params.
-- This is safe because the new function accepts the same first 4 args with defaults for the rest.

DROP FUNCTION IF EXISTS public.insert_confession(text, text, double precision, double precision);

-- =============================================================================
-- CREATE NEW FUNCTION WITH GEO PARAMS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.insert_confession(
  p_text TEXT,
  p_place_label TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
  -- Geo fields from client session (all optional with defaults)
  p_region TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  text TEXT,
  created_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_text TEXT;
  v_user_id UUID;
  v_last_post TIMESTAMPTZ;
  v_inserted_id UUID;
  v_digits_only TEXT;
BEGIN
  -- Get current user (anonymous or authenticated)
  v_user_id := auth.uid();
  
  -- Trim and validate text
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
  
  -- A) Contact / handles / links
  
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
  
  -- B) Phone-like sequences
  
  -- Extract digits only (remove spaces, hyphens, parentheses)
  v_digits_only := regexp_replace(v_text, '[^0-9]', '', 'g');
  
  -- Block 8+ consecutive digits
  IF length(v_digits_only) >= 8 THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  -- Block +<digits> country code pattern (e.g., +47, +1)
  IF v_text ~ '\+\s*[0-9]' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  -- C) Obvious real-name pattern
  -- Two capitalized words (e.g., "John Smith", "Kari Nordmann")
  IF v_text ~ '\m[A-Z][a-z]+\s+[A-Z][a-z]+\M' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;

  -- ==========================================================================
  -- RATE LIMITING
  -- ==========================================================================
  
  IF v_user_id IS NOT NULL THEN
    SELECT c.created_at INTO v_last_post
    FROM confessions c
    WHERE c.user_id = v_user_id
    ORDER BY c.created_at DESC
    LIMIT 1;
    
    IF v_last_post IS NOT NULL AND v_last_post > now() - interval '15 seconds' THEN
      RAISE EXCEPTION 'RATE_LIMIT: Please wait before posting again';
    END IF;
  END IF;
  
  -- ==========================================================================
  -- INSERT (includes geo fields)
  -- ==========================================================================
  
  INSERT INTO confessions (
    text,
    lat,
    lng,
    expires_at,
    is_hidden,
    user_id,
    region,
    city_code,
    country,
    country_code
  ) VALUES (
    v_text,
    p_lat,
    p_lng,
    now() + interval '24 hours',
    false,
    v_user_id,
    NULLIF(TRIM(COALESCE(p_region, '')), ''),
    NULLIF(TRIM(COALESCE(p_city_code, '')), ''),
    NULLIF(TRIM(COALESCE(p_country, '')), ''),
    NULLIF(TRIM(COALESCE(p_country_code, '')), '')
  )
  RETURNING confessions.id INTO v_inserted_id;
  
  -- Return the inserted row (selected fields only)
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
-- GRANTS (must use exact signature to avoid ambiguity)
-- =============================================================================
-- New 8-arg signature: (text, text, double precision, double precision, text, text, text, text)

GRANT EXECUTE ON FUNCTION public.insert_confession(text, text, double precision, double precision, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.insert_confession(text, text, double precision, double precision, text, text, text, text) TO authenticated;

-- =============================================================================
-- VERIFICATION QUERIES (run manually after deploy)
-- =============================================================================
/*
-- 1. Check which insert_confession functions exist:
SELECT 
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'insert_confession';

-- 2. Test insert with geo (use a unique test text):
SELECT * FROM public.insert_confession(
  'Test geo confession',
  NULL,
  59.91,
  10.75,
  'Europe',
  'OSL',
  'Norway',
  'NO'
);

-- 3. Verify geo was stored:
SELECT id, text, region, city_code, country, country_code, created_at
FROM confessions
WHERE text = 'Test geo confession'
ORDER BY created_at DESC
LIMIT 1;

-- 4. Delete test confession:
-- DELETE FROM confessions WHERE text = 'Test geo confession';
*/
