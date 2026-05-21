-- ============================================================================
-- Migration: Harden rpc_get_mood_pulse
-- ============================================================================
-- Purpose:
--   Convert one real, read-only Mood Insights aggregate RPC to the
--   production-safe admin model. This preserves the existing frontend RPC name,
--   parameters, and return columns while preventing anon access in production.
--
-- Notes:
--   This RPC returns aggregate mood scores only. It does not expose raw
--   confession text, raw event rows, or raw coordinates. The current production
--   schema has event_logs.emotion_bucket, so this function computes from
--   aggregate event-log mood buckets until production confession mood enrichment
--   is formalized.
--
-- Scope:
--   - aggregate analytics only
--   - no public app/feed RPCs
--   - no moderation writes
--   - no monetization writes
--   - no frontend contract changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_mood_pulse(
  p_start_date DATE,
  p_end_date DATE,
  p_region TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code TEXT DEFAULT NULL
)
RETURNS TABLE (
  balance_score NUMERIC,
  prev_balance_score NUMERIC,
  delta_balance_score NUMERIC,
  positive_share NUMERIC,
  negative_share NUMERIC,
  total_confessions BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  has_event_region BOOLEAN;
  has_event_country BOOLEAN;
  span_days INTEGER;
BEGIN
  -- Read-only Insights RPCs return an empty set for authenticated non-admins.
  -- Anon callers are denied by grants below before function execution.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN;
  END IF;

  span_days := p_end_date - p_start_date + 1;

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
      'WITH current_rows AS (
        SELECT el.emotion_bucket
        FROM public.event_logs el
        WHERE el.created_at::DATE >= $1
          AND el.created_at::DATE <= $2
          AND el.emotion_bucket IS NOT NULL
          AND ($4 IS NULL OR el.region = $4)
          AND ($5 IS NULL OR el.country_code = $5)
          AND ($6 IS NULL OR el.city_code = $6)
      ), previous_rows AS (
        SELECT el.emotion_bucket
        FROM public.event_logs el
        WHERE el.created_at::DATE >= ($1 - $3)
          AND el.created_at::DATE <= ($1 - 1)
          AND el.emotion_bucket IS NOT NULL
          AND ($4 IS NULL OR el.region = $4)
          AND ($5 IS NULL OR el.country_code = $5)
          AND ($6 IS NULL OR el.city_code = $6)
      ), cur AS (
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''hopeful'', ''calm'', ''grateful'')) AS positive,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''lonely'', ''anxious'', ''sad'', ''tired'', ''restless'')) AS negative
        FROM current_rows
      ), prev AS (
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''hopeful'', ''calm'', ''grateful'')) AS positive,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''lonely'', ''anxious'', ''sad'', ''tired'', ''restless'')) AS negative
        FROM previous_rows
      )
      SELECT
        CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END AS balance_score,
        CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS prev_balance_score,
        CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END
          - CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS delta_balance_score,
        CASE WHEN cur.total > 0 THEN cur.positive::NUMERIC / cur.total ELSE 0 END AS positive_share,
        CASE WHEN cur.total > 0 THEN cur.negative::NUMERIC / cur.total ELSE 0 END AS negative_share,
        cur.total::BIGINT AS total_confessions
      FROM cur, prev'
    USING p_start_date, p_end_date, span_days, p_region, p_country_code, p_city_code;
  ELSIF has_event_region THEN
    RETURN QUERY EXECUTE
      'WITH current_rows AS (
        SELECT el.emotion_bucket
        FROM public.event_logs el
        WHERE el.created_at::DATE >= $1
          AND el.created_at::DATE <= $2
          AND el.emotion_bucket IS NOT NULL
          AND ($4 IS NULL OR el.region = $4)
          AND ($5 IS NULL OR el.city_code = $5)
      ), previous_rows AS (
        SELECT el.emotion_bucket
        FROM public.event_logs el
        WHERE el.created_at::DATE >= ($1 - $3)
          AND el.created_at::DATE <= ($1 - 1)
          AND el.emotion_bucket IS NOT NULL
          AND ($4 IS NULL OR el.region = $4)
          AND ($5 IS NULL OR el.city_code = $5)
      ), cur AS (
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''hopeful'', ''calm'', ''grateful'')) AS positive,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''lonely'', ''anxious'', ''sad'', ''tired'', ''restless'')) AS negative
        FROM current_rows
      ), prev AS (
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''hopeful'', ''calm'', ''grateful'')) AS positive,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''lonely'', ''anxious'', ''sad'', ''tired'', ''restless'')) AS negative
        FROM previous_rows
      )
      SELECT
        CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END AS balance_score,
        CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS prev_balance_score,
        CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END
          - CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS delta_balance_score,
        CASE WHEN cur.total > 0 THEN cur.positive::NUMERIC / cur.total ELSE 0 END AS positive_share,
        CASE WHEN cur.total > 0 THEN cur.negative::NUMERIC / cur.total ELSE 0 END AS negative_share,
        cur.total::BIGINT AS total_confessions
      FROM cur, prev'
    USING p_start_date, p_end_date, span_days, p_region, p_city_code;
  ELSIF has_event_country THEN
    RETURN QUERY EXECUTE
      'WITH current_rows AS (
        SELECT el.emotion_bucket
        FROM public.event_logs el
        WHERE el.created_at::DATE >= $1
          AND el.created_at::DATE <= $2
          AND el.emotion_bucket IS NOT NULL
          AND ($4 IS NULL OR el.country_code = $4)
          AND ($5 IS NULL OR el.city_code = $5)
      ), previous_rows AS (
        SELECT el.emotion_bucket
        FROM public.event_logs el
        WHERE el.created_at::DATE >= ($1 - $3)
          AND el.created_at::DATE <= ($1 - 1)
          AND el.emotion_bucket IS NOT NULL
          AND ($4 IS NULL OR el.country_code = $4)
          AND ($5 IS NULL OR el.city_code = $5)
      ), cur AS (
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''hopeful'', ''calm'', ''grateful'')) AS positive,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''lonely'', ''anxious'', ''sad'', ''tired'', ''restless'')) AS negative
        FROM current_rows
      ), prev AS (
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''hopeful'', ''calm'', ''grateful'')) AS positive,
          COUNT(*) FILTER (WHERE emotion_bucket IN (''lonely'', ''anxious'', ''sad'', ''tired'', ''restless'')) AS negative
        FROM previous_rows
      )
      SELECT
        CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END AS balance_score,
        CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS prev_balance_score,
        CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END
          - CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS delta_balance_score,
        CASE WHEN cur.total > 0 THEN cur.positive::NUMERIC / cur.total ELSE 0 END AS positive_share,
        CASE WHEN cur.total > 0 THEN cur.negative::NUMERIC / cur.total ELSE 0 END AS negative_share,
        cur.total::BIGINT AS total_confessions
      FROM cur, prev'
    USING p_start_date, p_end_date, span_days, p_country_code, p_city_code;
  ELSE
    RETURN QUERY
    WITH current_rows AS (
      SELECT el.emotion_bucket
      FROM public.event_logs el
      WHERE el.created_at::DATE >= p_start_date
        AND el.created_at::DATE <= p_end_date
        AND el.emotion_bucket IS NOT NULL
        AND (p_city_code IS NULL OR el.city_code = p_city_code)
    ), previous_rows AS (
      SELECT el.emotion_bucket
      FROM public.event_logs el
      WHERE el.created_at::DATE >= (p_start_date - span_days)
        AND el.created_at::DATE <= (p_start_date - 1)
        AND el.emotion_bucket IS NOT NULL
        AND (p_city_code IS NULL OR el.city_code = p_city_code)
    ), cur AS (
      SELECT
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE emotion_bucket IN ('hopeful', 'calm', 'grateful')) AS positive,
        COUNT(*) FILTER (WHERE emotion_bucket IN ('lonely', 'anxious', 'sad', 'tired', 'restless')) AS negative
      FROM current_rows
    ), prev AS (
      SELECT
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE emotion_bucket IN ('hopeful', 'calm', 'grateful')) AS positive,
        COUNT(*) FILTER (WHERE emotion_bucket IN ('lonely', 'anxious', 'sad', 'tired', 'restless')) AS negative
      FROM previous_rows
    )
    SELECT
      CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END AS balance_score,
      CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS prev_balance_score,
      CASE WHEN cur.total > 0 THEN ((cur.positive - cur.negative)::NUMERIC / cur.total) ELSE 0 END
        - CASE WHEN prev.total > 0 THEN ((prev.positive - prev.negative)::NUMERIC / prev.total) ELSE 0 END AS delta_balance_score,
      CASE WHEN cur.total > 0 THEN cur.positive::NUMERIC / cur.total ELSE 0 END AS positive_share,
      CASE WHEN cur.total > 0 THEN cur.negative::NUMERIC / cur.total ELSE 0 END AS negative_share,
      cur.total::BIGINT AS total_confessions
    FROM cur, prev;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_get_mood_pulse(
  DATE,
  DATE,
  TEXT,
  TEXT,
  TEXT
) IS
  'Admin-gated production Insights RPC for read-only mood pulse analytics. Browser clients must never receive service_role.';

-- Functions are executable by PUBLIC by default in Postgres. Revoke broad
-- execution and allow only authenticated users to call the admin-gated RPC.
REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse(
  DATE,
  DATE,
  TEXT,
  TEXT,
  TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse(
  DATE,
  DATE,
  TEXT,
  TEXT,
  TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.rpc_get_mood_pulse(
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
--      SELECT * FROM public.rpc_get_mood_pulse(
--        current_date - 6,
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
--      SELECT * FROM public.rpc_get_mood_pulse(
--        current_date - 6,
--        current_date,
--        NULL,
--        NULL,
--        NULL
--      );
--      -- expected: one aggregate mood pulse row when mood data exists.
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession, and other public
--    app RPCs are intentionally unchanged by this migration.
-- ============================================================================
