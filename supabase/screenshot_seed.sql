-- Lethe screenshot seed — v2 (120 confessions, non-destructive)
-- ============================================================================
-- PURPOSE
--   Insert 120 realistic confessions into the Supabase database for
--   app screenshots, mockups, and press assets.
--
-- SAFETY
--   This script is fully NON-DESTRUCTIVE.
--   · It does NOT delete any existing confessions.
--   · Each row is inserted only if no confession with that exact text
--     already exists in the table (idempotent on re-runs).
--   · Real user confessions are never touched.
--
-- HOW TO RUN
--   1. Open Supabase Dashboard → SQL Editor → New query
--      https://supabase.com/dashboard/project/<your-project>/sql/new
--   2. Paste this entire file and click Run.
--   3. The script runs as the postgres role (bypasses RLS / content filter).
--   4. It is safe to run multiple times — duplicate seed rows are skipped.
--
-- SCHEMA
--   confessions(id, text, lat, lng, created_at, expires_at, is_hidden, user_id)
--   text: max 120 chars. geo fields (region, country_code, city_code): NULL OK.
--
-- SCREENSHOT GUIDE
--   WORLD FEED   — any device location; shows all confessions ordered newest first
--   NEAR ME      — set device location to 63.5437, 8.4922 (Melandsjø, Norway)
--                  8 confessions cluster within ~200 m; app auto-expands to 500 m
--   SOMEWHERE    — set device location to any city below, filter by region
--   WRITE SCREEN — type or paste: "I moved here to escape something."
--
-- LANGUAGE DISTRIBUTION
--   English ~85 % · Norwegian ~6 % · German ~4 % · French ~4 % · Spanish ~5 %
--
-- EMOTIONAL DISTRIBUTION
--   ~70 % emotionally normal/human  (loneliness, relationships, work, mundane)
--   ~20 % more intense/edgy         (anger, sexuality, politics, dark thoughts)
--   ~10 % weird/funny/awkward       (mundane-funny, self-aware, random)
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- Insert 120 curated confessions — skips any row whose text already exists.
--
-- HOW DEDUPLICATION WORKS
--   The outer WHERE NOT EXISTS checks each candidate row against the live
--   confessions table before inserting. If a confession with the same text
--   is already present (from a prior run of this seed, or posted by a real
--   user), that row is silently skipped. No existing data is ever modified.
--
-- TYPE CASTS
--   Only the first VALUES row carries explicit type casts. PostgreSQL uses
--   those to type the entire derived table; subsequent rows inherit them.
--
-- TIMESTAMPS
--   created_at / expires_at are relative to now() at transaction start,
--   so the feed appears fresh every time you run this script.
-- --------------------------------------------------------------------------

INSERT INTO confessions (text, lat, lng, created_at, expires_at, is_hidden)
SELECT v.text, v.lat, v.lng, v.created_at, v.expires_at, v.is_hidden
FROM (VALUES

  -- ========================================================================
  -- OSLO (59.9139, 10.7522) — 10 confessions · includes Norwegian
  -- First row carries type casts for the whole table.
  -- ========================================================================

  ('I still check her Spotify sometimes.'::text,
   59.9142::double precision, 10.7530::double precision,
   (now() - interval '3 minutes')::timestamptz,
   (now() - interval '3 minutes'   + interval '24 hours')::timestamptz,
   false::boolean),

  ('My parents don''t know I smoke. I''m 34.',
   59.9135, 10.7514,
   now() - interval '11 minutes',
   now() - interval '11 minutes'  + interval '24 hours', false),

  ('Jeg håper hun tenker på meg like mye som jeg tenker på henne.',
   59.9151, 10.7541,
   now() - interval '25 minutes',
   now() - interval '25 minutes'  + interval '24 hours', false),

  ('I passed up a job I actually wanted. Still don''t know why.',
   59.9122, 10.7498,
   now() - interval '58 minutes',
   now() - interval '58 minutes'  + interval '24 hours', false),

  ('She texted me first and I waited two days to reply. I don''t know what I was trying to prove.',
   59.9161, 10.7555,
   now() - interval '105 minutes',
   now() - interval '105 minutes' + interval '24 hours', false),

  ('Jeg er lei meg for ting jeg aldri har sagt unnskyld for.',
   59.9130, 10.7510,
   now() - interval '140 minutes',
   now() - interval '140 minutes' + interval '24 hours', false),

  ('I''ve been faking my salary to keep up with my friends.',
   59.9148, 10.7535,
   now() - interval '190 minutes',
   now() - interval '190 minutes' + interval '24 hours', false),

  ('I think I peaked at 23.',
   59.9138, 10.7520,
   now() - interval '270 minutes',
   now() - interval '270 minutes' + interval '24 hours', false),

  ('sometimes i stay awake just to avoid tomorrow',
   59.9125, 10.7545,
   now() - interval '400 minutes',
   now() - interval '400 minutes' + interval '24 hours', false),

  ('Jeg har ikke sagt at jeg er glad i familien min på mange år. Det sitter fast i halsen.',
   59.9155, 10.7560,
   now() - interval '495 minutes',
   now() - interval '495 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- NEW YORK (40.7128, -74.0060) — 12 confessions
  -- ========================================================================

  ('I make enough money to be comfortable and it hasn''t helped at all.',
   40.7135, -74.0052,
   now() - interval '6 minutes',
   now() - interval '6 minutes'   + interval '24 hours', false),

  ('I google my ex''s name sometimes to see if anything comes up.',
   40.7120, -74.0068,
   now() - interval '19 minutes',
   now() - interval '19 minutes'  + interval '24 hours', false),

  ('I''m kind to everyone at work. I don''t like most of them.',
   40.7145, -74.0045,
   now() - interval '38 minutes',
   now() - interval '38 minutes'  + interval '24 hours', false),

  ('I told my therapist I was doing better. I lied.',
   40.7110, -74.0080,
   now() - interval '70 minutes',
   now() - interval '70 minutes'  + interval '24 hours', false),

  ('I find people who are passionately wrong about things kind of attractive.',
   40.7132, -74.0055,
   now() - interval '125 minutes',
   now() - interval '125 minutes' + interval '24 hours', false),

  ('I would vote differently if no one would ever find out.',
   40.7128, -74.0062,
   now() - interval '200 minutes',
   now() - interval '200 minutes' + interval '24 hours', false),

  ('I eat alone on purpose. I prefer it.',
   40.7118, -74.0072,
   now() - interval '280 minutes',
   now() - interval '280 minutes' + interval '24 hours', false),

  ('Sometimes I think I moved here to punish myself.',
   40.7141, -74.0048,
   now() - interval '330 minutes',
   now() - interval '330 minutes' + interval '24 hours', false),

  ('I got a promotion and my first feeling was dread.',
   40.7126, -74.0058,
   now() - interval '420 minutes',
   now() - interval '420 minutes' + interval '24 hours', false),

  ('I''ve fantasized about calling in sick for a week and just staying in bed.',
   40.7113, -74.0075,
   now() - interval '555 minutes',
   now() - interval '555 minutes' + interval '24 hours', false),

  ('My landlord raised my rent again. I smiled and said okay.',
   40.7138, -74.0043,
   now() - interval '700 minutes',
   now() - interval '700 minutes' + interval '24 hours', false),

  ('I wish I could disappear for like six months and come back when things are easier.',
   40.7122, -74.0066,
   now() - interval '800 minutes',
   now() - interval '800 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- LONDON (51.5074, -0.1278) — 10 confessions
  -- ========================================================================

  ('I pretend to like football. I''ve been doing it for years.',
   51.5082, -0.1269,
   now() - interval '8 minutes',
   now() - interval '8 minutes'   + interval '24 hours', false),

  ('I once reported a colleague for something I also do.',
   51.5068, -0.1290,
   now() - interval '31 minutes',
   now() - interval '31 minutes'  + interval '24 hours', false),

  ('sometimes I sit in my car after work for 20 minutes before going in',
   51.5079, -0.1262,
   now() - interval '55 minutes',
   now() - interval '55 minutes'  + interval '24 hours', false),

  ('I send my mum a text every Sunday. It''s the most we talk.',
   51.5060, -0.1295,
   now() - interval '85 minutes',
   now() - interval '85 minutes'  + interval '24 hours', false),

  ('I think most people are pretending more than they admit.',
   51.5075, -0.1275,
   now() - interval '160 minutes',
   now() - interval '160 minutes' + interval '24 hours', false),

  ('I drank too much last night and said something true by accident.',
   51.5065, -0.1285,
   now() - interval '230 minutes',
   now() - interval '230 minutes' + interval '24 hours', false),

  ('I keep fantasizing about quitting and moving somewhere no one knows my name.',
   51.5085, -0.1265,
   now() - interval '320 minutes',
   now() - interval '320 minutes' + interval '24 hours', false),

  ('I haven''t cried in two years. I''m starting to wonder if something is broken.',
   51.5070, -0.1280,
   now() - interval '430 minutes',
   now() - interval '430 minutes' + interval '24 hours', false),

  ('I''ve been pretending to be fine for so long I''ve lost track of what fine even means.',
   51.5078, -0.1272,
   now() - interval '585 minutes',
   now() - interval '585 minutes' + interval '24 hours', false),

  ('I told them I was happy here. Mostly I was just tired of trying to leave.',
   51.5062, -0.1292,
   now() - interval '720 minutes',
   now() - interval '720 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- PARIS (48.8566, 2.3522) — 10 confessions · includes French
  -- ========================================================================

  ('Je mens à mes amis sur à peu près tout.',
   48.8575, 2.3535,
   now() - interval '9 minutes',
   now() - interval '9 minutes'   + interval '24 hours', false),

  ('I kissed someone else and I haven''t stopped thinking about it.',
   48.8558, 2.3510,
   now() - interval '42 minutes',
   now() - interval '42 minutes'  + interval '24 hours', false),

  ('J''ai 31 ans et je ne sais toujours pas ce que je veux faire de ma vie.',
   48.8580, 2.3548,
   now() - interval '80 minutes',
   now() - interval '80 minutes'  + interval '24 hours', false),

  ('I think I got married too young. I think about it every day.',
   48.8565, 2.3528,
   now() - interval '175 minutes',
   now() - interval '175 minutes' + interval '24 hours', false),

  ('Je suis souvent en colère sans raison. Enfin, sans raison que j''avoue.',
   48.8552, 2.3498,
   now() - interval '250 minutes',
   now() - interval '250 minutes' + interval '24 hours', false),

  ('I have been living the same week on repeat for two years.',
   48.8578, 2.3542,
   now() - interval '390 minutes',
   now() - interval '390 minutes' + interval '24 hours', false),

  ('Ma vie a l''air bien de l''extérieur. De l''intérieur c''est autre chose.',
   48.8560, 2.3518,
   now() - interval '525 minutes',
   now() - interval '525 minutes' + interval '24 hours', false),

  ('I spent 40 euros on a bottle of wine I drank alone. Highly recommend.',
   48.8570, 2.3532,
   now() - interval '680 minutes',
   now() - interval '680 minutes' + interval '24 hours', false),

  ('I told him I wasn''t ready. I think I was just scared.',
   48.8555, 2.3505,
   now() - interval '850 minutes',
   now() - interval '850 minutes' + interval '24 hours', false),

  ('Je n''appelle plus ma mère assez souvent. Je le sais.',
   48.8583, 2.3555,
   now() - interval '1060 minutes',
   now() - interval '1060 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- BERLIN (52.5200, 13.4050) — 10 confessions · includes German
  -- ========================================================================

  ('I ghosted someone who was actually really good for me.',
   52.5215, 13.4068,
   now() - interval '14 minutes',
   now() - interval '14 minutes'  + interval '24 hours', false),

  ('Ich stehe jeden Morgen auf und tue so, als wäre ich glücklich. Es ist anstrengend.',
   52.5185, 13.4032,
   now() - interval '47 minutes',
   now() - interval '47 minutes'  + interval '24 hours', false),

  ('I''ve been angry at my dad for fifteen years and never said it.',
   52.5208, 13.4075,
   now() - interval '95 minutes',
   now() - interval '95 minutes'  + interval '24 hours', false),

  ('Manchmal wünsche ich mir, einfach eine andere Person zu sein.',
   52.5192, 13.4045,
   now() - interval '170 minutes',
   now() - interval '170 minutes' + interval '24 hours', false),

  ('I think I need therapy but I keep talking myself out of booking it.',
   52.5220, 13.4080,
   now() - interval '260 minutes',
   now() - interval '260 minutes' + interval '24 hours', false),

  ('Ich vermisse meine Ex, aber nicht sie — eher die Version von mir, die ich bei ihr war.',
   52.5178, 13.4025,
   now() - interval '365 minutes',
   now() - interval '365 minutes' + interval '24 hours', false),

  ('I spent three hours looking at apartments in cities I will never move to.',
   52.5202, 13.4060,
   now() - interval '510 minutes',
   now() - interval '510 minutes' + interval '24 hours', false),

  ('Ich mag meine Freunde nicht mehr so sehr. Ich frage mich, wann das passiert ist.',
   52.5195, 13.4038,
   now() - interval '650 minutes',
   now() - interval '650 minutes' + interval '24 hours', false),

  ('I don''t want kids. I just don''t tell people because the conversation isn''t worth it.',
   52.5210, 13.4070,
   now() - interval '795 minutes',
   now() - interval '795 minutes' + interval '24 hours', false),

  ('Ich habe heute meinen Kollegen angelogen. Es war so einfach.',
   52.5188, 13.4028,
   now() - interval '990 minutes',
   now() - interval '990 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- TOKYO (35.6762, 139.6503) — 8 confessions
  -- ========================================================================

  ('I got drunk and texted someone I shouldn''t have. They didn''t reply. Good.',
   35.6775, 139.6518,
   now() - interval '17 minutes',
   now() - interval '17 minutes'  + interval '24 hours', false),

  ('I''ve been avoiding a conversation for six months. I will continue to do so.',
   35.6750, 139.6488,
   now() - interval '52 minutes',
   now() - interval '52 minutes'  + interval '24 hours', false),

  ('I told my parents I was happy with my job. I am not.',
   35.6768, 139.6512,
   now() - interval '115 minutes',
   now() - interval '115 minutes' + interval '24 hours', false),

  ('I cried on the subway and no one noticed. Or they did and just didn''t say anything.',
   35.6758, 139.6498,
   now() - interval '205 minutes',
   now() - interval '205 minutes' + interval '24 hours', false),

  ('I have a box of things from my last relationship that I haven''t opened or thrown away.',
   35.6780, 139.6525,
   now() - interval '310 minutes',
   now() - interval '310 minutes' + interval '24 hours', false),

  ('I''m 28 and I feel like I missed something everyone else got told.',
   35.6745, 139.6480,
   now() - interval '460 minutes',
   now() - interval '460 minutes' + interval '24 hours', false),

  ('I am very good at seeming okay.',
   35.6762, 139.6503,
   now() - interval '560 minutes',
   now() - interval '560 minutes' + interval '24 hours', false),

  ('I keep saying things will be different next year.',
   35.6770, 139.6515,
   now() - interval '715 minutes',
   now() - interval '715 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- STOCKHOLM (59.3293, 18.0686) — 6 confessions
  -- ========================================================================

  ('I haven''t told anyone about this. Not sure why I''m saying it here.',
   59.3295, 18.0690,
   now() - interval '21 minutes',
   now() - interval '21 minutes'  + interval '24 hours', false),

  ('I''m in a good relationship. I''m still a little unhappy. I think that''s just me.',
   59.3288, 18.0680,
   now() - interval '75 minutes',
   now() - interval '75 minutes'  + interval '24 hours', false),

  ('I turned down something good because I was afraid I''d succeed.',
   59.3300, 18.0695,
   now() - interval '230 minutes',
   now() - interval '230 minutes' + interval '24 hours', false),

  ('I ate an entire pizza alone and it was honestly one of the better nights this month.',
   59.3282, 18.0672,
   now() - interval '380 minutes',
   now() - interval '380 minutes' + interval '24 hours', false),

  ('I check social media for updates on someone I no longer talk to. Old habit.',
   59.3292, 18.0685,
   now() - interval '580 minutes',
   now() - interval '580 minutes' + interval '24 hours', false),

  ('I spend Sunday evenings being anxious about Monday. Every Sunday.',
   59.3285, 18.0678,
   now() - interval '810 minutes',
   now() - interval '810 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- MADRID (40.4168, -3.7038) — 6 confessions · includes Spanish
  -- ========================================================================

  ('No sé si quiero a mi novio o solo tengo miedo de estar sola.',
   40.4172, -3.7035,
   now() - interval '32 minutes',
   now() - interval '32 minutes'  + interval '24 hours', false),

  ('I skipped my cousin''s wedding. I told them I was sick.',
   40.4162, -3.7042,
   now() - interval '135 minutes',
   now() - interval '135 minutes' + interval '24 hours', false),

  ('A veces pienso en dejarlo todo y viajar sola sin decirle a nadie adónde voy.',
   40.4175, -3.7030,
   now() - interval '275 minutes',
   now() - interval '275 minutes' + interval '24 hours', false),

  ('I flirt with my coworker. We both pretend it''s nothing.',
   40.4165, -3.7040,
   now() - interval '420 minutes',
   now() - interval '420 minutes' + interval '24 hours', false),

  ('Me arrepiento de haberle dicho que lo amaba primero.',
   40.4168, -3.7036,
   now() - interval '625 minutes',
   now() - interval '625 minutes' + interval '24 hours', false),

  ('Sometimes I want to be invisible. Not dead. Just... unaccountable for a while.',
   40.4158, -3.7045,
   now() - interval '945 minutes',
   now() - interval '945 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- SYDNEY (-33.8688, 151.2093) — 6 confessions
  -- ========================================================================

  ('I still have my ex''s Netflix password. We broke up two years ago.',
   -33.8685, 151.2098,
   now() - interval '44 minutes',
   now() - interval '44 minutes'  + interval '24 hours', false),

  ('I said I was ''exploring career options''. I got laid off.',
   -33.8692, 151.2090,
   now() - interval '150 minutes',
   now() - interval '150 minutes' + interval '24 hours', false),

  ('I don''t miss her. I miss feeling like someone cared where I was.',
   -33.8680, 151.2100,
   now() - interval '295 minutes',
   now() - interval '295 minutes' + interval '24 hours', false),

  ('I went to therapy for six months and told the therapist everything was fine.',
   -33.8695, 151.2085,
   now() - interval '440 minutes',
   now() - interval '440 minutes' + interval '24 hours', false),

  ('It''s 2am and I''m reading other people''s confessions instead of sleeping. Hi.',
   -33.8688, 151.2093,
   now() - interval '670 minutes',
   now() - interval '670 minutes' + interval '24 hours', false),

  ('I''ve been pretending to be more confident than I am since about 2017. I can''t stop.',
   -33.8682, 151.2096,
   now() - interval '1005 minutes',
   now() - interval '1005 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- SÃO PAULO (-23.5505, -46.6333) — 6 confessions · includes Spanish
  -- ========================================================================

  ('I send money to my family every month. They don''t know how little I have left.',
   -23.5502, -46.6338,
   now() - interval '36 minutes',
   now() - interval '36 minutes'  + interval '24 hours', false),

  ('I lie about how much I earn to seem like I have my life together.',
   -23.5510, -46.6328,
   now() - interval '185 minutes',
   now() - interval '185 minutes' + interval '24 hours', false),

  ('I work so hard and I still feel like I''m behind.',
   -23.5498, -46.6342,
   now() - interval '340 minutes',
   now() - interval '340 minutes' + interval '24 hours', false),

  ('I moved countries for a relationship. The relationship ended. I stayed.',
   -23.5508, -46.6325,
   now() - interval '495 minutes',
   now() - interval '495 minutes' + interval '24 hours', false),

  ('I''ve been angry for so long it just feels like my personality now.',
   -23.5515, -46.6330,
   now() - interval '750 minutes',
   now() - interval '750 minutes' + interval '24 hours', false),

  ('A veces me pregunto si me conozco realmente o solo me cuento cosas.',
   -23.5505, -46.6333,
   now() - interval '1040 minutes',
   now() - interval '1040 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- AMSTERDAM (52.3676, 4.9041) — 6 confessions
  -- ========================================================================

  ('I kissed a stranger at a party and thought about it for weeks.',
   52.3680, 4.9045,
   now() - interval '27 minutes',
   now() - interval '27 minutes'  + interval '24 hours', false),

  ('I''ve been sober for three months and told no one because I don''t want to jinx it.',
   52.3672, 4.9038,
   now() - interval '165 minutes',
   now() - interval '165 minutes' + interval '24 hours', false),

  ('I smoke weed every night and call it winding down. I know what it is.',
   52.3676, 4.9041,
   now() - interval '290 minutes',
   now() - interval '290 minutes' + interval '24 hours', false),

  ('I''ve started lying about small things just to see if anyone notices.',
   52.3682, 4.9048,
   now() - interval '395 minutes',
   now() - interval '395 minutes' + interval '24 hours', false),

  ('I think I''m the difficult one in my friend group. I just never say it out loud.',
   52.3670, 4.9035,
   now() - interval '545 minutes',
   now() - interval '545 minutes' + interval '24 hours', false),

  ('I turned 30 last week and felt absolutely nothing. Just another Tuesday.',
   52.3678, 4.9043,
   now() - interval '860 minutes',
   now() - interval '860 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- LOS ANGELES (34.0522, -118.2437) — 8 confessions
  -- ========================================================================

  ('I moved here to make it. Whatever that means.',
   34.0525, -118.2432,
   now() - interval '16 minutes',
   now() - interval '16 minutes'  + interval '24 hours', false),

  ('I didn''t go to the audition. I told myself I wasn''t ready. I was ready.',
   34.0515, -118.2442,
   now() - interval '60 minutes',
   now() - interval '60 minutes'  + interval '24 hours', false),

  ('I am exhausted by having to be interesting all the time.',
   34.0528, -118.2428,
   now() - interval '140 minutes',
   now() - interval '140 minutes' + interval '24 hours', false),

  ('I hate brunch. I go every week.',
   34.0518, -118.2438,
   now() - interval '225 minutes',
   now() - interval '225 minutes' + interval '24 hours', false),

  ('sometimes i look in the mirror and genuinely don''t recognize the person looking back',
   34.0522, -118.2435,
   now() - interval '330 minutes',
   now() - interval '330 minutes' + interval '24 hours', false),

  ('I''ve been writing the same screenplay for four years.',
   34.0512, -118.2445,
   now() - interval '475 minutes',
   now() - interval '475 minutes' + interval '24 hours', false),

  ('I think I want to move home. I''m too embarrassed to admit it didn''t work out.',
   34.0520, -118.2440,
   now() - interval '690 minutes',
   now() - interval '690 minutes' + interval '24 hours', false),

  ('I''ve met people more successful than me who are clearly miserable. Still jealous.',
   34.0526, -118.2430,
   now() - interval '855 minutes',
   now() - interval '855 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- BUENOS AIRES (-34.6037, -58.3816) — 4 confessions · includes Spanish
  -- ========================================================================

  ('I check the news every morning hoping something has changed. Nothing has.',
   -34.6033, -58.3820,
   now() - interval '43 minutes',
   now() - interval '43 minutes'  + interval '24 hours', false),

  ('Llevo meses diciendo que voy a cambiar algo. Ya no me lo creo.',
   -34.6040, -58.3812,
   now() - interval '195 minutes',
   now() - interval '195 minutes' + interval '24 hours', false),

  ('I''ve been in the same job for seven years and I''m afraid of what leaving would mean.',
   -34.6035, -58.3818,
   now() - interval '520 minutes',
   now() - interval '520 minutes' + interval '24 hours', false),

  ('No sé si extraño a la persona o solo la costumbre de tenerla cerca.',
   -34.6042, -58.3808,
   now() - interval '830 minutes',
   now() - interval '830 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- MUMBAI (19.0760, 72.8777) — 4 confessions
  -- ========================================================================

  ('I work twice as hard to be taken half as seriously. I don''t talk about it.',
   19.0764, 72.8782,
   now() - interval '28 minutes',
   now() - interval '28 minutes'  + interval '24 hours', false),

  ('I pretend not to hear things that are meant for me to hear.',
   19.0756, 72.8772,
   now() - interval '155 minutes',
   now() - interval '155 minutes' + interval '24 hours', false),

  ('I call home less often because hearing her voice makes me miss it too much.',
   19.0768, 72.8786,
   now() - interval '320 minutes',
   now() - interval '320 minutes' + interval '24 hours', false),

  ('I''ve been telling myself I''ll visit next month for eight months.',
   19.0752, 72.8768,
   now() - interval '645 minutes',
   now() - interval '645 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- CAPE TOWN (-33.9249, 18.4241) — 3 confessions
  -- ========================================================================

  ('I am tired in a way sleep doesn''t fix.',
   -33.9245, 18.4245,
   now() - interval '51 minutes',
   now() - interval '51 minutes'  + interval '24 hours', false),

  ('I''ve been staying in relationships longer than I should my whole adult life.',
   -33.9252, 18.4238,
   now() - interval '260 minutes',
   now() - interval '260 minutes' + interval '24 hours', false),

  ('I have opinions I keep to myself because I''ve given up on people changing their minds.',
   -33.9248, 18.4242,
   now() - interval '675 minutes',
   now() - interval '675 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- CHICAGO (41.8781, -87.6298) — 3 confessions
  -- ========================================================================

  ('I voted for the person I thought was least bad. Feels like that''s all voting is.',
   41.8785, -87.6295,
   now() - interval '22 minutes',
   now() - interval '22 minutes'  + interval '24 hours', false),

  ('I''ve been in a bad mood since November. Which November I won''t say.',
   41.8778, -87.6302,
   now() - interval '220 minutes',
   now() - interval '220 minutes' + interval '24 hours', false),

  ('I miss being bored. Real boredom. Not scrolling-through-my-phone bored.',
   41.8782, -87.6298,
   now() - interval '570 minutes',
   now() - interval '570 minutes' + interval '24 hours', false),

  -- ========================================================================
  -- MELANDSJØ, NORWAY — Near Me cluster (Hitra island)
  -- Centre: 63.5437, 8.4922  ← set device location here for Near Me screenshots
  -- All 8 confessions within ~200 m of centre.
  -- Near Me auto-expand settles at 500 m → shows all 8 confessions.
  -- ========================================================================

  -- 7 min ago · ~53 m NE of centre
  ('I moved here to escape something and I brought it with me.',
   63.5441, 8.4928,
   now() - interval '7 minutes',
   now() - interval '7 minutes'   + interval '24 hours', false),

  -- 52 min ago · ~74 m SW of centre
  ('I told her everything once. I should have kept some of it.',
   63.5432, 8.4912,
   now() - interval '52 minutes',
   now() - interval '52 minutes'  + interval '24 hours', false),

  -- 1h 18 min ago · ~110 m E of centre
  ('I like living out here. I just don''t tell anyone how lonely it gets in winter.',
   63.5439, 8.4943,
   now() - interval '78 minutes',
   now() - interval '78 minutes'  + interval '24 hours', false),

  -- 3h 5 min ago · ~126 m NE of centre
  ('I''m so tired of pretending this is the life I chose.',
   63.5447, 8.4934,
   now() - interval '185 minutes',
   now() - interval '185 minutes' + interval '24 hours', false),

  -- 4h 30 min ago · ~130 m SW of centre
  ('Jeg satt ute til klokken to i natt og tenkte på ting jeg aldri ville sagt.',
   63.5429, 8.4898,
   now() - interval '270 minutes',
   now() - interval '270 minutes' + interval '24 hours', false),

  -- 6h 45 min ago · ~80 m N of centre
  ('I have two phones. The second one has conversations I can''t show anyone.',
   63.5444, 8.4916,
   now() - interval '405 minutes',
   now() - interval '405 minutes' + interval '24 hours', false),

  -- 9h 20 min ago · ~155 m SW of centre
  ('I almost left. I would have been happier. I stayed anyway.',
   63.5425, 8.4906,
   now() - interval '560 minutes',
   now() - interval '560 minutes' + interval '24 hours', false),

  -- 12h 30 min ago · ~175 m E of centre
  ('out here you can actually hear yourself think. turns out that''s not always good.',
   63.5435, 8.4952,
   now() - interval '750 minutes',
   now() - interval '750 minutes' + interval '24 hours', false)

) AS v(text, lat, lng, created_at, expires_at, is_hidden)
WHERE NOT EXISTS (
  SELECT 1 FROM confessions c WHERE c.text = v.text
);

COMMIT;

-- --------------------------------------------------------------------------
-- Verification — run separately after commit to check what was inserted
-- --------------------------------------------------------------------------
-- SELECT
--   CASE
--     WHEN lat BETWEEN  59.90 AND  59.93 THEN 'Oslo'
--     WHEN lat BETWEEN  40.70 AND  40.72 THEN 'New York'
--     WHEN lat BETWEEN  51.50 AND  51.52 THEN 'London'
--     WHEN lat BETWEEN  48.85 AND  48.87 THEN 'Paris'
--     WHEN lat BETWEEN  52.51 AND  52.53 THEN 'Berlin'
--     WHEN lat BETWEEN  35.67 AND  35.68 THEN 'Tokyo'
--     WHEN lat BETWEEN  59.32 AND  59.34 THEN 'Stockholm'
--     WHEN lat BETWEEN  40.41 AND  40.42 THEN 'Madrid'
--     WHEN lat BETWEEN -33.87 AND -33.86 THEN 'Sydney'
--     WHEN lat BETWEEN -23.56 AND -23.54 THEN 'São Paulo'
--     WHEN lat BETWEEN  52.36 AND  52.38 THEN 'Amsterdam'
--     WHEN lat BETWEEN  34.05 AND  34.06 THEN 'Los Angeles'
--     WHEN lat BETWEEN -34.61 AND -34.60 THEN 'Buenos Aires'
--     WHEN lat BETWEEN  19.07 AND  19.08 THEN 'Mumbai'
--     WHEN lat BETWEEN -33.93 AND -33.92 THEN 'Cape Town'
--     WHEN lat BETWEEN  41.87 AND  41.88 THEN 'Chicago'
--     WHEN lat BETWEEN  63.54 AND  63.55 THEN 'Melandsjø'
--     ELSE 'unknown'
--   END AS city,
--   count(*) AS count
-- FROM confessions
-- WHERE expires_at > now()
-- GROUP BY 1
-- ORDER BY 2 DESC;
