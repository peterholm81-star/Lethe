-- ============================================================
-- GENERATE DEMO DATA FOR TODAY
-- ============================================================
--
-- daily_metrics columns:
--   day_bucket, sessions, readers, post_attempts, post_success,
--   post_reject, reader_to_poster_ratio, reject_ratio, is_demo
--
-- confessions columns:
--   text, intent, language, region, created_at, is_demo
--
-- RUN ORDER:
--   1) sql/get_pulse_metrics.sql
--   2) sql/generate_today_demo.sql (this file)
-- ============================================================

-- ============================================================
-- STEP 1: Delete existing demo confessions for today
-- ============================================================
DELETE FROM confessions 
WHERE is_demo = true 
  AND created_at::date = CURRENT_DATE;

-- ============================================================
-- STEP 2: Insert demo confessions for today
-- Using NOW() at UTC to ensure they fall within "today"
-- ============================================================
INSERT INTO confessions (text, intent, language, region, created_at, is_demo)
VALUES
  -- Curiosity (8)
  ('I open this app just to read what others are afraid to say.', 'curiosity', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('I wonder if anyone has felt exactly what I feel right now.', 'curiosity', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('Sometimes I scroll here hoping to find someone like me.', 'curiosity', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true),
  ('I came here to see if my thoughts are normal.', 'curiosity', 'en', 'Nordics', (CURRENT_DATE + interval '13 hours')::timestamptz, true),
  ('I read every post wondering who these people really are.', 'curiosity', 'en', 'EU', (CURRENT_DATE + interval '14 hours')::timestamptz, true),
  ('I keep coming back to see if the world is as broken as I think.', 'curiosity', 'en', 'US', (CURRENT_DATE + interval '9 hours')::timestamptz, true),
  ('Just curious what strangers confess to.', 'curiosity', 'en', 'EU', (CURRENT_DATE + interval '8 hours')::timestamptz, true),
  ('I check this app every night before sleep.', 'curiosity', 'en', 'US', (CURRENT_DATE + interval '7 hours')::timestamptz, true),

  -- Regret (5)
  ('I should have said something. Now it is too late.', 'regret', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('Ten years ago I made a choice that still haunts me.', 'regret', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('I wrote something three times tonight but deleted it every time.', 'regret', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true),
  ('I let the best thing in my life walk away.', 'regret', 'en', 'Nordics', (CURRENT_DATE + interval '13 hours')::timestamptz, true),
  ('I keep replaying that moment wishing I had done it differently.', 'regret', 'en', 'EU', (CURRENT_DATE + interval '14 hours')::timestamptz, true),

  -- Loneliness (4)
  ('I have not had a real conversation in weeks.', 'loneliness', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('Nobody would notice if I disappeared for a month.', 'loneliness', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('The silence in my apartment is deafening tonight.', 'loneliness', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true),
  ('I miss someone who does not even know I exist.', 'loneliness', 'en', 'Nordics', (CURRENT_DATE + interval '13 hours')::timestamptz, true),

  -- Desire (4)
  ('If no one knew, I would quit my job and disappear for a year.', 'desire', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('I fantasize about starting over in a city where nobody knows me.', 'desire', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('I dream about a life I am too scared to chase.', 'desire', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true),
  ('There is a version of me that only exists in my head.', 'desire', 'en', 'Nordics', (CURRENT_DATE + interval '13 hours')::timestamptz, true),

  -- Relief (3)
  ('I finally said no and it felt incredible.', 'relief', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('Writing this down makes it feel less heavy.', 'relief', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('Just admitting it to strangers helps somehow.', 'relief', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true),

  -- Anger (3)
  ('I smile at people I secretly can not stand.', 'anger', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('I am so tired of pretending everything is fine.', 'anger', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('I resent people who seem to have it all figured out.', 'anger', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true),

  -- Boredom (3)
  ('I am here because I have nothing else to do.', 'boredom', 'en', 'EU', (CURRENT_DATE + interval '10 hours')::timestamptz, true),
  ('Nothing exciting has happened to me in months.', 'boredom', 'en', 'US', (CURRENT_DATE + interval '11 hours')::timestamptz, true),
  ('I refresh this app like it is going to change something.', 'boredom', 'en', 'UK', (CURRENT_DATE + interval '12 hours')::timestamptz, true);

-- Total: 30 confessions for today

-- ============================================================
-- STEP 3: Delete existing demo metrics for today
-- ============================================================
DELETE FROM daily_metrics 
WHERE day_bucket = CURRENT_DATE 
  AND is_demo = true;

-- ============================================================
-- STEP 4: Insert demo metrics for today
-- Using correct columns: sessions, readers, post_attempts, post_success, post_reject
-- ============================================================
INSERT INTO daily_metrics (
  day_bucket, 
  sessions, 
  readers, 
  post_attempts, 
  post_success, 
  post_reject, 
  reader_to_poster_ratio, 
  reject_ratio, 
  is_demo
)
VALUES (
  CURRENT_DATE,
  156,    -- sessions
  128,    -- readers (82% of sessions)
  38,     -- post_attempts
  30,     -- post_success (matches our 30 confessions)
  8,      -- post_reject
  4.27,   -- reader_to_poster_ratio (128/30)
  0.21,   -- reject_ratio (8/38)
  true
);

-- ============================================================
-- VERIFY RESULTS
-- ============================================================

-- Intent distribution for today
SELECT 
  intent,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 0) AS percent
FROM confessions
WHERE is_demo = true 
  AND created_at::date = CURRENT_DATE
  AND intent IS NOT NULL
GROUP BY intent
ORDER BY count DESC;

-- Total confessions for today
SELECT COUNT(*) AS total_confessions_today 
FROM confessions 
WHERE created_at::date = CURRENT_DATE;

-- Daily metrics for today
SELECT * FROM daily_metrics 
WHERE day_bucket = CURRENT_DATE;

-- Test PULSE RPC
SELECT * FROM public.get_pulse_metrics();
