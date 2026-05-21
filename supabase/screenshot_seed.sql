-- Lethe screenshot demo seed
-- ============================================================================
-- PURPOSE
--   Prepare the remote Supabase database for app/website screenshots.
--   Clears all existing confessions and inserts 29 curated, realistic ones:
--   25 spread across 6 global cities + 4 clustered near Melandsjø, Norway.
--
-- HOW TO RUN
--   Paste this entire file into:
--   Supabase Dashboard → SQL Editor → click Run
--   (SQL Editor runs as postgres role — bypasses RLS and the content filter.)
--
-- REVERSIBILITY
--   Running the script again fully resets the demo data.
--   No undo for the DELETE. Back up first if needed:
--     CREATE TABLE confessions_backup AS SELECT * FROM confessions;
--
-- SCHEMA (confirmed against current migrations)
--   confessions(
--     id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
--     text       TEXT NOT NULL CHECK (char_length(text) <= 120),
--     lat        DOUBLE PRECISION,
--     lng        DOUBLE PRECISION,
--     created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
--     expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '24 hours',
--     is_hidden  BOOLEAN DEFAULT false,
--     user_id    UUID  -- NULL for seeded data, fine
--   )
--
-- NEAR ME SCREENSHOT — Melandsjø, Hitra island, Norway
--   Set your device/browser location to: 63.5437, 8.4922
--   4 confessions are within ~200 m of that point.
--   Near Me auto-expand settles at 500 m (MAX_ATTEMPTS=3, MIN_RESULTS=10).
--   Label shown in app: "Listening in: Near you · 500 m"
--
-- WORLD FEED SCREENSHOT
--   Any city works. Feed shows all non-expired confessions globally,
--   ordered by created_at DESC. Freshest confessions are at the top.
--
-- WRITE SCREEN EXAMPLE (type or paste manually in the app):
--   "I would leave everything behind and start again somewhere quiet."
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Clear existing confessions
-- --------------------------------------------------------------------------
DELETE FROM confessions;

-- --------------------------------------------------------------------------
-- 2. Insert 29 curated demo confessions
--    Timestamps are relative to now() — always fresh when you run this.
-- --------------------------------------------------------------------------
INSERT INTO confessions (text, lat, lng, created_at, expires_at, is_hidden)
VALUES

  -- ========================================================================
  -- OSLO (59.9139, 10.7522)
  -- 5 confessions spread across the last 12 hours
  -- ========================================================================

  -- 12 min ago
  ('Sometimes I count how many real friends I have and stop before I finish.',
   59.9142, 10.7530,
   now() - interval '12 minutes',
   now() - interval '12 minutes' + interval '24 hours',
   false),

  -- 28 min ago
  ('I want a different life. Not a better one. Just different.',
   59.9135, 10.7514,
   now() - interval '28 minutes',
   now() - interval '28 minutes' + interval '24 hours',
   false),

  -- 1h 50 min ago
  ('I smiled and said I was fine. I''ve been doing it so long I believe it myself.',
   59.9151, 10.7541,
   now() - interval '110 minutes',
   now() - interval '110 minutes' + interval '24 hours',
   false),

  -- 5h 30 min ago
  ('I miss someone who doesn''t miss me. I think that''s the whole story.',
   59.9122, 10.7498,
   now() - interval '330 minutes',
   now() - interval '330 minutes' + interval '24 hours',
   false),

  -- 11h 40 min ago
  ('I keep the light on because sleeping feels too much like giving up.',
   59.9161, 10.7555,
   now() - interval '700 minutes',
   now() - interval '700 minutes' + interval '24 hours',
   false),

  -- ========================================================================
  -- NEW YORK (40.7128, -74.0060)
  -- 4 confessions spread across the last 17 hours
  -- ========================================================================

  -- 35 min ago
  ('Every morning I think about quitting. Every morning I don''t.',
   40.7135, -74.0052,
   now() - interval '35 minutes',
   now() - interval '35 minutes' + interval '24 hours',
   false),

  -- 2h 40 min ago
  ('I''ve been in this city two years and I''ve never felt more alone.',
   40.7120, -74.0068,
   now() - interval '160 minutes',
   now() - interval '160 minutes' + interval '24 hours',
   false),

  -- 8h 45 min ago
  ('I keep a go-bag packed. Not because I travel. Because I might.',
   40.7145, -74.0045,
   now() - interval '525 minutes',
   now() - interval '525 minutes' + interval '24 hours',
   false),

  -- 16h 20 min ago
  ('The version of me they all believe in isn''t really me.',
   40.7110, -74.0080,
   now() - interval '980 minutes',
   now() - interval '980 minutes' + interval '24 hours',
   false),

  -- ========================================================================
  -- LONDON (51.5074, -0.1278)
  -- 4 confessions spread across the last 18 hours
  -- ========================================================================

  -- 45 min ago
  ('I told them I was happy here. Mostly I was just tired of trying to leave.',
   51.5082, -0.1269,
   now() - interval '45 minutes',
   now() - interval '45 minutes' + interval '24 hours',
   false),

  -- 3h 30 min ago
  ('Some days I go to the park just to be around people who don''t know me.',
   51.5068, -0.1290,
   now() - interval '210 minutes',
   now() - interval '210 minutes' + interval '24 hours',
   false),

  -- 10h 15 min ago
  ('I''m more careful about who I become than anyone I know.',
   51.5079, -0.1262,
   now() - interval '615 minutes',
   now() - interval '615 minutes' + interval '24 hours',
   false),

  -- 17h 50 min ago
  ('I cry in the shower sometimes. It''s the one place I''m allowed.',
   51.5060, -0.1295,
   now() - interval '1070 minutes',
   now() - interval '1070 minutes' + interval '24 hours',
   false),

  -- ========================================================================
  -- PARIS (48.8566, 2.3522)
  -- 4 confessions — includes 1 French-language confession
  -- ========================================================================

  -- 1h 10 min ago
  ('Je n''aime plus la personne que j''étais. Ça me fait peur.',
   48.8575, 2.3535,
   now() - interval '70 minutes',
   now() - interval '70 minutes' + interval '24 hours',
   false),

  -- 4h 15 min ago
  ('I spent all of Tuesday pretending to work. It felt like freedom.',
   48.8558, 2.3510,
   now() - interval '255 minutes',
   now() - interval '255 minutes' + interval '24 hours',
   false),

  -- 12h 30 min ago
  ('Sometimes I think I chose this life just because it was expected.',
   48.8580, 2.3548,
   now() - interval '750 minutes',
   now() - interval '750 minutes' + interval '24 hours',
   false),

  -- 18h 30 min ago
  ('Some things I''ve never said out loud. This is the closest I''ll get.',
   48.8552, 2.3498,
   now() - interval '1110 minutes',
   now() - interval '1110 minutes' + interval '24 hours',
   false),

  -- ========================================================================
  -- BERLIN (52.5200, 13.4050)
  -- 4 confessions — includes 1 German-language confession
  -- ========================================================================

  -- 1h 25 min ago
  ('Ich liebe meine Arbeit nicht mehr. Ich tu nur so, weil ich nicht weiß, was sonst.',
   52.5215, 13.4068,
   now() - interval '85 minutes',
   now() - interval '85 minutes' + interval '24 hours',
   false),

  -- 6h 20 min ago
  ('There''s a version of me that never left and I wonder about them.',
   52.5185, 13.4032,
   now() - interval '380 minutes',
   now() - interval '380 minutes' + interval '24 hours',
   false),

  -- 14h 10 min ago
  ('I don''t want to be remembered. I just want to feel like it mattered.',
   52.5208, 13.4075,
   now() - interval '850 minutes',
   now() - interval '850 minutes' + interval '24 hours',
   false),

  -- 20h 15 min ago
  ('I buy things I don''t need to feel like someone with a life.',
   52.5192, 13.4045,
   now() - interval '1215 minutes',
   now() - interval '1215 minutes' + interval '24 hours',
   false),

  -- ========================================================================
  -- TOKYO (35.6762, 139.6503)
  -- 4 confessions spread across the last 22 hours
  -- ========================================================================

  -- 2h 15 min ago
  ('I smile at people on the train. I wonder if they know how much it costs me.',
   35.6775, 139.6518,
   now() - interval '135 minutes',
   now() - interval '135 minutes' + interval '24 hours',
   false),

  -- 7h 10 min ago
  ('I''ve been thinking about one conversation for three years.',
   35.6750, 139.6488,
   now() - interval '430 minutes',
   now() - interval '430 minutes' + interval '24 hours',
   false),

  -- 15h 45 min ago
  ('I am very good at seeming okay.',
   35.6768, 139.6512,
   now() - interval '945 minutes',
   now() - interval '945 minutes' + interval '24 hours',
   false),

  -- 21h 40 min ago
  ('I keep saying things will be different next year.',
   35.6748, 139.6495,
   now() - interval '1300 minutes',
   now() - interval '1300 minutes' + interval '24 hours',
   false),

  -- ========================================================================
  -- MELANDSJØ, NORWAY — Near Me cluster (Hitra island)
  -- Centre: 63.5437, 8.4922
  -- All 4 confessions within ~160 m of centre.
  -- Set device location to 63.5437, 8.4922 for Near Me screenshots.
  -- Near Me auto-expand settles at 500 m → shows all 4 confessions.
  -- ========================================================================

  -- 7 min ago · ~53 m NE of centre
  ('I moved here to escape something and I brought it with me.',
   63.5441, 8.4928,
   now() - interval '7 minutes',
   now() - interval '7 minutes' + interval '24 hours',
   false),

  -- 52 min ago · ~74 m SW of centre
  ('I told her everything once. I should have kept some of it.',
   63.5432, 8.4912,
   now() - interval '52 minutes',
   now() - interval '52 minutes' + interval '24 hours',
   false),

  -- 3h 5 min ago · ~126 m NE of centre
  ('I''m so tired of pretending this is the life I chose.',
   63.5447, 8.4934,
   now() - interval '185 minutes',
   now() - interval '185 minutes' + interval '24 hours',
   false),

  -- 9h 20 min ago · ~155 m SW of centre
  ('I almost left. I would have been happier. I stayed anyway.',
   63.5425, 8.4906,
   now() - interval '560 minutes',
   now() - interval '560 minutes' + interval '24 hours',
   false);

COMMIT;

-- --------------------------------------------------------------------------
-- Verification query — run separately after commit to confirm row counts
-- --------------------------------------------------------------------------
-- SELECT
--   CASE
--     WHEN lat BETWEEN 59.90 AND 59.93 THEN 'Oslo'
--     WHEN lat BETWEEN 40.70 AND 40.72 THEN 'New York'
--     WHEN lat BETWEEN 51.50 AND 51.52 THEN 'London'
--     WHEN lat BETWEEN 48.85 AND 48.87 THEN 'Paris'
--     WHEN lat BETWEEN 52.51 AND 52.53 THEN 'Berlin'
--     WHEN lat BETWEEN 35.67 AND 35.68 THEN 'Tokyo'
--     WHEN lat BETWEEN 63.54 AND 63.55 THEN 'Melandsjø'
--     ELSE 'unknown'
--   END AS city,
--   count(*) AS count
-- FROM confessions
-- WHERE expires_at > now()
-- GROUP BY 1
-- ORDER BY 1;
