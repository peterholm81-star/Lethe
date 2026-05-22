-- Setup: insert an admin user and test data
INSERT INTO public.admin_users (user_id) VALUES ('11111111-1111-1111-1111-111111111111')
ON CONFLICT DO NOTHING;

-- Verify confessions table does NOT have region/city_code in this state
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'confessions'
  AND column_name IN ('region', 'country_code', 'city_code', 'emotion_bucket')
ORDER BY column_name;
