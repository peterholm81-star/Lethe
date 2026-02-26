-- ============================================================
-- CREATE DAILY_READERS_WRITERS TABLE
-- ============================================================
-- Stores daily aggregated readers vs writers metrics
-- ============================================================

-- Create table
CREATE TABLE IF NOT EXISTS public.daily_readers_writers (
  day_bucket    date        NOT NULL,
  city_code     text        NOT NULL DEFAULT 'WORLD',
  region        text        NOT NULL DEFAULT 'WORLD',
  readers_today integer     NOT NULL DEFAULT 0,
  writers_today integer     NOT NULL DEFAULT 0,
  writer_share  numeric     NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (day_bucket, city_code, region)
);

-- Permissions
GRANT SELECT ON public.daily_readers_writers TO anon;
GRANT SELECT ON public.daily_readers_writers TO authenticated;

-- Insert demo data
INSERT INTO public.daily_readers_writers (day_bucket, city_code, region, readers_today, writers_today, writer_share)
VALUES ('2026-02-04', 'WORLD', 'WORLD', 100, 25, 0.25)
ON CONFLICT (day_bucket, city_code, region) DO UPDATE SET
  readers_today = EXCLUDED.readers_today,
  writers_today = EXCLUDED.writers_today,
  writer_share = EXCLUDED.writer_share;

-- Verify
SELECT * FROM public.daily_readers_writers;
