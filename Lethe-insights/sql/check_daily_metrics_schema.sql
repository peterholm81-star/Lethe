-- Check daily_metrics table schema
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'daily_metrics'
ORDER BY ordinal_position;
