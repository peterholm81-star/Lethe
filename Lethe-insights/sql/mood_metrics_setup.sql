-- =============================================================================
-- MOOD METRICS: Database Layer for Lethe Insights
-- =============================================================================
--
-- Privacy-first aggregated metrics for mood tracking.
-- No PII stored - only counts per dimension combination.
--
-- DEPLOY: Run this file in Supabase SQL Editor (as service role).
--
-- =============================================================================

-- =============================================================================
-- 1. CREATE TABLE: confession_metrics_daily
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.confession_metrics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Dimensions
  date date NOT NULL,
  time_bucket text NOT NULL,           -- 'night' | 'morning' | 'afternoon' | 'evening'
  region text NOT NULL,                -- 'Europe', 'Asia', etc. or 'Unknown'
  country_code text NOT NULL,          -- ISO2 code or 'Unknown'
  city_code text NOT NULL,             -- Internal code or 'Unknown'
  mood_bucket text NOT NULL,           -- One of 12 mood buckets
  
  -- Metric
  count bigint NOT NULL DEFAULT 0,
  
  -- Timestamps
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  -- Constraints
  CONSTRAINT confession_metrics_daily_time_bucket_check CHECK (
    time_bucket IN ('night', 'morning', 'afternoon', 'evening')
  ),
  CONSTRAINT confession_metrics_daily_mood_bucket_check CHECK (
    mood_bucket IN (
      'joy', 'love', 'calm', 'hope', 'gratitude', 'confidence',
      'anxiety', 'sadness', 'anger', 'loneliness', 'desire', 'shame'
    )
  ),
  CONSTRAINT confession_metrics_daily_count_non_negative CHECK (count >= 0)
);

-- Table comment
COMMENT ON TABLE public.confession_metrics_daily IS 
  'Aggregated daily mood metrics. Privacy-first: no PII, only counts per dimension.';

-- =============================================================================
-- 2. UNIQUE CONSTRAINT: One row per dimension combination
-- =============================================================================

ALTER TABLE public.confession_metrics_daily
  DROP CONSTRAINT IF EXISTS confession_metrics_daily_unique_dims;

ALTER TABLE public.confession_metrics_daily
  ADD CONSTRAINT confession_metrics_daily_unique_dims
  UNIQUE (date, time_bucket, region, country_code, city_code, mood_bucket);

-- =============================================================================
-- 3. INDEXES: Support typical Insights queries
-- =============================================================================

-- Primary query pattern: date range + optional geo filters
CREATE INDEX IF NOT EXISTS idx_cmd_date_region
  ON public.confession_metrics_daily (date DESC, region);

CREATE INDEX IF NOT EXISTS idx_cmd_date_country
  ON public.confession_metrics_daily (date DESC, country_code);

CREATE INDEX IF NOT EXISTS idx_cmd_date_city
  ON public.confession_metrics_daily (date DESC, city_code);

-- Mood breakdown queries
CREATE INDEX IF NOT EXISTS idx_cmd_date_mood
  ON public.confession_metrics_daily (date DESC, mood_bucket);

-- Full dimension lookup (for upsert performance)
CREATE INDEX IF NOT EXISTS idx_cmd_dimensions
  ON public.confession_metrics_daily (date, time_bucket, region, country_code, city_code, mood_bucket);

-- =============================================================================
-- 4. TRIGGER: Auto-update updated_at on UPDATE
-- =============================================================================

-- Function to update timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS trg_confession_metrics_daily_updated_at 
  ON public.confession_metrics_daily;

-- Create trigger
CREATE TRIGGER trg_confession_metrics_daily_updated_at
  BEFORE UPDATE ON public.confession_metrics_daily
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 5. ROW LEVEL SECURITY: Lock down access
-- =============================================================================

ALTER TABLE public.confession_metrics_daily ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS cmd_select_service ON public.confession_metrics_daily;
DROP POLICY IF EXISTS cmd_insert_service ON public.confession_metrics_daily;
DROP POLICY IF EXISTS cmd_update_service ON public.confession_metrics_daily;

-- Policy: Only service_role can SELECT (for now)
-- We'll create a read RPC later that uses SECURITY DEFINER
CREATE POLICY cmd_select_service ON public.confession_metrics_daily
  FOR SELECT
  TO service_role
  USING (true);

-- Policy: Only service_role can INSERT
CREATE POLICY cmd_insert_service ON public.confession_metrics_daily
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Policy: Only service_role can UPDATE
CREATE POLICY cmd_update_service ON public.confession_metrics_daily
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- No DELETE policy = no one can delete (except superuser)

-- Revoke direct access from anon and authenticated
REVOKE ALL ON public.confession_metrics_daily FROM anon;
REVOKE ALL ON public.confession_metrics_daily FROM authenticated;

-- Grant to service_role (for Edge Functions)
GRANT SELECT, INSERT, UPDATE ON public.confession_metrics_daily TO service_role;

-- =============================================================================
-- 6. RPC: rpc_increment_confession_metric
-- =============================================================================

-- Drop existing function if exists
DROP FUNCTION IF EXISTS public.rpc_increment_confession_metric(date, text, text, text, text, text, bigint);

CREATE OR REPLACE FUNCTION public.rpc_increment_confession_metric(
  p_date date,
  p_time_bucket text,
  p_region text,
  p_country_code text,
  p_city_code text,
  p_mood_bucket text,
  p_increment bigint DEFAULT 1
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_valid_moods text[] := ARRAY[
    'joy', 'love', 'calm', 'hope', 'gratitude', 'confidence',
    'anxiety', 'sadness', 'anger', 'loneliness', 'desire', 'shame'
  ];
  v_valid_time_buckets text[] := ARRAY['night', 'morning', 'afternoon', 'evening'];
  v_new_count bigint;
  v_region text;
  v_country_code text;
  v_city_code text;
BEGIN
  -- ==========================================================================
  -- VALIDATION
  -- ==========================================================================
  
  -- Validate mood_bucket
  IF p_mood_bucket IS NULL OR NOT (p_mood_bucket = ANY(v_valid_moods)) THEN
    RAISE EXCEPTION 'Invalid mood_bucket: %. Must be one of: %', 
      COALESCE(p_mood_bucket, 'NULL'), 
      array_to_string(v_valid_moods, ', ');
  END IF;
  
  -- Validate time_bucket
  IF p_time_bucket IS NULL OR NOT (p_time_bucket = ANY(v_valid_time_buckets)) THEN
    RAISE EXCEPTION 'Invalid time_bucket: %. Must be one of: %', 
      COALESCE(p_time_bucket, 'NULL'), 
      array_to_string(v_valid_time_buckets, ', ');
  END IF;
  
  -- Validate date
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'date cannot be NULL';
  END IF;
  
  -- Validate increment
  IF p_increment IS NULL OR p_increment < 1 THEN
    RAISE EXCEPTION 'increment must be >= 1, got: %', COALESCE(p_increment::text, 'NULL');
  END IF;
  
  -- ==========================================================================
  -- NORMALIZE INPUTS
  -- ==========================================================================
  
  -- Normalize geo fields: NULL or empty -> 'Unknown'
  v_region := COALESCE(NULLIF(TRIM(p_region), ''), 'Unknown');
  v_country_code := COALESCE(NULLIF(TRIM(p_country_code), ''), 'Unknown');
  v_city_code := COALESCE(NULLIF(TRIM(p_city_code), ''), 'Unknown');
  
  -- ==========================================================================
  -- UPSERT: Insert or increment
  -- ==========================================================================
  
  INSERT INTO public.confession_metrics_daily (
    date,
    time_bucket,
    region,
    country_code,
    city_code,
    mood_bucket,
    count
  ) VALUES (
    p_date,
    p_time_bucket,
    v_region,
    v_country_code,
    v_city_code,
    p_mood_bucket,
    p_increment
  )
  ON CONFLICT (date, time_bucket, region, country_code, city_code, mood_bucket)
  DO UPDATE SET
    count = confession_metrics_daily.count + EXCLUDED.count
  RETURNING count INTO v_new_count;
  
  RETURN v_new_count;
END;
$$;

-- Comment
COMMENT ON FUNCTION public.rpc_increment_confession_metric IS 
  'Atomically increments a mood metric counter. For use by Edge Functions only.';

-- Grant execute ONLY to service_role (Edge Functions)
REVOKE ALL ON FUNCTION public.rpc_increment_confession_metric(date, text, text, text, text, text, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_increment_confession_metric(date, text, text, text, text, text, bigint) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_increment_confession_metric(date, text, text, text, text, text, bigint) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_increment_confession_metric(date, text, text, text, text, text, bigint) TO service_role;

-- =============================================================================
-- 7. NOTIFY POSTGREST TO RELOAD SCHEMA
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- DONE
-- =============================================================================
-- See test queries below for verification.
