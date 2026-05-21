-- ============================================================================
-- Migration: Harden get_revenue_by_country_range
-- ============================================================================
-- Purpose:
--   Convert one real, read-only geo/revenue Insights aggregate RPC to the
--   production-safe admin model. This preserves the existing frontend RPC name,
--   parameters, and return columns while preventing anon access in production.
--
-- Notes:
--   The current production event_logs schema does not yet include country/region
--   enrichment or production ad policy tables. This function is intentionally
--   defensive: admins receive an empty result set until those production
--   migrations exist, while local/demo environments with those objects can still
--   compute the aggregate.
--
-- Scope:
--   - aggregate analytics only
--   - no public app/feed RPCs
--   - no moderation writes
--   - no monetization writes
--   - no frontend contract changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_revenue_by_country_range(
  p_start TIMESTAMPTZ,
  p_end TIMESTAMPTZ,
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
  country_code TEXT,
  sessions BIGINT,
  ad_impressions BIGINT,
  revenue_total NUMERIC,
  ad_revenue NUMERIC,
  premium_revenue NUMERIC,
  revenue_per_session NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  has_country_code BOOLEAN;
  has_region BOOLEAN;
  has_ad_policy BOOLEAN;
BEGIN
  -- Read-only Insights RPCs return an empty set for authenticated non-admins.
  -- Anon callers are denied by grants below before function execution.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  IF p_start IS NULL OR p_end IS NULL OR p_end <= p_start THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'event_logs'
      AND column_name = 'country_code'
  ) INTO has_country_code;

  -- Production cannot compute country aggregates until event_logs has country
  -- enrichment. Returning an empty set preserves the frontend contract without
  -- leaking raw analytics or depending on dev-only columns.
  IF NOT has_country_code THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'event_logs'
      AND column_name = 'region'
  ) INTO has_region;

  SELECT to_regclass('public.ad_policy_effective') IS NOT NULL
  INTO has_ad_policy;

  IF p_region IS NOT NULL AND NOT has_region THEN
    RETURN;
  END IF;

  IF has_ad_policy THEN
    IF has_region THEN
      RETURN QUERY EXECUTE
        'WITH aggregates AS (
          SELECT
            e.country_code,
            COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = ''session_start'') AS sessions,
            COUNT(*) FILTER (WHERE e.event_name = ''ad_shown'') AS ad_impressions
          FROM public.event_logs e
          WHERE e.created_at >= $1
            AND e.created_at < $2
            AND e.country_code IS NOT NULL
            AND ($3 IS NULL OR e.region = $3)
          GROUP BY e.country_code
        )
        SELECT
          a.country_code,
          a.sessions::BIGINT,
          a.ad_impressions::BIGINT,
          ROUND((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85), 4) AS revenue_total,
          ROUND((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85), 4) AS ad_revenue,
          0::NUMERIC AS premium_revenue,
          CASE
            WHEN a.sessions > 0 THEN ROUND(((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85)) / a.sessions, 6)
            ELSE 0
          END AS revenue_per_session
        FROM aggregates a
        LEFT JOIN public.ad_policy_effective p ON p.country_code = a.country_code
        ORDER BY revenue_total DESC, sessions DESC'
      USING p_start, p_end, p_region;
    ELSE
      RETURN QUERY EXECUTE
        'WITH aggregates AS (
          SELECT
            e.country_code,
            COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = ''session_start'') AS sessions,
            COUNT(*) FILTER (WHERE e.event_name = ''ad_shown'') AS ad_impressions
          FROM public.event_logs e
          WHERE e.created_at >= $1
            AND e.created_at < $2
            AND e.country_code IS NOT NULL
          GROUP BY e.country_code
        )
        SELECT
          a.country_code,
          a.sessions::BIGINT,
          a.ad_impressions::BIGINT,
          ROUND((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85), 4) AS revenue_total,
          ROUND((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85), 4) AS ad_revenue,
          0::NUMERIC AS premium_revenue,
          CASE
            WHEN a.sessions > 0 THEN ROUND(((a.ad_impressions::NUMERIC / 1000) * COALESCE(p.ecpm_nok, 18) * COALESCE(p.fill_rate, 0.85)) / a.sessions, 6)
            ELSE 0
          END AS revenue_per_session
        FROM aggregates a
        LEFT JOIN public.ad_policy_effective p ON p.country_code = a.country_code
        ORDER BY revenue_total DESC, sessions DESC'
      USING p_start, p_end;
    END IF;
  ELSE
    IF has_region THEN
      RETURN QUERY EXECUTE
        'WITH aggregates AS (
          SELECT
            e.country_code,
            COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = ''session_start'') AS sessions,
            COUNT(*) FILTER (WHERE e.event_name = ''ad_shown'') AS ad_impressions
          FROM public.event_logs e
          WHERE e.created_at >= $1
            AND e.created_at < $2
            AND e.country_code IS NOT NULL
            AND ($3 IS NULL OR e.region = $3)
          GROUP BY e.country_code
        )
        SELECT
          a.country_code,
          a.sessions::BIGINT,
          a.ad_impressions::BIGINT,
          ROUND((a.ad_impressions::NUMERIC / 1000) * 18 * 0.85, 4) AS revenue_total,
          ROUND((a.ad_impressions::NUMERIC / 1000) * 18 * 0.85, 4) AS ad_revenue,
          0::NUMERIC AS premium_revenue,
          CASE
            WHEN a.sessions > 0 THEN ROUND(((a.ad_impressions::NUMERIC / 1000) * 18 * 0.85) / a.sessions, 6)
            ELSE 0
          END AS revenue_per_session
        FROM aggregates a
        ORDER BY revenue_total DESC, sessions DESC'
      USING p_start, p_end, p_region;
    ELSE
      RETURN QUERY EXECUTE
        'WITH aggregates AS (
          SELECT
            e.country_code,
            COUNT(DISTINCT e.session_hash) FILTER (WHERE e.event_name = ''session_start'') AS sessions,
            COUNT(*) FILTER (WHERE e.event_name = ''ad_shown'') AS ad_impressions
          FROM public.event_logs e
          WHERE e.created_at >= $1
            AND e.created_at < $2
            AND e.country_code IS NOT NULL
          GROUP BY e.country_code
        )
        SELECT
          a.country_code,
          a.sessions::BIGINT,
          a.ad_impressions::BIGINT,
          ROUND((a.ad_impressions::NUMERIC / 1000) * 18 * 0.85, 4) AS revenue_total,
          ROUND((a.ad_impressions::NUMERIC / 1000) * 18 * 0.85, 4) AS ad_revenue,
          0::NUMERIC AS premium_revenue,
          CASE
            WHEN a.sessions > 0 THEN ROUND(((a.ad_impressions::NUMERIC / 1000) * 18 * 0.85) / a.sessions, 6)
            ELSE 0
          END AS revenue_per_session
        FROM aggregates a
        ORDER BY revenue_total DESC, sessions DESC'
      USING p_start, p_end;
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.get_revenue_by_country_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT
) IS
  'Admin-gated production Insights RPC for read-only revenue-by-country analytics. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.get_revenue_by_country_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.get_revenue_by_country_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.get_revenue_by_country_range(
  TIMESTAMPTZ,
  TIMESTAMPTZ,
  TEXT
) TO authenticated;

-- ============================================================================
-- Verification notes (run manually in local/staging)
-- ============================================================================
--
-- 1. Anon REST caller:
--    Expected: permission denied because anon has no EXECUTE grant.
--
-- 2. Authenticated non-admin:
--    Expected: empty result set.
--
--      SELECT * FROM public.get_revenue_by_country_range(
--        now() - interval '30 days',
--        now(),
--        NULL
--      );
--
-- 3. Authenticated admin:
--    Insert auth.uid() into public.admin_users using SQL owner/service-role
--    privileges, then call as that authenticated user.
--
--      SELECT * FROM public.get_revenue_by_country_range(
--        now() - interval '30 days',
--        now(),
--        NULL
--      );
--      -- expected: revenue aggregate rows when country enrichment exists;
--      -- otherwise an empty set until geo/revenue production migrations land.
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
