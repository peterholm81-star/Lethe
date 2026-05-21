-- =============================================================================
-- Migration 035: Harden public.get_reports_groups
--
-- Phase: Production Hardening Phase 2 — HIGH-risk read RPCs (raw content)
--
-- Purpose:
--   Replace the open (anon-accessible) dev-seed version of get_reports_groups
--   with a production-safe, admin-gated read RPC.
--
--   This RPC groups reports by confession and returns raw confession text
--   (max(text) AS confession_text). That content is acceptable only for
--   authenticated Insights admins performing moderation. Anon and
--   authenticated non-admins must receive zero rows, not an error.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive an empty result set (RETURN)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Anon callers are denied by grants before the function body runs
--   - Language changed from sql to plpgsql to support the admin gate;
--     all CTE logic, return columns, and ordering are preserved exactly
--
-- Frontend contract preserved:
--   - Same name: get_reports_groups
--   - Same parameters (all five, with same defaults):
--       p_limit integer DEFAULT 50
--       p_only_unhandled boolean DEFAULT true
--       p_reason text DEFAULT NULL
--       p_visibility text DEFAULT NULL
--       p_sort text DEFAULT 'last_reported_desc'
--   - Same return columns and types (all 11 columns in same order):
--       confession_id uuid
--       confession_text text
--       confession_region text
--       confession_is_hidden boolean
--       total_reports bigint
--       unhandled_reports bigint
--       handled_all boolean
--       first_reported_at timestamptz
--       last_reported_at timestamptz
--       reason_breakdown_json jsonb
--       report_city_code_sample text
--   - Frontend (useReportGroups.ts) handles an empty array gracefully:
--       setGroups(rows as ReportGroup[]) → renders empty groups list
--
-- Production safety:
--   - Raw confession text is exposed only to authenticated admin users
--   - Anon access is blocked by grants before the function body executes
--   - Non-admin authenticated users receive zero rows (not an error)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_groups(
  p_limit          INTEGER DEFAULT 50,
  p_only_unhandled BOOLEAN DEFAULT true,
  p_reason         TEXT    DEFAULT NULL,
  p_visibility     TEXT    DEFAULT NULL,
  p_sort           TEXT    DEFAULT 'last_reported_desc'
)
RETURNS TABLE(
  confession_id          UUID,
  confession_text        TEXT,
  confession_region      TEXT,
  confession_is_hidden   BOOLEAN,
  total_reports          BIGINT,
  unhandled_reports      BIGINT,
  handled_all            BOOLEAN,
  first_reported_at      TIMESTAMPTZ,
  last_reported_at       TIMESTAMPTZ,
  reason_breakdown_json  JSONB,
  report_city_code_sample TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — raw confession text and
  -- moderation grouping data must not be visible outside the admin boundary.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH r AS (
    SELECT r.*, c.text, c.region, c.is_hidden, c.city_code
    FROM public.reports r
    JOIN public.confessions c ON c.id = r.confession_id
    WHERE (p_reason IS NULL OR r.reason = p_reason)
      AND (p_visibility IS NULL
           OR (p_visibility = 'hidden'  AND     COALESCE(c.is_hidden, false))
           OR (p_visibility = 'visible' AND NOT COALESCE(c.is_hidden, false)))
  ), g AS (
    SELECT
      x.confession_id,
      max(x.text)                                                         AS text,
      max(x.region)                                                       AS region,
      bool_or(COALESCE(x.is_hidden, false))                              AS is_hidden,
      count(*)                                                            AS total_reports,
      count(*) FILTER (WHERE x.status = 'open')                          AS unhandled_reports,
      bool_and(x.status <> 'open')                                       AS handled_all,
      min(x.created_at)                                                   AS first_reported_at,
      max(x.created_at)                                                   AS last_reported_at,
      COALESCE(jsonb_object_agg(x.reason, x.reason_count), '{}'::jsonb) AS reason_breakdown_json,
      max(x.city_code)                                                    AS report_city_code_sample
    FROM (
      SELECT r.*,
             count(*) OVER (PARTITION BY r.confession_id, r.reason) AS reason_count
      FROM r
    ) x
    GROUP BY x.confession_id
  )
  SELECT
    g.confession_id,
    g.text,
    g.region,
    g.is_hidden,
    g.total_reports,
    g.unhandled_reports,
    g.handled_all,
    g.first_reported_at,
    g.last_reported_at,
    g.reason_breakdown_json,
    g.report_city_code_sample
  FROM g
  WHERE (NOT p_only_unhandled OR g.unhandled_reports > 0)
  ORDER BY
    CASE WHEN p_sort = 'total_reports_desc'      THEN g.total_reports      END DESC,
    CASE WHEN p_sort = 'unhandled_reports_desc'  THEN g.unhandled_reports  END DESC,
    g.last_reported_at DESC
  LIMIT p_limit;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read grouped moderation data.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_reports_groups(INTEGER, BOOLEAN, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_groups(INTEGER, BOOLEAN, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_groups(INTEGER, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;

-- =============================================================================
-- Verification notes (run manually against local DB to confirm):
--
-- 1. Anon blocked by grant:
--    SET ROLE anon;
--    SELECT * FROM public.get_reports_groups();
--    -- Expected: ERROR 42501 permission denied for function get_reports_groups
--
-- 2. Authenticated non-admin receives zero rows:
--    SET LOCAL ROLE authenticated;
--    SELECT count(*) FROM public.get_reports_groups();
--    -- Expected: 0
--
-- 3. Authenticated admin receives grouped rows with confession text:
--    INSERT INTO public.admin_users (user_id) VALUES ('<admin-uuid>');
--    SELECT count(*), bool_or(confession_text IS NOT NULL)
--    FROM public.get_reports_groups();
--    -- Expected: count > 0, confession_text present = true
--    DELETE FROM public.admin_users WHERE user_id = '<admin-uuid>';
-- =============================================================================
