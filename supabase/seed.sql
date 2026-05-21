-- Lethe local development seed
-- ============================================================================
-- PURPOSE
--   Populated automatically after: npx supabase db reset
--   (db reset wipes the database first, so no DELETE is needed here.)
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
--     user_id    UUID  -- NULL for seeded data
--   )
--
-- NEAR ME TESTING — Melandsjø, Hitra island, Norway
--   Device / browser location: 63.5437, 8.4922
--   4 confessions within ~160 m of that point.
--   App auto-expand settles at 500 m.
--   Label: "Listening in: Near you · 500 m"
--
-- WRITE SCREEN EXAMPLE (paste manually):
--   "I would leave everything behind and start again somewhere quiet."
-- ============================================================================

INSERT INTO confessions (text, lat, lng, created_at, expires_at, is_hidden)
VALUES

  -- ========================================================================
  -- OSLO (59.9139, 10.7522)
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
  -- Includes 1 French-language confession
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
  -- Includes 1 German-language confession
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
  -- Set device location to 63.5437, 8.4922 for Near Me testing/screenshots.
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
