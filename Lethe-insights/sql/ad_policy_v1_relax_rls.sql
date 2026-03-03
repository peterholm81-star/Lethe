-- =============================================================================
-- AD POLICY V1 - RELAX RLS (Remove Admin Requirement)
-- =============================================================================
-- 
-- Purpose:
--   Simplify ad policy management by removing admin_users dependency.
--   Lethe Insights is single-user, so all authenticated/anon users can manage policy.
--
-- Changes:
--   - DROP admin-only INSERT/UPDATE/DELETE policies
--   - CREATE open policies for anon + authenticated
--   - ad_policy_default: allow UPDATE only (single-row constraint via PK)
--   - ad_policy_country: allow full CRUD
--
-- =============================================================================

-- =============================================================================
-- 1) DROP EXISTING ADMIN-ONLY POLICIES
-- =============================================================================

DROP POLICY IF EXISTS "ad_policy_default_admin_insert" ON ad_policy_default;
DROP POLICY IF EXISTS "ad_policy_default_admin_update" ON ad_policy_default;
DROP POLICY IF EXISTS "ad_policy_default_admin_delete" ON ad_policy_default;

DROP POLICY IF EXISTS "ad_policy_country_admin_insert" ON ad_policy_country;
DROP POLICY IF EXISTS "ad_policy_country_admin_update" ON ad_policy_country;
DROP POLICY IF EXISTS "ad_policy_country_admin_delete" ON ad_policy_country;

-- =============================================================================
-- 2) CREATE OPEN POLICIES FOR ad_policy_default
-- =============================================================================

-- UPDATE: Allow anyone to update the single default row
CREATE POLICY "ad_policy_default_update_open"
  ON ad_policy_default
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

-- DELETE: Allow delete (though typically not needed)
CREATE POLICY "ad_policy_default_delete_open"
  ON ad_policy_default
  FOR DELETE
  TO anon, authenticated
  USING (true);

-- INSERT: Allow insert (PK constraint ensures only one row can exist)
-- If you want to be extra safe, you can skip this and only allow UPDATE
CREATE POLICY "ad_policy_default_insert_open"
  ON ad_policy_default
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    -- Only allow insert if no rows exist (single-row enforcement)
    NOT EXISTS (SELECT 1 FROM ad_policy_default)
  );

-- =============================================================================
-- 3) CREATE OPEN POLICIES FOR ad_policy_country
-- =============================================================================

-- INSERT: Allow anyone to insert country overrides
CREATE POLICY "ad_policy_country_insert_open"
  ON ad_policy_country
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- UPDATE: Allow anyone to update country overrides
CREATE POLICY "ad_policy_country_update_open"
  ON ad_policy_country
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

-- DELETE: Allow anyone to delete country overrides
CREATE POLICY "ad_policy_country_delete_open"
  ON ad_policy_country
  FOR DELETE
  TO anon, authenticated
  USING (true);

-- =============================================================================
-- 4) GRANTS (ensure anon/authenticated can write)
-- =============================================================================

-- ad_policy_default: full access (INSERT constrained by policy above)
GRANT INSERT, UPDATE, DELETE ON ad_policy_default TO anon, authenticated;

-- ad_policy_country: full access
GRANT INSERT, UPDATE, DELETE ON ad_policy_country TO anon, authenticated;

-- =============================================================================
-- 5) NOTIFY POSTGREST TO RELOAD SCHEMA
-- =============================================================================

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 6) VERIFICATION QUERIES (run manually to test)
-- =============================================================================

/*
-- Test 1: Check default row exists
SELECT * FROM ad_policy_default;

-- Test 2: Upsert country policy for US with cap=3
INSERT INTO ad_policy_country (country_code, ads_per_session_cap)
VALUES ('US', 3)
ON CONFLICT (country_code) 
DO UPDATE SET ads_per_session_cap = EXCLUDED.ads_per_session_cap;

-- Test 3: Verify effective policy shows override
SELECT * FROM ad_policy_effective WHERE country_code = 'US';
-- Should show: source = 'override', ads_per_session_cap = 3
*/
