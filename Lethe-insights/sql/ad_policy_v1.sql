-- =============================================================================
-- AD POLICY V1 - Per-Country Monetization Policy Layer
-- =============================================================================
-- 
-- Purpose:
--   Provides configurable ad policy settings per country, allowing admins to
--   apply monetization recommendations from country_monetization_optimization_v1.
--
-- Tables:
--   - ad_policy_default: Single-row global default settings
--   - ad_policy_country: Per-country overrides
--
-- Views:
--   - ad_policy_effective: Computed effective policy for all known countries
--
-- Security:
--   - RLS enabled on both tables
--   - SELECT allowed for anon/authenticated (config is public)
--   - INSERT/UPDATE/DELETE restricted to admins only
--
-- Dependencies:
--   - country_monetization_optimization_v1 (for country list)
--   - admin_users table (for admin checks)
--
-- =============================================================================

-- =============================================================================
-- 1) TABLES
-- =============================================================================

-- Drop existing if needed (safe for development, remove in prod migrations)
DROP TABLE IF EXISTS ad_policy_country CASCADE;
DROP TABLE IF EXISTS ad_policy_default CASCADE;

-- Global default policy (single row)
CREATE TABLE ad_policy_default (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ads_per_session_cap int NOT NULL DEFAULT 1,
  trigger_pages int NOT NULL DEFAULT 6,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Per-country override policy
CREATE TABLE ad_policy_country (
  country_code text PRIMARY KEY,
  ads_per_session_cap int NULL,
  trigger_pages int NULL,
  enabled boolean NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add helpful comments
COMMENT ON TABLE ad_policy_default IS 'Global default ad policy settings (single row)';
COMMENT ON TABLE ad_policy_country IS 'Per-country ad policy overrides';

COMMENT ON COLUMN ad_policy_default.ads_per_session_cap IS 'Maximum ads shown per user session';
COMMENT ON COLUMN ad_policy_default.trigger_pages IS 'Number of page views before first ad';
COMMENT ON COLUMN ad_policy_default.enabled IS 'Whether ads are enabled globally';

COMMENT ON COLUMN ad_policy_country.ads_per_session_cap IS 'Override: max ads per session (NULL = use default)';
COMMENT ON COLUMN ad_policy_country.trigger_pages IS 'Override: pages before first ad (NULL = use default)';
COMMENT ON COLUMN ad_policy_country.enabled IS 'Override: ads enabled (NULL = use default)';

-- =============================================================================
-- 2) ENSURE DEFAULT ROW EXISTS
-- =============================================================================

INSERT INTO ad_policy_default (ads_per_session_cap, trigger_pages, enabled)
SELECT 1, 6, true
WHERE NOT EXISTS (SELECT 1 FROM ad_policy_default);

-- =============================================================================
-- 3) EFFECTIVE POLICY VIEW
-- =============================================================================

DROP VIEW IF EXISTS ad_policy_effective;

CREATE OR REPLACE VIEW ad_policy_effective AS
WITH 
  -- Get all known country codes from optimization view
  known_countries AS (
    SELECT DISTINCT country_code
    FROM country_monetization_optimization_v1
    WHERE country_code IS NOT NULL
  ),
  -- Get the single default row
  defaults AS (
    SELECT 
      ads_per_session_cap,
      trigger_pages,
      enabled,
      updated_at
    FROM ad_policy_default
    LIMIT 1
  )
SELECT
  kc.country_code,
  COALESCE(ovr.ads_per_session_cap, def.ads_per_session_cap) AS ads_per_session_cap,
  COALESCE(ovr.trigger_pages, def.trigger_pages) AS trigger_pages,
  COALESCE(ovr.enabled, def.enabled) AS enabled,
  CASE 
    WHEN ovr.country_code IS NOT NULL THEN 'override'::text
    ELSE 'default'::text
  END AS source,
  GREATEST(
    COALESCE(ovr.updated_at, '1970-01-01'::timestamptz),
    def.updated_at
  ) AS updated_at
FROM known_countries kc
CROSS JOIN defaults def
LEFT JOIN ad_policy_country ovr ON ovr.country_code = kc.country_code
ORDER BY kc.country_code;

COMMENT ON VIEW ad_policy_effective IS 'Computed effective ad policy per country (override merged with defaults)';

-- =============================================================================
-- 4) ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS
ALTER TABLE ad_policy_default ENABLE ROW LEVEL SECURITY;
ALTER TABLE ad_policy_country ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (safe for re-runs)
DROP POLICY IF EXISTS "ad_policy_default_select" ON ad_policy_default;
DROP POLICY IF EXISTS "ad_policy_default_admin_insert" ON ad_policy_default;
DROP POLICY IF EXISTS "ad_policy_default_admin_update" ON ad_policy_default;
DROP POLICY IF EXISTS "ad_policy_default_admin_delete" ON ad_policy_default;

DROP POLICY IF EXISTS "ad_policy_country_select" ON ad_policy_country;
DROP POLICY IF EXISTS "ad_policy_country_admin_insert" ON ad_policy_country;
DROP POLICY IF EXISTS "ad_policy_country_admin_update" ON ad_policy_country;
DROP POLICY IF EXISTS "ad_policy_country_admin_delete" ON ad_policy_country;

-- SELECT: Allow all (config is public)
CREATE POLICY "ad_policy_default_select"
  ON ad_policy_default
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "ad_policy_country_select"
  ON ad_policy_country
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- INSERT/UPDATE/DELETE: Admin only
-- Admin check: user must exist in admin_users table

CREATE POLICY "ad_policy_default_admin_insert"
  ON ad_policy_default
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  );

CREATE POLICY "ad_policy_default_admin_update"
  ON ad_policy_default
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  );

CREATE POLICY "ad_policy_default_admin_delete"
  ON ad_policy_default
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  );

CREATE POLICY "ad_policy_country_admin_insert"
  ON ad_policy_country
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  );

CREATE POLICY "ad_policy_country_admin_update"
  ON ad_policy_country
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  );

CREATE POLICY "ad_policy_country_admin_delete"
  ON ad_policy_country
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
  );

-- =============================================================================
-- 5) GRANTS
-- =============================================================================

-- View: SELECT for all
GRANT SELECT ON ad_policy_effective TO anon, authenticated;

-- Tables: SELECT for all (RLS protects writes)
GRANT SELECT ON ad_policy_default TO anon, authenticated;
GRANT SELECT ON ad_policy_country TO anon, authenticated;

-- Tables: Full access for authenticated (RLS will enforce admin check)
GRANT INSERT, UPDATE, DELETE ON ad_policy_default TO authenticated;
GRANT INSERT, UPDATE, DELETE ON ad_policy_country TO authenticated;

-- =============================================================================
-- 6) AUTO-UPDATE updated_at TRIGGER
-- =============================================================================

-- Function to auto-update updated_at
CREATE OR REPLACE FUNCTION update_ad_policy_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers
DROP TRIGGER IF EXISTS ad_policy_default_updated_at ON ad_policy_default;
CREATE TRIGGER ad_policy_default_updated_at
  BEFORE UPDATE ON ad_policy_default
  FOR EACH ROW
  EXECUTE FUNCTION update_ad_policy_updated_at();

DROP TRIGGER IF EXISTS ad_policy_country_updated_at ON ad_policy_country;
CREATE TRIGGER ad_policy_country_updated_at
  BEFORE UPDATE ON ad_policy_country
  FOR EACH ROW
  EXECUTE FUNCTION update_ad_policy_updated_at();

-- =============================================================================
-- 7) NOTIFY POSTGREST TO RELOAD SCHEMA
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- VERIFICATION QUERIES (run manually to test)
-- =============================================================================
/*

-- Check default row exists:
SELECT * FROM ad_policy_default;

-- Check effective view (should show all countries from optimization):
SELECT * FROM ad_policy_effective ORDER BY country_code LIMIT 10;

-- Test insert override (as admin):
INSERT INTO ad_policy_country (country_code, ads_per_session_cap)
VALUES ('US', 2)
ON CONFLICT (country_code) DO UPDATE SET ads_per_session_cap = EXCLUDED.ads_per_session_cap;

-- Verify override appears:
SELECT * FROM ad_policy_effective WHERE country_code = 'US';

-- Clean up test:
DELETE FROM ad_policy_country WHERE country_code = 'US';

*/
