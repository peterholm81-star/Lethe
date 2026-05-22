-- =============================================================================
-- Migration 056: Harden public.get_emotion_fingerprint_v1 — both overloads
--
-- Phase: Production Hardening — FINAL MEDIUM-risk seasonality analytics RPCs
--
-- Two overloads exist (same p_city wrapper pattern as migrations 054 and 055):
--
--   Overload A (5-param): core logic. Reads public.confessions, groups by
--   month × emotion_bucket, returns a monthly emotion-count time series.
--
--   Overload B (6-param): thin wrapper around Overload A. Accepts p_city
--   (ignored) for frontend compatibility. The frontend always calls this
--   overload because scopeToRpc() always emits p_city.
--
-- plpgsql shadowing analysis for Overload A:
--   Output columns: month_start date, emotion text, count bigint.
--   Query body is a single SELECT with no CTEs. All column references are
--   fully qualified with table alias c. (c.created_at, c.emotion_bucket,
--   c.region, c.country_code). GROUP BY 1, 2 and ORDER BY 1, 2 are
--   positional. No unqualified column names that could shadow output vars.
--   The body converts cleanly to plpgsql RETURN QUERY without any alias
--   renaming required.
--
-- Frontend contract preserved (useEmotionFingerprintV1.ts):
--   - Same name: get_emotion_fingerprint_v1 (both overloads)
--   - Frontend calls 6-param overload via scopeToRpc() + p_days + p_end_date
--   - Same return shape (multi-row):
--       month_start  date
--       emotion      text
--       count        bigint
--   - Empty result → normalize(res.data ?? []) → [] — handled gracefully
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Overload A: 5-parameter core logic
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_emotion_fingerprint_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_country  TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 365,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  month_start DATE,
  emotion     TEXT,
  count       BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — normalize(res.data ?? [])
  -- evaluates to [] in the frontend.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- All column references are fully qualified with alias c., so no plpgsql
  -- output-variable shadowing occurs. GROUP BY/ORDER BY are positional.
  RETURN QUERY
  SELECT
    date_trunc('month', c.created_at)::DATE,
    COALESCE(c.emotion_bucket, 'unknown'),
    count(*)::BIGINT
  FROM public.confessions c
  WHERE c.created_at::DATE >= p_end_date - p_days
    AND (p_region  IS NULL OR c.region       = p_region)
    AND (p_country IS NULL OR c.country_code = p_country)
  GROUP BY 1, 2
  ORDER BY 1, 2;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- Overload B: 6-parameter wrapper (p_city accepted but ignored — calls Overload A)
-- This is the overload the frontend always invokes via scopeToRpc().
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_emotion_fingerprint_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_country  TEXT    DEFAULT NULL,
  p_city     TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 365,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  month_start DATE,
  emotion     TEXT,
  count       BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Defence-in-depth gate at the wrapper level.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- p_city accepted for frontend compatibility, not forwarded to core logic.
  RETURN QUERY
  SELECT gef.month_start, gef.emotion, gef.count
  FROM public.get_emotion_fingerprint_v1(p_scope, p_region, p_country, p_days, p_end_date) gef;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;
