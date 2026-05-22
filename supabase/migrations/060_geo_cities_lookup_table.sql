-- =============================================================================
-- Migration 060: geo_cities lookup table
-- =============================================================================
-- Promotes the 25-city dev_seed dataset to a permanent production lookup table.
-- Used by insert_confession (migration 061) for nearest-city reverse geocoding.
--
-- Design:
--   - Static reference data; no writes after seeding
--   - No enrichment, no triggers
--   - SECURITY DEFINER RPCs (postgres-owned) bypass RLS; policy added for
--     transparency and any future direct queries
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.geo_cities (
  city_code    TEXT             PRIMARY KEY,
  city_label   TEXT             NOT NULL,
  region       TEXT             NOT NULL,
  country_code TEXT             NOT NULL,
  lat          DOUBLE PRECISION NOT NULL,
  lng          DOUBLE PRECISION NOT NULL
);

ALTER TABLE public.geo_cities ENABLE ROW LEVEL SECURITY;

-- Reference data is intentionally public — no personal data here.
CREATE POLICY "geo_cities_public_read"
  ON public.geo_cities
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Btree index on (lat, lng) for Haversine ORDER BY distance queries.
CREATE INDEX IF NOT EXISTS geo_cities_lat_lng_idx
  ON public.geo_cities (lat, lng);

-- ---------------------------------------------------------------------------
-- Static 25-city dataset — exact match for the dev_seed_cities model.
-- Conflicts are silently ignored so re-applying is safe.
-- ---------------------------------------------------------------------------
INSERT INTO public.geo_cities (city_code, city_label, region, country_code, lat, lng)
VALUES
  ('OSL', 'Oslo',          'Europe',        'NO',  59.9139,   10.7522),
  ('MEL', 'Melandsjo',     'Europe',        'NO',  63.5437,    8.4922),
  ('LON', 'London',        'Europe',        'GB',  51.5074,   -0.1278),
  ('PAR', 'Paris',         'Europe',        'FR',  48.8566,    2.3522),
  ('BER', 'Berlin',        'Europe',        'DE',  52.5200,   13.4050),
  ('MAD', 'Madrid',        'Europe',        'ES',  40.4168,   -3.7038),
  ('NYC', 'New York',      'North America', 'US',  40.7128,  -74.0060),
  ('LAX', 'Los Angeles',   'North America', 'US',  34.0522, -118.2437),
  ('TOR', 'Toronto',       'North America', 'CA',  43.6532,  -79.3832),
  ('MEX', 'Mexico City',   'North America', 'MX',  19.4326,  -99.1332),
  ('SAO', 'Sao Paulo',     'South America', 'BR', -23.5558,  -46.6396),
  ('BUE', 'Buenos Aires',  'South America', 'AR', -34.6037,  -58.3816),
  ('BOG', 'Bogota',        'South America', 'CO',   4.7110,  -74.0721),
  ('TYO', 'Tokyo',         'Asia',          'JP',  35.6762,  139.6503),
  ('SEL', 'Seoul',         'Asia',          'KR',  37.5665,  126.9780),
  ('SIN', 'Singapore',     'Asia',          'SG',   1.3521,  103.8198),
  ('BOM', 'Mumbai',        'Asia',          'IN',  19.0760,   72.8777),
  ('CPT', 'Cape Town',     'Africa',        'ZA', -33.9249,   18.4241),
  ('LOS', 'Lagos',         'Africa',        'NG',   6.5244,    3.3792),
  ('NBO', 'Nairobi',       'Africa',        'KE',  -1.2921,   36.8219),
  ('SYD', 'Sydney',        'Oceania',       'AU', -33.8688,  151.2093),
  ('AKL', 'Auckland',      'Oceania',       'NZ', -36.8509,  174.7645),
  ('DXB', 'Dubai',         'Middle East',   'AE',  25.2048,   55.2708),
  ('TLV', 'Tel Aviv',      'Middle East',   'IL',  32.0853,   34.7818),
  ('RUH', 'Riyadh',        'Middle East',   'SA',  24.7136,   46.6753)
ON CONFLICT (city_code) DO NOTHING;
