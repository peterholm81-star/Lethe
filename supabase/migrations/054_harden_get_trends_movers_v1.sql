-- =============================================================================
-- Migration 054: Harden public.get_trends_movers_v1 — both overloads
--
-- Phase: Production Hardening — MEDIUM-risk Trends analytics read RPCs
--
-- Two overloads exist:
--
--   Overload A (4-param): the real logic. Reads from public.confessions,
--   computes emotion-bucket movers by comparing last 7 days vs baseline 28d.
--   Returns TABLE(tag, current_7d, baseline_28d, delta_pct, status) LIMIT 20.
--
--   Overload B (5-param): thin wrapper around Overload A that accepts a
--   p_city parameter (ignored — passed through as a no-op). This is the
--   overload the frontend always calls because scopeToRpc() always emits
--   p_city (scopeUtils.ts line 29-32).
--
-- Both overloads must be hardened:
--   - Overload A: blocks direct anon/non-admin calls to the logic function
--   - Overload B: blocks the frontend path; calls hardened Overload A via
--     SECURITY DEFINER (postgres owner), which re-checks is_insights_admin()
--     against request.jwt.claims — defence-in-depth
--
-- plpgsql shadowing risk in Overload A:
--   Output column "tag" matches the CTE alias "tag". Using `USING (tag)` in
--   the LEFT JOIN could be ambiguous. Internal aliases renamed:
--     emotion_bucket AS tag  → etag
--     count(*) AS c          → cnt
--     count(*)/4.0 AS b      → bline
--   JOIN uses ON base.etag = cur.etag (explicit, unambiguous).
--   All SELECT columns map positionally to RETURNS TABLE.
--
-- Frontend contract preserved (useTrendsMoversV1.ts):
--   - Same name: get_trends_movers_v1 (both overloads)
--   - Frontend calls 5-param overload via scopeToRpc():
--       p_scope     text DEFAULT 'global'
--       p_region    text DEFAULT NULL
--       p_country   text DEFAULT NULL
--       p_city      text DEFAULT NULL   ← always present in frontend calls
--       p_end_date  date DEFAULT CURRENT_DATE
--   - Same return shape (both overloads, multi-row):
--       tag           text
--       current_7d    bigint
--       baseline_28d  numeric
--       delta_pct     numeric   (nullable)
--       status        text      ('rising'|'falling'|'emerging')
--   - Empty result → normalize(data ?? []) → [] — handled gracefully
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Overload A: 4-parameter core logic
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trends_movers_v1(
  p_scope    TEXT DEFAULT 'global',
  p_region   TEXT DEFAULT NULL,
  p_country  TEXT DEFAULT NULL,
  p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  tag          TEXT,
  current_7d   BIGINT,
  baseline_28d NUMERIC,
  delta_pct    NUMERIC,
  status       TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below.
  -- Authenticated non-admins receive zero rows — normalize(data ?? [])
  -- evaluates to [] in the frontend.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Internal aliases etag/cnt/bline replace tag/c/b to avoid plpgsql
  -- output variable shadowing. ON base.etag = cur.etag replaces USING (tag).
  -- All SELECT columns map positionally to the RETURNS TABLE declaration.
  RETURN QUERY
  WITH cur AS (
    SELECT c.emotion_bucket AS etag, count(*) AS cnt
    FROM public.confessions c
    WHERE c.created_at::DATE BETWEEN p_end_date - 6 AND p_end_date
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
    GROUP BY c.emotion_bucket
  ),
  base AS (
    SELECT c.emotion_bucket AS etag, count(*) / 4.0 AS bline
    FROM public.confessions c
    WHERE c.created_at::DATE BETWEEN p_end_date - 34 AND p_end_date - 7
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
    GROUP BY c.emotion_bucket
  )
  SELECT
    cur.etag,                                                        -- → tag
    cur.cnt,                                                         -- → current_7d
    COALESCE(base.bline, 0),                                         -- → baseline_28d
    CASE WHEN COALESCE(base.bline, 0) > 0
         THEN (cur.cnt - base.bline) * 100.0 / base.bline
         ELSE NULL
    END,                                                             -- → delta_pct
    CASE
      WHEN COALESCE(base.bline, 0) < 1 AND cur.cnt >= 5 THEN 'emerging'
      WHEN cur.cnt >= COALESCE(base.bline, 0)            THEN 'rising'
      ELSE 'falling'
    END                                                              -- → status
  FROM cur
  LEFT JOIN base ON base.etag = cur.etag
  ORDER BY abs(COALESCE(
    CASE WHEN COALESCE(base.bline, 0) > 0
         THEN (cur.cnt - base.bline) * 100.0 / base.bline
         ELSE NULL
    END,
    100
  )) DESC
  LIMIT 20;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- Overload B: 5-parameter wrapper (p_city added; ignored — calls Overload A)
-- This is the overload the frontend always invokes via scopeToRpc().
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trends_movers_v1(
  p_scope    TEXT DEFAULT 'global',
  p_region   TEXT DEFAULT NULL,
  p_country  TEXT DEFAULT NULL,
  p_city     TEXT DEFAULT NULL,
  p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  tag          TEXT,
  current_7d   BIGINT,
  baseline_28d NUMERIC,
  delta_pct    NUMERIC,
  status       TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Gate at the wrapper level as well for defence-in-depth — prevents any
  -- future path that might bypass calling the inner function.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- p_city is accepted for frontend compatibility but not forwarded —
  -- the core logic function does not filter by city.
  RETURN QUERY
  SELECT gtm.tag, gtm.current_7d, gtm.baseline_28d, gtm.delta_pct, gtm.status
  FROM public.get_trends_movers_v1(p_scope, p_region, p_country, p_end_date) gtm;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, TEXT, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, TEXT, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, TEXT, DATE) TO authenticated;
