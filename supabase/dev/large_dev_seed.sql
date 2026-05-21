-- Lethe large local development dataset
-- ============================================================================
-- DEV ONLY. Do not paste this into a hosted/production Supabase SQL editor.
--
-- Intended workflow:
--   npx supabase start
--   npx supabase db reset --local
--   npx supabase db execute --local --file supabase/dev/large_dev_seed.sql
--
-- What this does:
--   - Adds nullable dev/test metadata columns used only by local Insights RPCs.
--   - Creates local-only analytics/reporting RPCs expected by Lethe Insights.
--   - Replaces prior rows from this dev seed batch only.
--   - Inserts 30,000 confessions, about 320,000 analytics events, reports,
--     moderation actions, place cache rows, and ad policy rows.
--
-- Production safety:
--   - This file is outside supabase/migrations and outside configured seed.sql.
--   - The npm workflow uses Supabase CLI --local.
--   - All generated rows are marked with is_dev_seed/dev_seed_batch where the
--     table supports it.
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Local-only schema support for Insights
-- --------------------------------------------------------------------------

ALTER TABLE public.confessions
  ADD COLUMN IF NOT EXISTS region TEXT,
  ADD COLUMN IF NOT EXISTS country_code TEXT,
  ADD COLUMN IF NOT EXISTS city_code TEXT,
  ADD COLUMN IF NOT EXISTS language_detected TEXT,
  ADD COLUMN IF NOT EXISTS emotion_bucket TEXT,
  ADD COLUMN IF NOT EXISTS is_dev_seed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dev_seed_batch TEXT;

ALTER TABLE public.event_logs
  ADD COLUMN IF NOT EXISTS region TEXT,
  ADD COLUMN IF NOT EXISTS country_code TEXT,
  ADD COLUMN IF NOT EXISTS is_dev_seed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dev_seed_batch TEXT;

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS handled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS handled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS handled_by TEXT,
  ADD COLUMN IF NOT EXISTS is_dev_seed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dev_seed_batch TEXT;

CREATE TABLE IF NOT EXISTS public.moderation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  action_type TEXT NOT NULL,
  confession_id UUID,
  report_id UUID,
  reason TEXT,
  notes TEXT,
  context JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_dev_seed BOOLEAN NOT NULL DEFAULT false,
  dev_seed_batch TEXT
);

CREATE TABLE IF NOT EXISTS public.ad_policy_effective (
  country_code TEXT PRIMARY KEY,
  ads_per_session_cap NUMERIC NOT NULL DEFAULT 1,
  trigger_share NUMERIC NOT NULL DEFAULT 0.35,
  fill_rate NUMERIC NOT NULL DEFAULT 0.85,
  ecpm_nok NUMERIC NOT NULL DEFAULT 18,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_dev_seed BOOLEAN NOT NULL DEFAULT false,
  dev_seed_batch TEXT
);

CREATE INDEX IF NOT EXISTS confessions_dev_seed_idx ON public.confessions (is_dev_seed, dev_seed_batch);
CREATE INDEX IF NOT EXISTS confessions_dev_geo_idx ON public.confessions (region, country_code, city_code, created_at DESC);
CREATE INDEX IF NOT EXISTS event_logs_dev_seed_idx ON public.event_logs (is_dev_seed, dev_seed_batch);
CREATE INDEX IF NOT EXISTS event_logs_dev_analytics_idx ON public.event_logs (created_at, event_name, region, country_code, city_code, mode);
CREATE INDEX IF NOT EXISTS reports_dev_seed_idx ON public.reports (is_dev_seed, dev_seed_batch);
CREATE INDEX IF NOT EXISTS moderation_actions_dev_seed_idx ON public.moderation_actions (is_dev_seed, dev_seed_batch);

-- --------------------------------------------------------------------------
-- 2. Remove previous local dev seed rows only
-- --------------------------------------------------------------------------

DELETE FROM public.moderation_actions WHERE is_dev_seed = true OR dev_seed_batch = 'large-global-v1';
DELETE FROM public.reports WHERE is_dev_seed = true OR dev_seed_batch = 'large-global-v1';
DELETE FROM public.event_logs WHERE is_dev_seed = true OR dev_seed_batch = 'large-global-v1';
DELETE FROM public.ad_policy_effective WHERE is_dev_seed = true OR dev_seed_batch = 'large-global-v1';
DELETE FROM public.confessions WHERE is_dev_seed = true OR dev_seed_batch = 'large-global-v1';

-- --------------------------------------------------------------------------
-- 3. City and behavior model
-- --------------------------------------------------------------------------

CREATE TEMP TABLE dev_seed_cities (
  city_idx INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  region TEXT NOT NULL,
  country_code TEXT NOT NULL,
  city_code TEXT NOT NULL,
  city_label TEXT NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  language_detected TEXT NOT NULL,
  emotion_bias TEXT NOT NULL,
  ad_tolerance TEXT NOT NULL,
  weight INT NOT NULL
) ON COMMIT DROP;

INSERT INTO dev_seed_cities
  (region, country_code, city_code, city_label, lat, lng, language_detected, emotion_bias, ad_tolerance, weight)
VALUES
  ('Europe','NO','OSL','Oslo',59.9139,10.7522,'nb','lonely','high',4),
  ('Europe','NO','MEL','Melandsjo',63.5437,8.4922,'nb','tired','high',2),
  ('Europe','GB','LON','London',51.5074,-0.1278,'en','anxious','medium',5),
  ('Europe','FR','PAR','Paris',48.8566,2.3522,'fr','sad','medium',4),
  ('Europe','DE','BER','Berlin',52.5200,13.4050,'de','restless','medium',4),
  ('Europe','ES','MAD','Madrid',40.4168,-3.7038,'es','hopeful','low',3),
  ('North America','US','NYC','New York',40.7128,-74.0060,'en','anxious','low',6),
  ('North America','US','LAX','Los Angeles',34.0522,-118.2437,'en','restless','low',5),
  ('North America','CA','TOR','Toronto',43.6532,-79.3832,'en','lonely','medium',3),
  ('North America','MX','MEX','Mexico City',19.4326,-99.1332,'es','hopeful','medium',3),
  ('South America','BR','SAO','Sao Paulo',-23.5558,-46.6396,'pt','tired','medium',4),
  ('South America','AR','BUE','Buenos Aires',-34.6037,-58.3816,'es','sad','medium',3),
  ('South America','CO','BOG','Bogota',4.7110,-74.0721,'es','hopeful','high',2),
  ('Asia','JP','TYO','Tokyo',35.6762,139.6503,'ja','lonely','high',5),
  ('Asia','KR','SEL','Seoul',37.5665,126.9780,'ko','anxious','high',4),
  ('Asia','SG','SIN','Singapore',1.3521,103.8198,'en','tired','medium',3),
  ('Asia','IN','BOM','Mumbai',19.0760,72.8777,'en','hopeful','low',4),
  ('Africa','ZA','CPT','Cape Town',-33.9249,18.4241,'en','hopeful','medium',3),
  ('Africa','NG','LOS','Lagos',6.5244,3.3792,'en','restless','low',3),
  ('Africa','KE','NBO','Nairobi',-1.2921,36.8219,'en','tired','medium',2),
  ('Oceania','AU','SYD','Sydney',-33.8688,151.2093,'en','hopeful','high',3),
  ('Oceania','NZ','AKL','Auckland',-36.8509,174.7645,'en','lonely','high',2),
  ('Middle East','AE','DXB','Dubai',25.2048,55.2708,'en','restless','low',3),
  ('Middle East','IL','TLV','Tel Aviv',32.0853,34.7818,'en','anxious','medium',2),
  ('Middle East','SA','RUH','Riyadh',24.7136,46.6753,'ar','tired','low',2);

CREATE TEMP TABLE dev_seed_texts (
  n INT PRIMARY KEY,
  language_detected TEXT NOT NULL,
  text_value TEXT NOT NULL
) ON COMMIT DROP;

INSERT INTO dev_seed_texts VALUES
  (1,'en','I keep acting calm because everyone else needs me to be steady.'),
  (2,'en','Some days I want to disappear without worrying anyone.'),
  (3,'en','I miss who I was before everything became performance.'),
  (4,'en','I am proud of surviving things I still cannot explain.'),
  (5,'es','A veces sonrio para que nadie pregunte demasiado.'),
  (6,'es','Tengo miedo de estar construyendo una vida que no quiero.'),
  (7,'fr','Je fais semblant d aller bien parce que c est plus simple.'),
  (8,'fr','Il y a des jours ou le silence me sauve.'),
  (9,'de','Ich bin mude davon stark zu wirken.'),
  (10,'de','Manchmal vermisse ich eine Zukunft die nie passiert ist.'),
  (11,'pt','Eu queria recomecar sem explicar nada para ninguem.'),
  (12,'ja','daijoubu to itta kedo honto wa sukoshi kowai.'),
  (13,'ko','gwaenchanhdago malhaetjiman maeum-eun jogeum jichyeo isseo.'),
  (14,'ar','ana atazahar bilhudu lakin dakhili mutab.'),
  (15,'nb','Jeg savner en ro jeg ikke helt husker.'),
  (16,'sv','Jag ler ofta nar jag egentligen vill ga hem.'),
  (17,'da','Jeg har brug for stilhed mere end rad.'),
  (18,'en','I feel lighter when nobody expects an answer from me.'),
  (19,'en','I want a softer life, not a louder one.'),
  (20,'en','I am learning that quiet can be a boundary.');

CREATE TEMP TABLE dev_seed_emotions (n INT PRIMARY KEY, emotion TEXT NOT NULL) ON COMMIT DROP;
INSERT INTO dev_seed_emotions VALUES
  (1,'lonely'), (2,'anxious'), (3,'sad'), (4,'tired'), (5,'hopeful'), (6,'calm'), (7,'restless'), (8,'grateful');

-- --------------------------------------------------------------------------
-- 4. Confessions: 30k global rows, 180-day spread, coordinates sometimes null
-- --------------------------------------------------------------------------

WITH city_count AS (SELECT count(*)::INT AS c FROM dev_seed_cities),
generated AS (
  SELECT
    gs AS n,
    ((gs * 17) % (SELECT c FROM city_count)) + 1 AS city_idx,
    now()
      - make_interval(days => ((gs * 13) % 180), hours => ((gs * 7) % 24), mins => ((gs * 11) % 60))
      AS created_at
  FROM generate_series(1, 30000) AS gs
),
rows AS (
  SELECT
    g.n,
    c.*,
    t.text_value,
    CASE
      WHEN (g.n % 9) = 0 THEN NULL
      ELSE c.lat + ((((g.n * 37) % 1000) - 500)::DOUBLE PRECISION / 100000)
    END AS seeded_lat,
    CASE
      WHEN (g.n % 9) = 0 THEN NULL
      ELSE c.lng + ((((g.n * 53) % 1000) - 500)::DOUBLE PRECISION / 100000)
    END AS seeded_lng,
    CASE
      WHEN (g.n % 11) = 0 THEN 'calm'
      WHEN (g.n % 7) = 0 THEN 'hopeful'
      WHEN (g.n % 5) = 0 THEN 'sad'
      ELSE c.emotion_bias
    END AS seeded_emotion,
    g.created_at
  FROM generated g
  JOIN dev_seed_cities c ON c.city_idx = g.city_idx
  JOIN dev_seed_texts t ON t.n = ((g.n * 5) % 20) + 1
)
INSERT INTO public.confessions (
  text, lat, lng, created_at, expires_at, is_hidden, user_id,
  region, country_code, city_code, language_detected, emotion_bucket,
  is_dev_seed, dev_seed_batch
)
SELECT
  text_value,
  seeded_lat,
  seeded_lng,
  created_at,
  now() + interval '36 hours',
  (n % 41) = 0,
  NULL,
  region,
  country_code,
  city_code,
  language_detected,
  seeded_emotion,
  true,
  'large-global-v1'
FROM rows;

-- Keep Somewhere suggestions aligned with the large dataset.
INSERT INTO public.places_cache (name, lat, lng)
SELECT city_label, lat, lng
FROM dev_seed_cities
ON CONFLICT DO NOTHING;

-- Cache common place searches for local resolve_place testing.
INSERT INTO public.place_cache (q, q_lower, lat, lng, name, provider)
SELECT city_label, lower(city_label), lat, lng, city_label, 'dev_seed'
FROM dev_seed_cities
ON CONFLICT (q_lower) DO UPDATE
SET lat = EXCLUDED.lat, lng = EXCLUDED.lng, name = EXCLUDED.name, provider = 'dev_seed';

-- --------------------------------------------------------------------------
-- 5. Analytics events: sessions, feed, pagination, posting, ads, geo, mood
-- --------------------------------------------------------------------------

CREATE TEMP TABLE dev_seed_sessions AS
WITH city_count AS (SELECT count(*)::INT AS c FROM dev_seed_cities),
generated AS (
  SELECT
    gs AS n,
    ((gs * 19) % (SELECT c FROM city_count)) + 1 AS city_idx,
    now()
      - make_interval(days => ((gs * 17) % 180), hours => ((gs * 5) % 24), mins => ((gs * 7) % 60))
      AS started_at
  FROM generate_series(1, 80000) AS gs
)
SELECT
  g.n,
  ('dev-session-' || g.n)::TEXT AS session_hash,
  g.started_at,
  c.region,
  c.country_code,
  c.city_code,
  c.language_detected,
  c.emotion_bias AS emotion_bucket,
  CASE WHEN g.n % 10 = 0 THEN 'somewhere' WHEN g.n % 4 = 0 THEN 'near' ELSE 'world' END AS mode,
  CASE c.ad_tolerance
    WHEN 'high' THEN 5 + (g.n % 7)
    WHEN 'medium' THEN 3 + (g.n % 5)
    ELSE 1 + (g.n % 4)
  END AS page_depth,
  CASE c.ad_tolerance
    WHEN 'high' THEN 0.86
    WHEN 'medium' THEN 0.58
    ELSE 0.27
  END AS continue_probability,
  c.ad_tolerance
FROM generated g
JOIN dev_seed_cities c ON c.city_idx = g.city_idx;

INSERT INTO public.event_logs (
  event_name, created_at, day_bucket, time_bucket, mode, city_code,
  language_detected, emotion_bucket, session_hash, reason_bucket,
  region, country_code, is_dev_seed, dev_seed_batch
)
SELECT
  event_name,
  event_ts,
  event_ts::DATE,
  EXTRACT(HOUR FROM event_ts)::INT,
  mode,
  city_code,
  language_detected,
  emotion_bucket,
  session_hash,
  reason_bucket,
  region,
  country_code,
  true,
  'large-global-v1'
FROM (
  SELECT 'session_start'::TEXT AS event_name, started_at AS event_ts, NULL::TEXT AS reason_bucket, *
  FROM dev_seed_sessions

  UNION ALL
  SELECT 'feed_view', started_at + interval '5 seconds', NULL::TEXT, *
  FROM dev_seed_sessions

  UNION ALL
  SELECT 'page_fetch', started_at + (p * interval '25 seconds'), NULL::TEXT, s.*
  FROM dev_seed_sessions s
  JOIN LATERAL generate_series(1, LEAST(s.page_depth, 8)) AS p ON true

  UNION ALL
  SELECT 'post_attempt', started_at + interval '90 seconds', NULL::TEXT, *
  FROM dev_seed_sessions
  WHERE n % 5 = 0

  UNION ALL
  SELECT 'post_success', started_at + interval '100 seconds', NULL::TEXT, *
  FROM dev_seed_sessions
  WHERE n % 5 = 0 AND n % 6 <> 0

  UNION ALL
  SELECT 'post_reject', started_at + interval '100 seconds',
    CASE WHEN n % 13 = 0 THEN 'rate_limit' WHEN n % 11 = 0 THEN 'validation' ELSE 'content_filter' END,
    *
  FROM dev_seed_sessions
  WHERE n % 5 = 0 AND n % 6 = 0

  UNION ALL
  SELECT 'ad_shown', started_at + interval '130 seconds', NULL::TEXT, *
  FROM dev_seed_sessions
  WHERE page_depth >= 4

  UNION ALL
  SELECT 'continue_after_ad', started_at + interval '155 seconds', NULL::TEXT, *
  FROM dev_seed_sessions
  WHERE page_depth >= 4 AND ((n % 100)::NUMERIC / 100.0) < continue_probability

  UNION ALL
  SELECT 'drop_after_ad', started_at + interval '155 seconds', NULL::TEXT, *
  FROM dev_seed_sessions
  WHERE page_depth >= 4 AND ((n % 100)::NUMERIC / 100.0) >= continue_probability
) events;

-- --------------------------------------------------------------------------
-- 6. Reports and moderation data
-- --------------------------------------------------------------------------

WITH reportable AS (
  SELECT
    c.*,
    row_number() OVER (ORDER BY c.created_at DESC, c.id) AS rn
  FROM public.confessions c
  WHERE c.is_dev_seed = true
    AND c.dev_seed_batch = 'large-global-v1'
    AND (abs(hashtext(c.id::TEXT)) % 100) < 4
),
inserted AS (
  INSERT INTO public.reports (
    confession_id, reason, details, reporter_user_id, status, created_at,
    handled, handled_at, handled_by, is_dev_seed, dev_seed_batch
  )
  SELECT
    id,
    CASE
      WHEN rn % 5 = 0 THEN 'identifying'
      WHEN rn % 5 = 1 THEN 'contact'
      WHEN rn % 5 = 2 THEN 'threats'
      WHEN rn % 5 = 3 THEN 'spam'
      ELSE 'other'
    END,
    CASE WHEN rn % 4 = 0 THEN 'DEV SEED: simulated report detail.' ELSE NULL END,
    NULL,
    CASE
      WHEN rn % 9 = 0 THEN 'actioned'
      WHEN rn % 7 = 0 THEN 'dismissed'
      WHEN rn % 5 = 0 THEN 'reviewed'
      ELSE 'open'
    END,
    created_at + make_interval(hours => ((rn % 18)::INT), mins => ((rn % 50)::INT)),
    (rn % 5 = 0 OR rn % 7 = 0 OR rn % 9 = 0),
    CASE WHEN (rn % 5 = 0 OR rn % 7 = 0 OR rn % 9 = 0)
      THEN created_at + make_interval(hours => (((rn % 18) + 2)::INT), mins => ((rn % 50)::INT))
      ELSE NULL
    END,
    CASE WHEN (rn % 5 = 0 OR rn % 7 = 0 OR rn % 9 = 0) THEN 'dev-moderator' ELSE NULL END,
    true,
    'large-global-v1'
  FROM reportable
  RETURNING *
)
INSERT INTO public.moderation_actions (
  created_at, action_type, confession_id, report_id, reason, notes, context,
  is_dev_seed, dev_seed_batch
)
SELECT
  COALESCE(handled_at, created_at + interval '3 hours'),
  CASE
    WHEN status = 'actioned' THEN 'HIDE_CONFESSION'
    WHEN status = 'dismissed' THEN 'DISMISS_REPORT'
    WHEN status = 'reviewed' THEN 'MARK_HANDLED'
    ELSE 'ESCALATE'
  END,
  confession_id,
  id,
  reason,
  'DEV SEED: simulated moderation action.',
  jsonb_build_object('source','large_dev_seed','ui_version','reports_v2'),
  true,
  'large-global-v1'
FROM inserted
WHERE handled = true OR (abs(hashtext(id::TEXT)) % 100) < 10;

UPDATE public.confessions c
SET is_hidden = true
FROM public.reports r
WHERE r.confession_id = c.id
  AND r.is_dev_seed = true
  AND r.status = 'actioned';

INSERT INTO public.ad_policy_effective (
  country_code, ads_per_session_cap, trigger_share, fill_rate, ecpm_nok,
  is_dev_seed, dev_seed_batch
)
SELECT DISTINCT
  country_code,
  CASE ad_tolerance WHEN 'high' THEN 1.6 WHEN 'medium' THEN 1.2 ELSE 0.8 END,
  CASE ad_tolerance WHEN 'high' THEN 0.62 WHEN 'medium' THEN 0.42 ELSE 0.22 END,
  CASE ad_tolerance WHEN 'high' THEN 0.92 WHEN 'medium' THEN 0.84 ELSE 0.70 END,
  CASE region
    WHEN 'North America' THEN 38
    WHEN 'Europe' THEN 30
    WHEN 'Oceania' THEN 28
    WHEN 'Middle East' THEN 25
    ELSE 14
  END,
  true,
  'large-global-v1'
FROM dev_seed_cities
ON CONFLICT (country_code) DO UPDATE SET
  ads_per_session_cap = EXCLUDED.ads_per_session_cap,
  trigger_share = EXCLUDED.trigger_share,
  fill_rate = EXCLUDED.fill_rate,
  ecpm_nok = EXCLUDED.ecpm_nok,
  updated_at = now(),
  is_dev_seed = true,
  dev_seed_batch = 'large-global-v1';

-- --------------------------------------------------------------------------
-- 7. Local-only Insights RPCs
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_insights_region_options()
RETURNS TABLE (region TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT e.region
  FROM public.event_logs e
  WHERE e.region IS NOT NULL
  ORDER BY e.region;
$$;

CREATE OR REPLACE FUNCTION public.get_insights_country_options(p_region TEXT DEFAULT NULL)
RETURNS TABLE (country_code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT e.country_code
  FROM public.event_logs e
  WHERE e.country_code IS NOT NULL
    AND (p_region IS NULL OR e.region = p_region)
  ORDER BY e.country_code;
$$;

CREATE OR REPLACE FUNCTION public.get_insights_city_options(p_country_code TEXT DEFAULT NULL, p_region TEXT DEFAULT NULL)
RETURNS TABLE (city_code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT e.city_code
  FROM public.event_logs e
  WHERE e.city_code IS NOT NULL
    AND (p_country_code IS NULL OR e.country_code = p_country_code)
    AND (p_region IS NULL OR e.region = p_region)
  ORDER BY e.city_code;
$$;

CREATE OR REPLACE FUNCTION public._lethe_event_filtered(
  p_start_ts TIMESTAMPTZ,
  p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL,
  p_mode TEXT DEFAULT NULL
)
RETURNS SETOF public.event_logs
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
  FROM public.event_logs e
  WHERE e.created_at >= p_start_ts
    AND e.created_at < p_end_ts
    AND (p_region IS NULL OR e.region = p_region)
    AND (p_country_code IS NULL OR e.country_code = p_country_code)
    AND (p_city_code IS NULL OR e.city_code = p_city_code)
    AND (p_mode IS NULL OR e.mode = p_mode);
$$;

CREATE OR REPLACE FUNCTION public.get_pulse_metrics_range(
  p_start_ts TIMESTAMPTZ, p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL, p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL, p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (sessions BIGINT, readers BIGINT, posts BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    count(DISTINCT session_hash) FILTER (WHERE event_name = 'session_start') AS sessions,
    count(DISTINCT session_hash) FILTER (WHERE event_name IN ('feed_view','page_fetch')) AS readers,
    count(*) FILTER (WHERE event_name = 'post_success') AS posts
  FROM public._lethe_event_filtered(p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode);
$$;

CREATE OR REPLACE FUNCTION public.get_engagement_flow_range(
  p_start_ts TIMESTAMPTZ, p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL, p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL, p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (
  sessions BIGINT, pages_loaded BIGINT, post_attempts BIGINT, post_success BIGINT,
  ads_shown BIGINT, ads_shown_sessions BIGINT, ad_continue_sessions BIGINT,
  ad_drop_sessions BIGINT, posts_per_session NUMERIC, pages_per_session NUMERIC,
  ad_continue_rate NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH e AS (
    SELECT * FROM public._lethe_event_filtered(p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode)
  ), a AS (
    SELECT
      count(DISTINCT session_hash) FILTER (WHERE event_name = 'session_start') AS sessions,
      count(*) FILTER (WHERE event_name = 'page_fetch') AS pages_loaded,
      count(*) FILTER (WHERE event_name = 'post_attempt') AS post_attempts,
      count(*) FILTER (WHERE event_name = 'post_success') AS post_success,
      count(*) FILTER (WHERE event_name = 'ad_shown') AS ads_shown,
      count(DISTINCT session_hash) FILTER (WHERE event_name = 'ad_shown') AS ads_shown_sessions,
      count(DISTINCT session_hash) FILTER (WHERE event_name = 'continue_after_ad') AS ad_continue_sessions,
      count(DISTINCT session_hash) FILTER (WHERE event_name = 'drop_after_ad') AS ad_drop_sessions
    FROM e
  )
  SELECT
    sessions, pages_loaded, post_attempts, post_success, ads_shown,
    ads_shown_sessions, ad_continue_sessions, ad_drop_sessions,
    CASE WHEN sessions > 0 THEN post_success::NUMERIC / sessions ELSE 0 END,
    CASE WHEN sessions > 0 THEN pages_loaded::NUMERIC / sessions ELSE 0 END,
    CASE WHEN ads_shown_sessions > 0 THEN ad_continue_sessions::NUMERIC / ads_shown_sessions ELSE 0 END
  FROM a;
$$;

CREATE OR REPLACE FUNCTION public.get_readers_writers_range(
  p_start_ts TIMESTAMPTZ, p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL, p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL, p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (readers BIGINT, writers BIGINT, writer_share NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH e AS (
    SELECT * FROM public._lethe_event_filtered(p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode)
  ), a AS (
    SELECT
      count(DISTINCT session_hash) FILTER (WHERE event_name IN ('feed_view','page_fetch')) AS readers,
      count(DISTINCT session_hash) FILTER (WHERE event_name = 'post_success') AS writers
    FROM e
  )
  SELECT readers, writers, CASE WHEN readers > 0 THEN writers::NUMERIC / readers ELSE 0 END
  FROM a;
$$;

CREATE OR REPLACE FUNCTION public.get_change_over_time_range(
  p_start_ts TIMESTAMPTZ, p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL, p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL, p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (day_bucket DATE, sessions BIGINT, posts BIGINT, post_rate NUMERIC, pages_loaded BIGINT, pages_per_session NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH days AS (
    SELECT generate_series(date_trunc('day', p_start_ts), date_trunc('day', p_end_ts - interval '1 second'), interval '1 day')::DATE AS day
  ), e AS (
    SELECT * FROM public._lethe_event_filtered(p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode)
  ), a AS (
    SELECT
      e.day_bucket,
      count(DISTINCT session_hash) FILTER (WHERE event_name = 'session_start') AS sessions,
      count(*) FILTER (WHERE event_name = 'post_success') AS posts,
      count(*) FILTER (WHERE event_name = 'page_fetch') AS pages_loaded
    FROM e
    GROUP BY e.day_bucket
  )
  SELECT
    d.day,
    COALESCE(a.sessions, 0),
    COALESCE(a.posts, 0),
    CASE WHEN COALESCE(a.sessions, 0) > 0 THEN a.posts::NUMERIC / a.sessions ELSE 0 END,
    COALESCE(a.pages_loaded, 0),
    CASE WHEN COALESCE(a.sessions, 0) > 0 THEN a.pages_loaded::NUMERIC / a.sessions ELSE 0 END
  FROM days d
  LEFT JOIN a ON a.day_bucket = d.day
  ORDER BY d.day;
$$;

CREATE OR REPLACE FUNCTION public.get_friction_range(
  p_start_ts TIMESTAMPTZ, p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL, p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL
)
RETURNS TABLE (attempts_total BIGINT, success_total BIGINT, rejected_total BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    count(*) FILTER (WHERE event_name = 'post_attempt') AS attempts_total,
    count(*) FILTER (WHERE event_name = 'post_success') AS success_total,
    count(*) FILTER (WHERE event_name = 'post_reject') AS rejected_total
  FROM public._lethe_event_filtered(p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, NULL);
$$;

CREATE OR REPLACE FUNCTION public.get_sessions_by_country_range(
  p_start_ts TIMESTAMPTZ, p_end_ts TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL, p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL, p_mode TEXT DEFAULT NULL
)
RETURNS TABLE (country_code TEXT, sessions BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT e.country_code, count(DISTINCT e.session_hash) AS sessions
  FROM public._lethe_event_filtered(p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode) e
  WHERE e.event_name = 'session_start' AND e.country_code IS NOT NULL
  GROUP BY e.country_code
  ORDER BY sessions DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_revenue_by_country_range(
  p_start TIMESTAMPTZ, p_end TIMESTAMPTZ, p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
  country_code TEXT, sessions BIGINT, ad_impressions BIGINT,
  revenue_total NUMERIC, ad_revenue NUMERIC, premium_revenue NUMERIC,
  revenue_per_session NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH a AS (
    SELECT
      e.country_code,
      count(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'session_start') AS sessions,
      count(*) FILTER (WHERE e.event_name = 'ad_shown') AS ad_impressions
    FROM public.event_logs e
    WHERE e.created_at >= p_start
      AND e.created_at < p_end
      AND e.country_code IS NOT NULL
      AND (p_region IS NULL OR e.region = p_region)
    GROUP BY e.country_code
  )
  SELECT
    a.country_code,
    a.sessions,
    a.ad_impressions,
    ROUND((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85), 4) AS revenue_total,
    ROUND((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85), 4) AS ad_revenue,
    0::NUMERIC AS premium_revenue,
    CASE WHEN a.sessions > 0
      THEN ROUND(((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85)) / a.sessions, 6)
      ELSE 0
    END AS revenue_per_session
  FROM a
  LEFT JOIN public.ad_policy_effective p ON p.country_code = a.country_code
  ORDER BY revenue_total DESC, sessions DESC;
$$;

CREATE OR REPLACE FUNCTION public._lethe_confession_filtered(
  p_start_date DATE,
  p_end_date DATE,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL
)
RETURNS SETOF public.confessions
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
  FROM public.confessions c
  WHERE c.created_at::DATE >= p_start_date
    AND c.created_at::DATE <= p_end_date
    AND (p_region IS NULL OR c.region = p_region)
    AND (p_country_code IS NULL OR c.country_code = p_country_code)
    AND (p_city_code IS NULL OR c.city_code = p_city_code);
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_mood_summary(
  p_start_date DATE, p_end_date DATE, p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL, p_city_code TEXT DEFAULT NULL
)
RETURNS TABLE (mood_bucket TEXT, total_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(emotion_bucket, 'unknown'), count(*)
  FROM public._lethe_confession_filtered(p_start_date, p_end_date, p_region, p_country_code, p_city_code)
  GROUP BY 1
  ORDER BY 2 DESC;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_mood_pulse(
  p_start_date DATE, p_end_date DATE, p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL, p_city_code TEXT DEFAULT NULL
)
RETURNS TABLE (
  balance_score NUMERIC, prev_balance_score NUMERIC, delta_balance_score NUMERIC,
  positive_share NUMERIC, negative_share NUMERIC, total_confessions BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH current_rows AS (
    SELECT * FROM public._lethe_confession_filtered(p_start_date, p_end_date, p_region, p_country_code, p_city_code)
  ), cur AS (
    SELECT
      count(*) AS total,
      count(*) FILTER (WHERE emotion_bucket IN ('hopeful','calm','grateful')) AS positive,
      count(*) FILTER (WHERE emotion_bucket IN ('lonely','anxious','sad','tired','restless')) AS negative
    FROM current_rows
  ), span AS (
    SELECT (p_end_date - p_start_date + 1) AS days
  ), prev_rows AS (
    SELECT * FROM public._lethe_confession_filtered(p_start_date - (SELECT days FROM span), p_start_date - 1, p_region, p_country_code, p_city_code)
  ), prev AS (
    SELECT
      count(*) AS total,
      count(*) FILTER (WHERE emotion_bucket IN ('hopeful','calm','grateful')) AS positive,
      count(*) FILTER (WHERE emotion_bucket IN ('lonely','anxious','sad','tired','restless')) AS negative
    FROM prev_rows
  ), scores AS (
    SELECT
      CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END AS current_score,
      CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS previous_score,
      CASE WHEN cur.total > 0 THEN cur.positive::NUMERIC / cur.total ELSE 0 END AS positive_share,
      CASE WHEN cur.total > 0 THEN cur.negative::NUMERIC / cur.total ELSE 0 END AS negative_share,
      cur.total
    FROM cur, prev
  )
  SELECT current_score, previous_score, current_score - previous_score, positive_share, negative_share, total
  FROM scores;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_mood_pulse_by_region(p_start_date DATE, p_end_date DATE)
RETURNS TABLE (
  region TEXT, balance_score NUMERIC, prev_balance_score NUMERIC,
  delta_balance_score NUMERIC, positive_share NUMERIC, negative_share NUMERIC,
  total_confessions BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    r.region,
    p.balance_score,
    p.prev_balance_score,
    p.delta_balance_score,
    p.positive_share,
    p.negative_share,
    p.total_confessions
  FROM (SELECT DISTINCT c.region FROM public.confessions c WHERE c.region IS NOT NULL) r
  CROSS JOIN LATERAL public.rpc_get_mood_pulse(p_start_date, p_end_date, r.region, NULL, NULL) p
  ORDER BY p.total_confessions DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_overview(
  p_only_unhandled BOOLEAN DEFAULT true,
  p_reason TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL
)
RETURNS TABLE (total_confessions BIGINT, total_reports BIGINT, total_unhandled_reports BIGINT, reasons_json JSONB)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH filtered AS (
    SELECT r.*, c.is_hidden
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE (p_reason IS NULL OR r.reason = p_reason)
      AND (p_visibility IS NULL OR (p_visibility = 'hidden' AND COALESCE(c.is_hidden,false)) OR (p_visibility = 'visible' AND NOT COALESCE(c.is_hidden,false)))
      AND (NOT p_only_unhandled OR r.status = 'open')
  ), reasons AS (
    SELECT COALESCE(jsonb_object_agg(reason, cnt), '{}'::jsonb) AS j
    FROM (SELECT reason, count(*) AS cnt FROM filtered GROUP BY reason) x
  )
  SELECT
    (SELECT count(*) FROM public.confessions),
    (SELECT count(*) FROM filtered),
    (SELECT count(*) FROM filtered WHERE status = 'open'),
    reasons.j
  FROM reasons;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_inbox(p_limit INT DEFAULT 50, p_only_unhandled BOOLEAN DEFAULT true)
RETURNS TABLE (
  report_id UUID, report_created_at TIMESTAMPTZ, reason TEXT, details TEXT,
  report_city_code TEXT, confession_id UUID, confession_region TEXT,
  confession_text TEXT, confession_is_hidden BOOLEAN, handled BOOLEAN,
  handled_at TIMESTAMPTZ, handled_by TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    r.id, r.created_at, r.reason, r.details, c.city_code, c.id, c.region,
    c.text, COALESCE(c.is_hidden,false), COALESCE(r.handled, r.status <> 'open'),
    r.handled_at, r.handled_by
  FROM public.reports r
  LEFT JOIN public.confessions c ON c.id = r.confession_id
  WHERE (NOT p_only_unhandled OR r.status = 'open')
  ORDER BY r.created_at DESC
  LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION public.set_report_handled(p_report_id UUID, p_handled BOOLEAN DEFAULT true)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.reports
  SET handled = p_handled,
      handled_at = CASE WHEN p_handled THEN now() ELSE NULL END,
      handled_by = CASE WHEN p_handled THEN 'local-dev' ELSE NULL END,
      status = CASE WHEN p_handled THEN 'reviewed' ELSE 'open' END
  WHERE id = p_report_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_confession_hidden(p_confession_id UUID, p_hidden BOOLEAN DEFAULT true)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.confessions SET is_hidden = p_hidden WHERE id = p_confession_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_moderation_action(
  p_action_type TEXT, p_report_id UUID DEFAULT NULL, p_confession_id UUID DEFAULT NULL,
  p_reason TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL, p_context JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.moderation_actions (action_type, report_id, confession_id, reason, notes, context, is_dev_seed, dev_seed_batch)
  VALUES (p_action_type, p_report_id, p_confession_id, p_reason, p_notes, COALESCE(p_context, '{}'::jsonb), true, 'large-global-v1')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_moderation_actions_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL, p_limit INT DEFAULT 25, p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID, created_at TIMESTAMPTZ, action_type TEXT, confession_id UUID,
  report_id UUID, reason TEXT, city_code TEXT, region TEXT, country_code TEXT, source TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    a.id, a.created_at, a.action_type, a.confession_id, a.report_id, a.reason,
    c.city_code, c.region, c.country_code, COALESCE(a.context->>'source','dev_seed')
  FROM public.moderation_actions a
  LEFT JOIN public.confessions c ON c.id = a.confession_id
  WHERE a.created_at >= now() - make_interval(days => p_days)
    AND (p_region IS NULL OR c.region = p_region)
    AND (p_country IS NULL OR c.country_code = p_country)
    AND (p_city IS NULL OR c.city_code = p_city)
  ORDER BY a.created_at DESC
  LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_pending_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL, p_limit INT DEFAULT 25, p_offset INT DEFAULT 0
)
RETURNS TABLE (
  report_id UUID, confession_id UUID, reason TEXT, created_at TIMESTAMPTZ,
  region TEXT, country_code TEXT, city_code TEXT, hours_open NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT r.id, r.confession_id, r.reason, r.created_at, c.region, c.country_code, c.city_code,
         EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600
  FROM public.reports r
  LEFT JOIN public.confessions c ON c.id = r.confession_id
  WHERE r.status = 'open'
    AND r.created_at >= now() - make_interval(days => p_days)
    AND (p_region IS NULL OR c.region = p_region)
    AND (p_country IS NULL OR c.country_code = p_country)
    AND (p_city IS NULL OR c.city_code = p_city)
  ORDER BY r.created_at DESC
  LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_escalated_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL, p_limit INT DEFAULT 20, p_offset INT DEFAULT 0
)
RETURNS TABLE (
  report_id UUID, confession_id UUID, reason TEXT, region TEXT, country_code TEXT,
  city_code TEXT, created_at TIMESTAMPTZ, hours_open NUMERIC,
  latest_action TEXT, latest_action_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT r.id, r.confession_id, r.reason, c.region, c.country_code, c.city_code,
         r.created_at, EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600,
         COALESCE(a.action_type, 'ESCALATE'), COALESCE(a.created_at, r.created_at)
  FROM public.reports r
  LEFT JOIN public.confessions c ON c.id = r.confession_id
  LEFT JOIN LATERAL (
    SELECT * FROM public.moderation_actions ma
    WHERE ma.report_id = r.id
    ORDER BY ma.created_at DESC
    LIMIT 1
  ) a ON true
  WHERE (
      (r.status = 'open' AND r.created_at < now() - interval '12 hours')
      OR COALESCE(a.action_type, '') = 'ESCALATE'
    )
    AND r.created_at >= now() - make_interval(days => p_days)
    AND (p_region IS NULL OR c.region = p_region)
    AND (p_country IS NULL OR c.country_code = p_country)
    AND (p_city IS NULL OR c.city_code = p_city)
  ORDER BY r.created_at DESC
  LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_outcomes_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL, p_city TEXT DEFAULT NULL
)
RETURNS TABLE (
  actioned_reports BIGINT, handled_reports BIGINT, hidden_reports BIGINT,
  dismissed_reports BIGINT, escalated_reports BIGINT, handled_rate_pct NUMERIC,
  hidden_rate_pct NUMERIC, dismissed_rate_pct NUMERIC, escalated_rate_pct NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH r AS (
    SELECT r.*, c.region, c.country_code, c.city_code, c.is_hidden
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region IS NULL OR c.region = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city IS NULL OR c.city_code = p_city)
  ), a AS (
    SELECT
      count(*) AS total,
      count(*) FILTER (WHERE status = 'actioned') AS actioned,
      count(*) FILTER (WHERE handled OR status <> 'open') AS handled_count,
      count(*) FILTER (WHERE COALESCE(is_hidden,false)) AS hidden,
      count(*) FILTER (WHERE status = 'dismissed') AS dismissed,
      count(*) FILTER (WHERE status = 'open' AND created_at < now() - interval '12 hours') AS escalated
    FROM r
  )
  SELECT actioned, handled_count, hidden, dismissed, escalated,
    CASE WHEN total > 0 THEN handled_count * 100.0 / total ELSE 0 END,
    CASE WHEN total > 0 THEN hidden * 100.0 / total ELSE 0 END,
    CASE WHEN total > 0 THEN dismissed * 100.0 / total ELSE 0 END,
    CASE WHEN total > 0 THEN escalated * 100.0 / total ELSE 0 END
  FROM a;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_hotspots_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL
)
RETURNS TABLE (
  city_code TEXT, city_label TEXT, region TEXT, country TEXT, reports_count BIGINT,
  reads_count BIGINT, reports_per_1k NUMERIC, top_reason TEXT, top_reason_count BIGINT,
  total_reports_count BIGINT, unknown_reports_count BIGINT, unknown_reports_pct NUMERIC,
  total_reads_count BIGINT, unknown_reads_count BIGINT, unknown_reads_pct NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH r AS (
    SELECT r.reason, c.city_code, c.region, c.country_code
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region IS NULL OR c.region = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
  ), city_reports AS (
    SELECT city_code, region, country_code, count(*) AS reports_count
    FROM r
    WHERE city_code IS NOT NULL
    GROUP BY city_code, region, country_code
  ), reads AS (
    SELECT city_code, count(*) AS reads_count
    FROM public.event_logs
    WHERE created_at >= now() - make_interval(days => p_days)
      AND event_name IN ('feed_view','page_fetch')
    GROUP BY city_code
  ), top_reason AS (
    SELECT DISTINCT ON (city_code) city_code, reason, count(*) AS reason_count
    FROM r
    WHERE city_code IS NOT NULL
    GROUP BY city_code, reason
    ORDER BY city_code, count(*) DESC
  ), totals AS (
    SELECT
      (SELECT count(*) FROM r) AS total_reports,
      (SELECT count(*) FROM r WHERE city_code IS NULL) AS unknown_reports,
      (SELECT count(*) FROM public.event_logs WHERE created_at >= now() - make_interval(days => p_days) AND event_name IN ('feed_view','page_fetch')) AS total_reads,
      (SELECT count(*) FROM public.event_logs WHERE created_at >= now() - make_interval(days => p_days) AND event_name IN ('feed_view','page_fetch') AND city_code IS NULL) AS unknown_reads
  )
  SELECT
    cr.city_code, cr.city_code, cr.region, cr.country_code, cr.reports_count,
    COALESCE(rd.reads_count, 0),
    CASE WHEN COALESCE(rd.reads_count, 0) > 0 THEN cr.reports_count * 1000.0 / rd.reads_count ELSE NULL END,
    tr.reason, tr.reason_count,
    t.total_reports, t.unknown_reports,
    CASE WHEN t.total_reports > 0 THEN t.unknown_reports * 100.0 / t.total_reports ELSE 0 END,
    t.total_reads, t.unknown_reads,
    CASE WHEN t.total_reads > 0 THEN t.unknown_reads * 100.0 / t.total_reads ELSE 0 END
  FROM city_reports cr
  LEFT JOIN reads rd ON rd.city_code = cr.city_code
  LEFT JOIN top_reason tr ON tr.city_code = cr.city_code
  CROSS JOIN totals t
  ORDER BY cr.reports_count DESC
  LIMIT 20;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_sla_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL, p_city TEXT DEFAULT NULL
)
RETURNS TABLE (avg_hours_to_handle NUMERIC, p95_hours_to_handle NUMERIC, overdue_open BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH r AS (
    SELECT r.*, c.region, c.country_code, c.city_code
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region IS NULL OR c.region = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city IS NULL OR c.city_code = p_city)
  )
  SELECT
    avg(EXTRACT(EPOCH FROM (handled_at - created_at)) / 3600) FILTER (WHERE handled_at IS NOT NULL),
    percentile_cont(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (handled_at - created_at)) / 3600) FILTER (WHERE handled_at IS NOT NULL),
    count(*) FILTER (WHERE status = 'open' AND created_at < now() - interval '12 hours')
  FROM r;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL, p_city TEXT DEFAULT NULL
)
RETURNS TABLE (total_reports BIGINT, reports_with_geo BIGINT, geo_coverage_pct NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH r AS (
    SELECT r.*, c.region, c.country_code, c.city_code
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region IS NULL OR c.region = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city IS NULL OR c.city_code = p_city)
  ), a AS (
    SELECT count(*) AS total, count(*) FILTER (WHERE city_code IS NOT NULL OR country_code IS NOT NULL) AS with_geo
    FROM r
  )
  SELECT total, with_geo, CASE WHEN total > 0 THEN with_geo * 100.0 / total ELSE 0 END FROM a;
$$;

CREATE OR REPLACE FUNCTION public.get_reports_spike_explain_v1(
  p_days INT DEFAULT 7, p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL, p_city TEXT DEFAULT NULL
)
RETURNS TABLE (reason TEXT, current_count BIGINT, previous_count BIGINT, delta_pct NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH cur AS (
    SELECT r.reason, count(*) AS c
    FROM public.reports r LEFT JOIN public.confessions cf ON cf.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days)
      AND (p_region IS NULL OR cf.region = p_region)
      AND (p_country IS NULL OR cf.country_code = p_country)
      AND (p_city IS NULL OR cf.city_code = p_city)
    GROUP BY r.reason
  ), prev AS (
    SELECT r.reason, count(*) AS c
    FROM public.reports r LEFT JOIN public.confessions cf ON cf.id = r.confession_id
    WHERE r.created_at >= now() - make_interval(days => p_days * 2)
      AND r.created_at < now() - make_interval(days => p_days)
      AND (p_region IS NULL OR cf.region = p_region)
      AND (p_country IS NULL OR cf.country_code = p_country)
      AND (p_city IS NULL OR cf.city_code = p_city)
    GROUP BY r.reason
  )
  SELECT cur.reason, cur.c, COALESCE(prev.c, 0),
    CASE WHEN COALESCE(prev.c, 0) > 0 THEN (cur.c - prev.c) * 100.0 / prev.c ELSE NULL END
  FROM cur LEFT JOIN prev USING (reason)
  ORDER BY cur.c DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_trends_comparison_v1(
  p_scope TEXT DEFAULT 'global', p_region TEXT DEFAULT NULL, p_days INT DEFAULT 7, p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (scope_key TEXT, metric_key TEXT, current_value NUMERIC, previous_value NUMERIC, delta_abs NUMERIC, delta_pct NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH bounds AS (
    SELECT p_end_date - (p_days - 1) AS cur_start, p_end_date AS cur_end,
           p_end_date - (p_days * 2 - 1) AS prev_start, p_end_date - p_days AS prev_end
  ), scopes AS (
    SELECT CASE WHEN p_scope = 'country' THEN e.country_code ELSE COALESCE(p_region, 'global') END AS scope_key, e.*
    FROM public.event_logs e
    WHERE (p_region IS NULL OR e.region = p_region OR e.country_code = p_region)
      AND (p_scope <> 'country' OR e.country_code IS NOT NULL)
  ), agg AS (
    SELECT scope_key, metric_key, period, value
    FROM (
      SELECT
        scope_key,
        metric_key,
        CASE WHEN day_bucket BETWEEN b.cur_start AND b.cur_end THEN 'cur' ELSE 'prev' END AS period,
        CASE
          WHEN metric_key = 'sessions' THEN count(DISTINCT session_hash)::NUMERIC
          ELSE count(*)::NUMERIC
        END AS value
      FROM (
        SELECT scope_key, day_bucket, session_hash, 'sessions' AS metric_key
        FROM scopes
        WHERE event_name = 'session_start'
        UNION ALL
        SELECT scope_key, day_bucket, session_hash, 'reads' AS metric_key
        FROM scopes
        WHERE event_name IN ('feed_view','page_fetch')
        UNION ALL
        SELECT scope_key, day_bucket, session_hash, 'posts' AS metric_key
        FROM scopes
        WHERE event_name = 'post_success'
        UNION ALL
        SELECT scope_key, day_bucket, session_hash, 'ads_shown' AS metric_key
        FROM scopes
        WHERE event_name = 'ad_shown'
      ) m, bounds b
      WHERE day_bucket BETWEEN b.prev_start AND b.cur_end
      GROUP BY scope_key, metric_key, CASE WHEN day_bucket BETWEEN b.cur_start AND b.cur_end THEN 'cur' ELSE 'prev' END
    ) x
  ), pivot AS (
    SELECT scope_key, metric_key,
      COALESCE(sum(value) FILTER (WHERE period = 'cur'), 0) AS cur,
      COALESCE(sum(value) FILTER (WHERE period = 'prev'), 0) AS prev
    FROM agg
    GROUP BY scope_key, metric_key
  )
  SELECT scope_key, metric_key, cur, prev, cur - prev,
    CASE WHEN prev > 0 THEN (cur - prev) * 100.0 / prev ELSE NULL END
  FROM pivot
  ORDER BY metric_key, cur DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_trends_trendline_v1(
  p_region TEXT DEFAULT NULL, p_days INT DEFAULT 30, p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (day DATE, metric_key TEXT, value NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH days AS (
    SELECT generate_series(p_end_date - (p_days - 1), p_end_date, interval '1 day')::DATE AS d
  ), filtered AS (
    SELECT * FROM public.event_logs
    WHERE (p_region IS NULL OR region = p_region OR country_code = p_region)
  ), metrics AS (
    SELECT d.d, 'sessions' AS metric_key, count(DISTINCT session_hash)::NUMERIC AS value
    FROM days d LEFT JOIN filtered e ON e.day_bucket = d.d AND e.event_name = 'session_start'
    GROUP BY d.d
    UNION ALL
    SELECT d.d, 'reads', count(e.*)::NUMERIC
    FROM days d LEFT JOIN filtered e ON e.day_bucket = d.d AND e.event_name IN ('feed_view','page_fetch')
    GROUP BY d.d
    UNION ALL
    SELECT d.d, 'posts', count(e.*)::NUMERIC
    FROM days d LEFT JOIN filtered e ON e.day_bucket = d.d AND e.event_name = 'post_success'
    GROUP BY d.d
    UNION ALL
    SELECT d.d, 'ads_shown', count(e.*)::NUMERIC
    FROM days d LEFT JOIN filtered e ON e.day_bucket = d.d AND e.event_name = 'ad_shown'
    GROUP BY d.d
  )
  SELECT d, metric_key, value FROM metrics ORDER BY d, metric_key;
$$;

CREATE OR REPLACE FUNCTION public.get_year_wheel_v1(
  p_scope TEXT DEFAULT 'global', p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL,
  p_days INT DEFAULT 365, p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  month_start DATE, sessions BIGINT, posts BIGINT, posts_per_session NUMERIC,
  mood_pos BIGINT, mood_neg BIGINT, mood_balance NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH months AS (
    SELECT generate_series(date_trunc('month', p_end_date::TIMESTAMP - make_interval(days => p_days)), date_trunc('month', p_end_date::TIMESTAMP), interval '1 month')::DATE AS m
  ), event_months AS (
    SELECT
      date_trunc('month', e.created_at)::DATE AS month_start,
      count(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'session_start') AS sessions,
      count(*) FILTER (WHERE e.event_name = 'post_success') AS posts
    FROM public.event_logs e
    WHERE day_bucket >= p_end_date - p_days
      AND (p_region IS NULL OR region = p_region)
      AND (p_country IS NULL OR country_code = p_country)
    GROUP BY 1
  ), confession_months AS (
    SELECT
      date_trunc('month', c.created_at)::DATE AS month_start,
      count(*) FILTER (WHERE c.emotion_bucket IN ('hopeful','calm','grateful')) AS mood_pos,
      count(*) FILTER (WHERE c.emotion_bucket IN ('lonely','anxious','sad','tired','restless')) AS mood_neg,
      count(*) AS total
    FROM public.confessions c
    WHERE created_at::DATE >= p_end_date - p_days
      AND (p_region IS NULL OR region = p_region)
      AND (p_country IS NULL OR country_code = p_country)
    GROUP BY 1
  )
  SELECT
    m.m,
    COALESCE(e.sessions, 0),
    COALESCE(e.posts, 0),
    CASE WHEN COALESCE(e.sessions, 0) > 0
      THEN e.posts::NUMERIC / e.sessions
      ELSE NULL END,
    COALESCE(c.mood_pos, 0),
    COALESCE(c.mood_neg, 0),
    CASE WHEN COALESCE(c.total, 0) > 0 THEN
      (c.mood_pos - c.mood_neg)::NUMERIC / c.total
    ELSE NULL END
  FROM months m
  LEFT JOIN event_months e ON e.month_start = m.m
  LEFT JOIN confession_months c ON c.month_start = m.m
  ORDER BY m.m;
$$;

CREATE OR REPLACE FUNCTION public.get_emotion_fingerprint_v1(
  p_scope TEXT DEFAULT 'global', p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL,
  p_days INT DEFAULT 365, p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (month_start DATE, emotion TEXT, count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT date_trunc('month', c.created_at)::DATE, COALESCE(c.emotion_bucket,'unknown'), count(*)
  FROM public.confessions c
  WHERE c.created_at::DATE >= p_end_date - p_days
    AND (p_region IS NULL OR c.region = p_region)
    AND (p_country IS NULL OR c.country_code = p_country)
  GROUP BY 1, 2
  ORDER BY 1, 2;
$$;

CREATE OR REPLACE FUNCTION public.get_trends_movers_v1(
  p_scope TEXT DEFAULT 'global', p_region TEXT DEFAULT NULL, p_country TEXT DEFAULT NULL,
  p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (tag TEXT, current_7d BIGINT, baseline_28d NUMERIC, delta_pct NUMERIC, status TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH cur AS (
    SELECT emotion_bucket AS tag, count(*) AS c
    FROM public.confessions
    WHERE created_at::DATE BETWEEN p_end_date - 6 AND p_end_date
      AND (p_region IS NULL OR region = p_region)
      AND (p_country IS NULL OR country_code = p_country)
    GROUP BY emotion_bucket
  ), base AS (
    SELECT emotion_bucket AS tag, count(*) / 4.0 AS b
    FROM public.confessions
    WHERE created_at::DATE BETWEEN p_end_date - 34 AND p_end_date - 7
      AND (p_region IS NULL OR region = p_region)
      AND (p_country IS NULL OR country_code = p_country)
    GROUP BY emotion_bucket
  )
  SELECT
    cur.tag,
    cur.c,
    COALESCE(base.b, 0),
    CASE WHEN COALESCE(base.b, 0) > 0 THEN (cur.c - base.b) * 100.0 / base.b ELSE NULL END,
    CASE
      WHEN COALESCE(base.b, 0) < 1 AND cur.c >= 5 THEN 'emerging'
      WHEN cur.c >= COALESCE(base.b, 0) THEN 'rising'
      ELSE 'falling'
    END
  FROM cur
  LEFT JOIN base USING (tag)
  ORDER BY abs(COALESCE(CASE WHEN COALESCE(base.b, 0) > 0 THEN (cur.c - base.b) * 100.0 / base.b ELSE NULL END, 100)) DESC
  LIMIT 20;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.ad_policy_effective TO anon, authenticated;

COMMIT;
