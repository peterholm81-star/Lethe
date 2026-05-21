-- ============================================================================
-- Migration: Harden rpc_get_mood_summary
-- ============================================================================
-- Purpose:
--   Convert one real, read-only Mood Insights aggregate RPC to the
--   production-safe admin model. This preserves the existing frontend RPC name,
--   parameters, and return columns while preventing anon access in production.
--
-- Notes:
--   Local/demo environments enrich confessions with emotion/geo columns. The
--   current production schema does not yet include those confession columns, but
--   event_logs does include emotion_bucket and city_code. This function uses
--   confession mood data when available and falls back safely to event-log mood
--   buckets in production.
--
-- Scope:
--   - aggregate analytics only
--   - no public app/feed RPCs
--   - no moderation writes
--   - no monetization writes
--   - no frontend contract changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_mood_summary(
  p_start_date DATE,
  p_end_date DATE,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL
)
RETURNS TABLE (
  mood_bucket TEXT,
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  has_confession_emotion BOOLEAN;
  has_confession_region BOOLEAN;
  has_confession_country BOOLEAN;
  has_confession_city BOOLEAN;
  has_event_region BOOLEAN;
  has_event_country BOOLEAN;
BEGIN
  -- Read-only Insights RPCs return an empty set for authenticated non-admins.
  -- Anon callers are denied by grants below before function execution.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'confessions'
      AND column_name = 'emotion_bucket'
  ) INTO has_confession_emotion;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'confessions'
      AND column_name = 'region'
  ) INTO has_confession_region;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'confessions'
      AND column_name = 'country_code'
  ) INTO has_confession_country;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'confessions'
      AND column_name = 'city_code'
  ) INTO has_confession_city;

  IF has_confession_emotion THEN
    IF p_region IS NOT NULL AND NOT has_confession_region THEN
      RETURN;
    END IF;

    IF p_country_code IS NOT NULL AND NOT has_confession_country THEN
      RETURN;
    END IF;

    IF p_city_code IS NOT NULL AND NOT has_confession_city THEN
      RETURN;
    END IF;

    RETURN QUERY EXECUTE
      'SELECT
        COALESCE(c.emotion_bucket, ''unknown'')::TEXT AS mood_bucket,
        COUNT(*)::BIGINT AS total_count
      FROM public.confessions c
      WHERE c.created_at::DATE >= $1
        AND c.created_at::DATE <= $2
        AND ($3 IS NULL OR c.region = $3)
        AND ($4 IS NULL OR c.country_code = $4)
        AND ($5 IS NULL OR c.city_code = $5)
      GROUP BY 1
      ORDER BY 2 DESC'
    USING p_start_date, p_end_date, p_region, p_country_code, p_city_code;

    RETURN;
  END IF;

  -- Production fallback: event_logs has emotion_bucket and city_code, but not
  -- region/country enrichment yet. Preserve filter parameters by returning an
  -- empty set when unsupported region/country filters are requested.
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'event_logs'
      AND column_name = 'region'
  ) INTO has_event_region;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'event_logs'
      AND column_name = 'country_code'
  ) INTO has_event_country;

  IF p_region IS NOT NULL AND NOT has_event_region THEN
    RETURN;
  END IF;

  IF p_country_code IS NOT NULL AND NOT has_event_country THEN
    RETURN;
  END IF;

  IF has_event_region AND has_event_country THEN
    RETURN QUERY EXECUTE
      'SELECT
        COALESCE(el.emotion_bucket, ''unknown'')::TEXT AS mood_bucket,
        COUNT(*)::BIGINT AS total_count
      FROM public.event_logs el
      WHERE el.created_at::DATE >= $1
        AND el.created_at::DATE <= $2
        AND el.emotion_bucket IS NOT NULL
        AND ($3 IS NULL OR el.region = $3)
        AND ($4 IS NULL OR el.country_code = $4)
        AND ($5 IS NULL OR el.city_code = $5)
      GROUP BY 1
      ORDER BY 2 DESC'
    USING p_start_date, p_end_date, p_region, p_country_code, p_city_code;
  ELSIF has_event_region THEN
    RETURN QUERY EXECUTE
      'SELECT
        COALESCE(el.emotion_bucket, ''unknown'')::TEXT AS mood_bucket,
        COUNT(*)::BIGINT AS total_count
      FROM public.event_logs el
      WHERE el.created_at::DATE >= $1
        AND el.created_at::DATE <= $2
        AND el.emotion_bucket IS NOT NULL
        AND ($3 IS NULL OR el.region = $3)
        AND ($4 IS NULL OR el.city_code = $4)
      GROUP BY 1
      ORDER BY 2 DESC'
    USING p_start_date, p_end_date, p_region, p_city_code;
  ELSIF has_event_country THEN
    RETURN QUERY EXECUTE
      'SELECT
        COALESCE(el.emotion_bucket, ''unknown'')::TEXT AS mood_bucket,
        COUNT(*)::BIGINT AS total_count
      FROM public.event_logs el
      WHERE el.created_at::DATE >= $1
        AND el.created_at::DATE <= $2
        AND el.emotion_bucket IS NOT NULL
        AND ($3 IS NULL OR el.country_code = $3)
        AND ($4 IS NULL OR el.city_code = $4)
      GROUP BY 1
      ORDER BY 2 DESC'
    USING p_start_date, p_end_date, p_country_code, p_city_code;
  ELSE
    RETURN QUERY
    SELECT
      COALESCE(el.emotion_bucket, 'unknown')::TEXT AS mood_bucket,
      COUNT(*)::BIGINT AS total_count
    FROM public.event_logs el
    WHERE el.created_at::DATE >= p_start_date
      AND el.created_at::DATE <= p_end_date
      AND el.emotion_bucket IS NOT NULL
      AND (p_city_code IS NULL OR el.city_code = p_city_code)
    GROUP BY 1
    ORDER BY 2 DESC;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_get_mood_summary(
  DATE,
  DATE,
  TEXT,
  TEXT,
  TEXT
) IS
  'Admin-gated production Insights RPC for read-only mood summary analytics. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.rpc_get_mood_summary(
  DATE,
  DATE,
  TEXT,
  TEXT,
  TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.rpc_get_mood_summary(
  DATE,
  DATE,
  TEXT,
  TEXT,
  TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.rpc_get_mood_summary(
  DATE,
  DATE,
  TEXT,
  TEXT,
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
--      SELECT * FROM public.rpc_get_mood_summary(
--        current_date - 7,
--        current_date,
--        NULL,
--        NULL,
--        NULL
--      );
--
-- 3. Authenticated admin:
--    Insert auth.uid() into public.admin_users using SQL owner/service-role
--    privileges, then call as that authenticated user.
--
--      SELECT * FROM public.rpc_get_mood_summary(
--        current_date - 7,
--        current_date,
--        NULL,
--        NULL,
--        NULL
--      );
--      -- expected: mood bucket aggregate rows when mood data exists.
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
