-- ============================================================
-- ADD INTENT COLUMN TO CONFESSIONS
-- ============================================================
-- Run this in Supabase SQL Editor FIRST
-- Then run generate_demo_data.sql to populate with demo data
-- ============================================================

-- Step 1: Add intent column if it doesn't exist
ALTER TABLE confessions 
ADD COLUMN IF NOT EXISTS intent text;

-- Step 2: Add is_demo column if it doesn't exist (needed for demo data)
ALTER TABLE confessions 
ADD COLUMN IF NOT EXISTS is_demo boolean DEFAULT false;

-- Step 3: Add region column if it doesn't exist
ALTER TABLE confessions 
ADD COLUMN IF NOT EXISTS region text;

-- Step 4: Add language column if it doesn't exist
ALTER TABLE confessions 
ADD COLUMN IF NOT EXISTS language text DEFAULT 'en';

-- Verify columns exist
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'confessions'
ORDER BY ordinal_position;
