-- ============================================================================
-- Migration: Harden rpc_get_mood_pulse_by_region
-- ============================================================================
-- Purpose:
--   Convert the read-only regional mood Insights aggregate RPC to the
--   production-safe admin model. Preserves the existing frontend RPC name,
--   parameters, and return columns exactly.
--
-- Notes:
--   The local/demo version joins confessions.region (dev-enriched) via a
--   CROSS JOIN LATERAL. The production-safe version computes directly from
--   event_logs.emotion_bucket grouped by event_logs.region, which is present
--   in the local DB and will exist once geo-enrichment lands in production.
--   Until then (event_logs.region absent) the function returns an empty set.
--
--   No raw confession text, no raw coordinates, no session-level data exposed.
--
-- Scope:
--   - aggregate analytics only
--   - no public app/feed RPCs
--   - no moderation writes
--   - no monetization writes
--   - no frontend contract changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_mood_pulse_by_region(
  p_start_date DATE,
  p_end_date DATE
)
RETURNS TABLE (
  region              TEXT,
  balance_score       NUMERIC,
  prev_balance_score  NUMERIC,
  delta_balance_score NUMERIC,
  positive_share      NUMERIC,
  negative_share      NUMERIC,
  total_confessions   BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  has_region  BOOLEAN;
  span_days   INTEGER;
BEGIN
  -- Read-only Insights RPCs return an empty set for authenticated non-admins.
  -- Anon callers are denied by grants below before function execution.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN;
  END IF;

  -- Check whether the geo-enrichment column exists in event_logs.
  -- Production without geo enrichment returns an empty set rather than failing.
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'event_logs'
      AND column_name  = 'region'
  ) INTO has_region;

  IF NOT has_region THEN
    RETURN;
  END IF;

  span_days := p_end_date - p_start_date + 1;

  RETURN QUERY
  WITH cur AS (
    SELECT
      el.region,
      COUNT(*) FILTER (WHERE el.emotion_bucket IN ('hopeful','calm','grateful'))    AS positive,
      COUNT(*) FILTER (WHERE el.emotion_bucket IN ('lonely','anxious','sad','tired','restless')) AS negative,
      COUNT(*) AS total
    FROM public.event_logs el
    WHERE el.created_at::DATE >= p_start_date
      AND el.created_at::DATE <= p_end_date
      AND el.emotion_bucket IS NOT NULL
      AND el.region IS NOT NULL
    GROUP BY el.region
  ), prev AS (
    SELECT
      el.region,
      COUNT(*) FILTER (WHERE el.emotion_bucket IN ('hopeful','calm','grateful'))    AS positive,
      COUNT(*) FILTER (WHERE el.emotion_bucket IN ('lonely','anxious','sad','tired','restless')) AS negative,
      COUNT(*) AS total
    FROM public.event_logs el
    WHERE el.created_at::DATE >= (p_start_date - span_days)
      AND el.created_at::DATE <= (p_start_date - 1)
      AND el.emotion_bucket IS NOT NULL
      AND el.region IS NOT NULL
    GROUP BY el.region
  )
  SELECT
    cur.region,
    CASE WHEN cur.total  > 0 THEN (cur.positive  - cur.negative )::NUMERIC / cur.total  ELSE 0 END AS balance_score,
    CASE WHEN prev.total > 0 THEN (prev.positive - prev.negative)::NUMERIC / prev.total ELSE 0 END AS prev_balance_score,
    CASE WHEN cur.total  > 0 THEN (cur.positive  - cur.negative )::NUMERIC / cur.total  ELSE 0 END
      - CASE WHEN prev.total > 0 THEN (prev.positive - prev.negative)::NUMERIC / prev.total ELSE 0 END AS delta_balance_score,
    CASE WHEN cur.total  > 0 THEN cur.positive ::NUMERIC / cur.total  ELSE 0 END AS positive_share,
    CASE WHEN cur.total  > 0 THEN cur.negative ::NUMERIC / cur.total  ELSE 0 END AS negative_share,
    cur.total::BIGINT AS total_confessions
  FROM cur
  LEFT JOIN prev ON prev.region = cur.region
  ORDER BY cur.total DESC;
END;
$$;

COMMENT ON FUNCTION public.rpc_get_mood_pulse_by_region(DATE, DATE) IS
  'Admin-gated production Insights RPC for read-only per-region mood pulse analytics. Browser clients must never receive service_role.';

-- Revoke broad PUBLIC execute then grant only the role that can carry a user identity.
REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse_by_region(DATE, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_mood_pulse_by_region(DATE, DATE) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_mood_pulse_by_region(DATE, DATE) TO authenticated;

-- ============================================================================
-- Verification notes (run manually in local/staging)
-- ============================================================================
--
-- 1. Anon REST caller:
--    Expected: permission denied — anon has no EXECUTE grant.
--
-- 2. Authenticated non-admin:
--    Expected: empty result set.
--
--      SELECT * FROM public.rpc_get_mood_pulse_by_region(
--        current_date - 6, current_date
--      );
--
-- 3. Authenticated admin:
--    Insert auth.uid() into public.admin_users with service-role, then call
--    as that authenticated user.
--
--      SELECT * FROM public.rpc_get_mood_pulse_by_region(
--        current_date - 6, current_date
--      );
--      -- expected: one aggregate row per region containing mood scores.
--      -- empty set if event_logs.region column does not yet exist.
--
-- 4. Public app behavior:
--    get_confess_feed, insert_confession, report_confession unchanged.
-- ============================================================================
