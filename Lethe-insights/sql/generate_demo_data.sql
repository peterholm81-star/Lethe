-- ============================================================
-- LETHE INSIGHTS: DEMO DATA GENERATOR
-- ============================================================
-- 
-- PURPOSE: Generate realistic demo data for investor presentations
-- SAFETY: All data marked with is_demo = true
-- CLEANUP: DELETE FROM ... WHERE is_demo = true
--
-- RUN THIS IN SUPABASE SQL EDITOR
-- ============================================================

-- ============================================================
-- STEP 0: Ensure tables exist with required columns
-- ============================================================

-- Add is_demo column to confessions if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'confessions' AND column_name = 'is_demo'
  ) THEN
    ALTER TABLE confessions ADD COLUMN is_demo boolean DEFAULT false;
  END IF;
END $$;

-- Add intent column to confessions if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'confessions' AND column_name = 'intent'
  ) THEN
    ALTER TABLE confessions ADD COLUMN intent text;
  END IF;
END $$;

-- Add region column to confessions if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'confessions' AND column_name = 'region'
  ) THEN
    ALTER TABLE confessions ADD COLUMN region text;
  END IF;
END $$;

-- Add language column to confessions if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'confessions' AND column_name = 'language'
  ) THEN
    ALTER TABLE confessions ADD COLUMN language text DEFAULT 'en';
  END IF;
END $$;

-- Create daily_metrics table if not exists
CREATE TABLE IF NOT EXISTS daily_metrics (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  metric_date date NOT NULL,
  region text,
  city text,
  session_count integer DEFAULT 0,
  reader_count integer DEFAULT 0,
  post_count integer DEFAULT 0,
  post_attempts integer DEFAULT 0,
  post_success integer DEFAULT 0,
  post_reject integer DEFAULT 0,
  is_demo boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(metric_date, region, city)
);

-- Create demo_events table for world events
CREATE TABLE IF NOT EXISTS demo_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_name text NOT NULL,
  event_date date NOT NULL,
  event_type text,
  description text,
  is_demo boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- STEP 1: Clean up existing demo data
-- ============================================================

DELETE FROM confessions WHERE is_demo = true;
DELETE FROM daily_metrics WHERE is_demo = true;
DELETE FROM demo_events WHERE is_demo = true;

-- ============================================================
-- STEP 2: Generate demo confessions (800-1200 over 30 days)
-- ============================================================

-- Sample confession texts (anonymous, ephemeral tone)
WITH confession_templates AS (
  SELECT unnest(ARRAY[
    -- Curiosity
    'I open this app just to read what others are afraid to say.',
    'I wonder if anyone has felt exactly what I feel right now.',
    'Sometimes I scroll here hoping to find someone like me.',
    'I came here to see if my thoughts are normal.',
    'I read every post wondering who these people really are.',
    'I keep coming back to see if the world is as broken as I think.',
    
    -- Loneliness
    'I haven''t had a real conversation in weeks.',
    'Nobody would notice if I disappeared for a month.',
    'I pretend to be busy so people don''t realize I have no one.',
    'The silence in my apartment is deafening tonight.',
    'I miss someone who doesn''t even know I exist.',
    'I talk to myself more than I talk to anyone else.',
    
    -- Desire
    'If no one knew, I would quit my job and disappear for a year.',
    'I fantasize about starting over in a city where nobody knows me.',
    'I want to tell them how I feel but I never will.',
    'I dream about a life I''m too scared to chase.',
    'I wish I could be someone else for just one day.',
    'There''s a version of me that only exists in my head.',
    
    -- Regret
    'I should have said something. Now it''s too late.',
    'Ten years ago I made a choice that still haunts me.',
    'I wrote something three times tonight but deleted it every time.',
    'I let the best thing in my life walk away.',
    'I was cruel to someone who didn''t deserve it.',
    'I keep replaying that moment wishing I''d done it differently.',
    
    -- Anger
    'I smile at people I secretly can''t stand.',
    'I''m so tired of pretending everything is fine.',
    'Sometimes I want to scream but I just nod and smile.',
    'I hate how much I care about what others think.',
    'I resent people who seem to have it all figured out.',
    'I''m angry at myself for not being braver.',
    
    -- Relief
    'I finally said no and it felt incredible.',
    'Writing this down makes it feel less heavy.',
    'I thought I was alone in this. I''m not.',
    'Just admitting it to strangers helps somehow.',
    'I don''t need anyone to fix it. I just needed to say it.',
    'This is the first time I''ve been honest about this.',
    
    -- Boredom
    'I''m here because I have nothing else to do.',
    'My life is fine. Just... unremarkably fine.',
    'I refresh this app like it''s going to change something.',
    'Nothing exciting has happened to me in months.',
    'I''m not sad, just... empty.',
    'I keep waiting for something to happen.',
    
    -- Mixed/Deep
    'I love someone who will never know.',
    'I''ve been keeping a secret for fifteen years.',
    'I don''t recognize who I''ve become.',
    'I said I was fine. I''m not fine.',
    'I make jokes because the truth is too heavy.',
    'I wonder if anyone reads these and thinks of me.',
    'I''m terrified of being ordinary.',
    'I pretend to be happy so well that I almost believe it.',
    'I have everything I wanted. Why do I feel nothing?',
    'I''m watching my life pass by like a spectator.',
    
    -- Norwegian
    'Jeg har ikke snakket med noen på flere dager.',
    'Jeg later som alt er bra. Det er det ikke.',
    'Noen ganger ønsker jeg bare å forsvinne.',
    'Jeg savner noen som ikke vet at jeg eksisterer.',
    
    -- French
    'Je fais semblant d''être heureux depuis si longtemps.',
    'Personne ne sait vraiment qui je suis.',
    'J''ai peur d''être seul pour toujours.',
    
    -- German
    'Ich habe seit Wochen mit niemandem richtig gesprochen.',
    'Manchmal fühle ich mich völlig unsichtbar.',
    'Ich tue so, als wäre alles in Ordnung.',
    
    -- Spanish
    'No recuerdo la última vez que fui verdaderamente feliz.',
    'Sonrío pero por dentro estoy gritando.',
    'Nadie sabe lo que realmente siento.'
  ]) AS text
),

-- Intent mapping for each confession
intent_mapping AS (
  SELECT 
    text,
    CASE 
      WHEN text ILIKE '%read%' OR text ILIKE '%scroll%' OR text ILIKE '%wonder%' OR text ILIKE '%curious%' THEN 'curiosity'
      WHEN text ILIKE '%alone%' OR text ILIKE '%lonely%' OR text ILIKE '%nobody%' OR text ILIKE '%silence%' OR text ILIKE '%miss%' THEN 'loneliness'
      WHEN text ILIKE '%want%' OR text ILIKE '%wish%' OR text ILIKE '%dream%' OR text ILIKE '%fantasize%' OR text ILIKE '%desire%' THEN 'desire'
      WHEN text ILIKE '%regret%' OR text ILIKE '%should have%' OR text ILIKE '%haunts%' OR text ILIKE '%deleted%' OR text ILIKE '%too late%' THEN 'regret'
      WHEN text ILIKE '%angry%' OR text ILIKE '%hate%' OR text ILIKE '%resent%' OR text ILIKE '%tired of%' OR text ILIKE '%scream%' THEN 'anger'
      WHEN text ILIKE '%relief%' OR text ILIKE '%finally%' OR text ILIKE '%helps%' OR text ILIKE '%honest%' OR text ILIKE '%less heavy%' THEN 'relief'
      WHEN text ILIKE '%bored%' OR text ILIKE '%nothing%' OR text ILIKE '%empty%' OR text ILIKE '%waiting%' OR text ILIKE '%fine%' THEN 'boredom'
      ELSE (ARRAY['curiosity', 'loneliness', 'desire', 'regret', 'anger', 'relief', 'boredom'])[1 + floor(random() * 7)::int]
    END AS intent
  FROM confession_templates
),

-- Language detection
language_mapping AS (
  SELECT 
    text,
    intent,
    CASE 
      WHEN text ~ '[æøåÆØÅ]' OR text ILIKE '%jeg%' OR text ILIKE '%ikke%' THEN 'no'
      WHEN text ~ '[éèêë]' OR text ILIKE '%je %' OR text ILIKE '%suis%' THEN 'fr'
      WHEN text ~ '[äöüß]' OR text ILIKE '%ich%' OR text ILIKE '%nicht%' THEN 'de'
      WHEN text ~ '[ñ¿¡]' OR text ILIKE '%estoy%' OR text ILIKE '%nadie%' THEN 'es'
      ELSE 'en'
    END AS language
  FROM intent_mapping
),

-- Generate ~1000 confessions over 30 days
generated_confessions AS (
  SELECT 
    lm.text,
    lm.intent,
    lm.language,
    -- Realistic time distribution (more evening/night posts)
    (CURRENT_DATE - (random() * 30)::int) + 
    (
      CASE 
        WHEN random() < 0.15 THEN (interval '6 hours' + random() * interval '4 hours')   -- Morning 6-10 (15%)
        WHEN random() < 0.35 THEN (interval '10 hours' + random() * interval '4 hours')  -- Midday 10-14 (20%)
        WHEN random() < 0.60 THEN (interval '18 hours' + random() * interval '4 hours')  -- Evening 18-22 (25%)
        ELSE (interval '22 hours' + random() * interval '5 hours')                        -- Night 22-03 (40%)
      END
    ) AS created_at,
    -- Region distribution
    (ARRAY['EU', 'US', 'UK', 'Nordics'])[
      CASE 
        WHEN random() < 0.35 THEN 1  -- EU 35%
        WHEN random() < 0.65 THEN 2  -- US 30%
        WHEN random() < 0.85 THEN 3  -- UK 20%
        ELSE 4                        -- Nordics 15%
      END
    ] AS region,
    true AS is_demo,
    gs.n AS row_num
  FROM language_mapping lm
  CROSS JOIN generate_series(1, 15) AS gs(n)  -- Multiply templates ~15x for ~1000 posts
  ORDER BY random()
  LIMIT 1000
)

INSERT INTO confessions (text, intent, language, region, created_at, is_demo)
SELECT text, intent, language, region, created_at, is_demo
FROM generated_confessions;

-- ============================================================
-- STEP 3: Generate daily_metrics (readers vs writers + friction)
-- ============================================================

INSERT INTO daily_metrics (
  metric_date, 
  region, 
  session_count, 
  reader_count, 
  post_count,
  post_attempts,
  post_success,
  post_reject,
  is_demo
)
SELECT 
  d::date AS metric_date,
  r.region,
  -- Sessions: 50-200 per region per day, with weekend boost
  (50 + floor(random() * 150) + 
    CASE WHEN EXTRACT(dow FROM d) IN (0, 6) THEN 30 ELSE 0 END
  )::int AS session_count,
  -- Readers: 80-90% of sessions
  (
    (50 + floor(random() * 150) + 
      CASE WHEN EXTRACT(dow FROM d) IN (0, 6) THEN 30 ELSE 0 END
    ) * (0.80 + random() * 0.10)
  )::int AS reader_count,
  -- Posts: count from confessions for this day/region
  COALESCE((
    SELECT COUNT(*) FROM confessions 
    WHERE is_demo = true 
      AND created_at::date = d::date 
      AND confessions.region = r.region
  ), 0)::int AS post_count,
  -- Post attempts: 1.5-2.5x actual posts (some abandon)
  (COALESCE((
    SELECT COUNT(*) FROM confessions 
    WHERE is_demo = true 
      AND created_at::date = d::date 
      AND confessions.region = r.region
  ), 0) * (1.5 + random()))::int AS post_attempts,
  -- Post success: actual posts
  COALESCE((
    SELECT COUNT(*) FROM confessions 
    WHERE is_demo = true 
      AND created_at::date = d::date 
      AND confessions.region = r.region
  ), 0)::int AS post_success,
  -- Post reject: 5-15% of attempts
  (COALESCE((
    SELECT COUNT(*) FROM confessions 
    WHERE is_demo = true 
      AND created_at::date = d::date 
      AND confessions.region = r.region
  ), 0) * (0.05 + random() * 0.10))::int AS post_reject,
  true AS is_demo
FROM generate_series(
  CURRENT_DATE - interval '30 days', 
  CURRENT_DATE, 
  interval '1 day'
) AS d
CROSS JOIN (
  SELECT unnest(ARRAY['EU', 'US', 'UK', 'Nordics']) AS region
) AS r
ON CONFLICT (metric_date, region, city) DO UPDATE SET
  session_count = EXCLUDED.session_count,
  reader_count = EXCLUDED.reader_count,
  post_count = EXCLUDED.post_count,
  post_attempts = EXCLUDED.post_attempts,
  post_success = EXCLUDED.post_success,
  post_reject = EXCLUDED.post_reject,
  is_demo = true;

-- ============================================================
-- STEP 4: Create demo world events
-- ============================================================

INSERT INTO demo_events (event_name, event_date, event_type, description, is_demo)
VALUES 
  ('Major News Event', CURRENT_DATE - interval '21 days', 'news', 'Significant global news story that increased engagement', true),
  ('Holiday Weekend', CURRENT_DATE - interval '14 days', 'holiday', 'Long weekend with increased evening activity', true),
  ('Global Incident', CURRENT_DATE - interval '7 days', 'incident', 'World event that sparked reflection and confessions', true);

-- Boost confessions around events (mark with higher engagement)
-- This is simulated by having more confessions already in those date ranges

-- ============================================================
-- STEP 5: Update get_pulse_metrics RPC to use correct columns
-- ============================================================

DROP FUNCTION IF EXISTS public.get_pulse_metrics();
DROP FUNCTION IF EXISTS public.get_pulse_metrics(text, text, date);

-- Parameterized version
CREATE OR REPLACE FUNCTION public.get_pulse_metrics(
  p_region text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  sessions_today integer,
  readers_today integer,
  posts_today integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(session_count), 0)::integer AS sessions_today,
    COALESCE(SUM(reader_count), 0)::integer AS readers_today,
    COALESCE(SUM(post_count), 0)::integer AS posts_today
  FROM daily_metrics
  WHERE metric_date = p_date
    AND (p_region IS NULL OR region = p_region)
    AND (p_city IS NULL OR city = p_city);
END;
$$;

-- No-arg wrapper
CREATE OR REPLACE FUNCTION public.get_pulse_metrics()
RETURNS TABLE (
  sessions_today integer,
  readers_today integer,
  posts_today integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.get_pulse_metrics(NULL, NULL, CURRENT_DATE);
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics() TO anon;
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics(text, text, date) TO anon;
GRANT EXECUTE ON FUNCTION public.get_pulse_metrics(text, text, date) TO authenticated;

-- ============================================================
-- STEP 6: Verify demo data
-- ============================================================

-- Count confessions by day
SELECT 
  created_at::date AS day,
  COUNT(*) AS confessions,
  COUNT(DISTINCT region) AS regions
FROM confessions 
WHERE is_demo = true
GROUP BY created_at::date
ORDER BY day DESC
LIMIT 10;

-- Count by intent
SELECT intent, COUNT(*) AS count
FROM confessions 
WHERE is_demo = true
GROUP BY intent
ORDER BY count DESC;

-- Count by language
SELECT language, COUNT(*) AS count
FROM confessions 
WHERE is_demo = true
GROUP BY language
ORDER BY count DESC;

-- Daily metrics summary
SELECT 
  metric_date,
  SUM(session_count) AS sessions,
  SUM(reader_count) AS readers,
  SUM(post_count) AS posts,
  SUM(post_attempts) AS attempts,
  SUM(post_reject) AS rejects
FROM daily_metrics
WHERE is_demo = true
GROUP BY metric_date
ORDER BY metric_date DESC
LIMIT 10;

-- Test PULSE RPC
SELECT * FROM public.get_pulse_metrics();

-- ============================================================
-- CLEANUP COMMANDS (run when needed):
-- ============================================================
-- DELETE FROM confessions WHERE is_demo = true;
-- DELETE FROM daily_metrics WHERE is_demo = true;
-- DELETE FROM demo_events WHERE is_demo = true;
-- ============================================================
