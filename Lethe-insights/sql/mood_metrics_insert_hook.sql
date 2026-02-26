-- =============================================================================
-- MOOD METRICS: Hook into insert_confession RPC
-- =============================================================================
--
-- Modifies the existing insert_confession function to:
-- 1. Classify mood from text (simple keyword heuristic v1)
-- 2. Call rpc_increment_confession_metric after successful insert
-- 3. Never fail the confession insert if mood tracking fails
--
-- PRIVACY: Mood is NOT stored in confessions table, only in aggregated metrics.
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role).
-- DEPENDS ON: mood_metrics_setup.sql must be run first.
--
-- =============================================================================

-- =============================================================================
-- 1. HELPER: Get time bucket from current hour
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_time_bucket(p_hour integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_hour >= 0 AND p_hour <= 5 THEN 'night'      -- 00:00-05:59
    WHEN p_hour >= 6 AND p_hour <= 11 THEN 'morning'   -- 06:00-11:59
    WHEN p_hour >= 12 AND p_hour <= 17 THEN 'afternoon' -- 12:00-17:59
    ELSE 'evening'                                      -- 18:00-23:59
  END;
$$;

-- =============================================================================
-- 2. HELPER: Classify mood from text (simple keyword heuristic v1)
-- =============================================================================
-- Returns one of 12 mood buckets based on keyword matching.
-- Default: 'calm' when no keywords match (neutral baseline).
--
-- Mood buckets: joy, love, calm, hope, gratitude, confidence,
--               anxiety, sadness, anger, loneliness, desire, shame

CREATE OR REPLACE FUNCTION public.classify_mood_v1(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_lower text;
BEGIN
  -- Normalize text for matching
  v_lower := lower(coalesce(p_text, ''));
  
  -- ==========================================================================
  -- POSITIVE MOODS (check first - we want to catch positivity)
  -- ==========================================================================
  
  -- JOY: happiness, celebration, excitement
  IF v_lower ~ '\m(happy|joy|excited|amazing|wonderful|fantastic|great|awesome|love it|best day|celebrate|yay|woo|haha|lol|😊|😂|🎉)\M' THEN
    RETURN 'joy';
  END IF;
  
  -- LOVE: romantic feelings, deep affection
  IF v_lower ~ '\m(love|heart|crush|falling for|miss you|miss her|miss him|adore|soulmate|❤️|💕|🥰)\M' THEN
    RETURN 'love';
  END IF;
  
  -- HOPE: optimism, looking forward
  IF v_lower ~ '\m(hope|hopeful|optimistic|looking forward|can''t wait|excited about|future|dream|believe|🙏|✨)\M' THEN
    RETURN 'hope';
  END IF;
  
  -- GRATITUDE: thankfulness, appreciation
  IF v_lower ~ '\m(grateful|thankful|blessed|appreciate|thank|lucky|fortune|🙌)\M' THEN
    RETURN 'gratitude';
  END IF;
  
  -- CONFIDENCE: self-assurance, pride
  IF v_lower ~ '\m(proud|confident|strong|capable|nailed|crushed it|killed it|boss|winning|💪)\M' THEN
    RETURN 'confidence';
  END IF;
  
  -- ==========================================================================
  -- NEGATIVE MOODS
  -- ==========================================================================
  
  -- ANXIETY: worry, stress, fear
  IF v_lower ~ '\m(anxious|anxiety|worried|stress|nervous|panic|scared|fear|terrified|overwhelmed|can''t breathe|😰|😨)\M' THEN
    RETURN 'anxiety';
  END IF;
  
  -- SADNESS: grief, sorrow, depression
  IF v_lower ~ '\m(sad|depressed|crying|cry|tears|grief|mourning|heartbroken|devastated|miserable|empty|numb|😢|😭|💔)\M' THEN
    RETURN 'sadness';
  END IF;
  
  -- ANGER: frustration, rage
  IF v_lower ~ '\m(angry|furious|rage|hate|pissed|annoyed|frustrated|mad|fuck|shit|damn|🤬|😡)\M' THEN
    RETURN 'anger';
  END IF;
  
  -- LONELINESS: isolation, disconnection
  IF v_lower ~ '\m(lonely|alone|isolated|no one|nobody|left out|forgotten|invisible|miss people|😔)\M' THEN
    RETURN 'loneliness';
  END IF;
  
  -- SHAME: guilt, embarrassment
  IF v_lower ~ '\m(ashamed|shame|embarrassed|guilty|regret|stupid|idiot|fool|failure|worthless|😳)\M' THEN
    RETURN 'shame';
  END IF;
  
  -- ==========================================================================
  -- COMPLEX/NEUTRAL
  -- ==========================================================================
  
  -- DESIRE: wanting, longing, craving
  IF v_lower ~ '\m(want|wish|crave|need|desire|longing|yearn|if only|🤤)\M' THEN
    RETURN 'desire';
  END IF;
  
  -- Default: calm (neutral baseline when no strong signal)
  RETURN 'calm';
END;
$$;

-- =============================================================================
-- 3. UPDATE insert_confession TO TRACK MOOD METRICS
-- =============================================================================
-- This replaces the existing function with one that:
-- 1. Does normal confession insert (unchanged)
-- 2. Calls mood metrics RPC after successful insert
-- 3. Never fails the insert if mood tracking fails

CREATE OR REPLACE FUNCTION public.insert_confession(
  p_text TEXT,
  p_place_label TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
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
  v_mood_bucket TEXT;
  v_time_bucket TEXT;
  v_region TEXT;
  v_country_code TEXT;
  v_city_code TEXT;
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
  
  IF position('@' IN v_text) > 0 THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  IF v_text ~* 'https?://' OR v_text ~* '\mwww\.' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  IF v_text ~* '\.(com|net|org|no|io|co|app)\M' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  -- B) Phone-like sequences
  
  v_digits_only := regexp_replace(v_text, '[^0-9]', '', 'g');
  
  IF length(v_digits_only) >= 8 THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  IF v_text ~ '\+\s*[0-9]' THEN
    RAISE EXCEPTION 'CONTENT_BLOCKED: Please keep it abstract. This looks like it might identify a real person.';
  END IF;
  
  -- C) Real-name pattern
  
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
  -- INSERT CONFESSION
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
  
  -- ==========================================================================
  -- MOOD METRICS TRACKING (fire-and-forget, never fail the insert)
  -- ==========================================================================
  BEGIN
    -- Classify mood from text (never logged!)
    v_mood_bucket := public.classify_mood_v1(v_text);
    
    -- Get time bucket from current hour (server time)
    v_time_bucket := public.get_time_bucket(EXTRACT(HOUR FROM now())::integer);
    
    -- Normalize geo (NULL -> 'Unknown')
    v_region := COALESCE(NULLIF(TRIM(p_region), ''), 'Unknown');
    v_country_code := COALESCE(NULLIF(TRIM(p_country_code), ''), 'Unknown');
    v_city_code := COALESCE(NULLIF(TRIM(p_city_code), ''), 'Unknown');
    
    -- Increment mood metric (atomic upsert)
    PERFORM public.rpc_increment_confession_metric(
      current_date,      -- p_date
      v_time_bucket,     -- p_time_bucket
      v_region,          -- p_region
      v_country_code,    -- p_country_code
      v_city_code,       -- p_city_code
      v_mood_bucket,     -- p_mood_bucket
      1                  -- p_increment
    );
  EXCEPTION WHEN OTHERS THEN
    -- Log error but DON'T fail the confession insert
    -- IMPORTANT: Never log the confession text!
    RAISE WARNING 'Mood metrics tracking failed for confession %: %', v_inserted_id, SQLERRM;
  END;
  
  -- ==========================================================================
  -- RETURN
  -- ==========================================================================
  
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
-- 4. GRANTS (same as before)
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.insert_confession(text, text, double precision, double precision, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.insert_confession(text, text, double precision, double precision, text, text, text, text) TO authenticated;

-- Helper functions are internal, no public grants needed
GRANT EXECUTE ON FUNCTION public.get_time_bucket(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.classify_mood_v1(text) TO service_role;

-- =============================================================================
-- 5. NOTIFY POSTGREST
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- DEV TEST NOTE
-- =============================================================================
-- To test mood metrics tracking:
--
-- 1. Post a confession from the app (or via SQL):
--    SELECT * FROM public.insert_confession(
--      'I feel so happy today!',
--      NULL,
--      59.91, 10.75,
--      'Europe', 'OSL', 'Norway', 'NO'
--    );
--
-- 2. Check confession_metrics_daily for today's date:
--    SELECT * FROM public.confession_metrics_daily 
--    WHERE date = current_date 
--    ORDER BY created_at DESC;
--
-- 3. You should see a row with:
--    - mood_bucket = 'joy' (matched "happy")
--    - time_bucket = based on current hour
--    - region/country_code/city_code from the request
--    - count = 1 (or higher if you've posted multiple)
--
-- 4. Test mood classification directly:
--    SELECT public.classify_mood_v1('I feel so anxious about tomorrow');
--    -- Should return: 'anxiety'
--
--    SELECT public.classify_mood_v1('Missing my family');
--    -- Should return: 'loneliness'
--
--    SELECT public.classify_mood_v1('Just had a normal day');
--    -- Should return: 'calm' (default)
