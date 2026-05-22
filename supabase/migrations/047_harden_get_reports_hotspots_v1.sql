-- =============================================================================
-- Migration 047: Harden public.get_reports_hotspots_v1
--
-- Phase: Production Hardening — HIGH-risk moderation aggregate read RPCs
--
-- Purpose:
--   Replace the open (anon-accessible) version of get_reports_hotspots_v1
--   with a production-safe, admin-gated read RPC.
--
--   This RPC returns the top 20 cities by report density, including per-city
--   moderation counts, reads/report ratios, the top report reason per city, and
--   global coverage quality metrics (unknown geo percentages). It is the
--   densest operational moderation intelligence in the codebase after the
--   raw moderation inbox. Admin-only.
--
-- Security changes applied:
--   - SECURITY DEFINER with explicit SET search_path = public, pg_temp
--   - Authenticated non-admins receive zero rows (RETURN); frontend sets
--     hotspots to [] and coverage to null gracefully (useReportsHotspots.ts
--     lines 122-138)
--   - REVOKE EXECUTE FROM PUBLIC and FROM anon
--   - GRANT EXECUTE TO authenticated only
--   - Language changed from sql to plpgsql to support the admin gate;
--     all CTEs, query logic, return columns, order, LIMIT, and types are
--     preserved exactly
--
-- Frontend contract preserved (useReportsHotspots.ts):
--   - Same name: get_reports_hotspots_v1
--   - Same parameters with same defaults:
--       p_days    integer DEFAULT 7
--       p_region  text    DEFAULT NULL
--       p_country text    DEFAULT NULL
--   - Same return columns (up to 20 rows, one per city):
--       city_code            text
--       city_label           text
--       region               text
--       country              text
--       reports_count        bigint
--       reads_count          bigint
--       reports_per_1k       numeric  (nullable — null when reads = 0)
--       top_reason           text
--       top_reason_count     bigint
--       total_reports_count  bigint
--       unknown_reports_count bigint
--       unknown_reports_pct  numeric
--       total_reads_count    bigint
--       unknown_reads_count  bigint
--       unknown_reads_pct    numeric
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_reports_hotspots_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL
)
RETURNS TABLE(
  city_code             TEXT,
  city_label            TEXT,
  region                TEXT,
  country               TEXT,
  reports_count         BIGINT,
  reads_count           BIGINT,
  reports_per_1k        NUMERIC,
  top_reason            TEXT,
  top_reason_count      BIGINT,
  total_reports_count   BIGINT,
  unknown_reports_count BIGINT,
  unknown_reports_pct   NUMERIC,
  total_reads_count     BIGINT,
  unknown_reads_count   BIGINT,
  unknown_reads_pct     NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Anon callers are blocked by the REVOKE grant below before reaching here.
  -- Authenticated non-admins receive zero rows — per-city moderation density
  -- and operational intelligence must not be visible outside the admin boundary.
  -- The frontend handles an empty result by setting hotspots to [] and
  -- coverage to null.
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- plpgsql RETURNS TABLE columns are in scope as variables, which makes
  -- bare column names like 'city_code' and 'region' ambiguous inside the
  -- RETURN QUERY body. All CTE and table references are fully qualified
  -- with aliases to avoid the ambiguity error.
  RETURN QUERY
  WITH reps AS (
    -- Renamed from 'r' to 'reps'; all references use 'rep.' / 'c.' aliases
    SELECT rep.reason, c.city_code AS rep_city, c.region AS rep_region, c.country_code AS rep_country
    FROM public.reports rep
    LEFT JOIN public.confessions c ON c.id = rep.confession_id
    WHERE rep.created_at >= now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
  ),
  city_reps AS (
    SELECT reps.rep_city, reps.rep_region, reps.rep_country, count(*) AS reps_count
    FROM reps
    WHERE reps.rep_city IS NOT NULL
    GROUP BY reps.rep_city, reps.rep_region, reps.rep_country
  ),
  city_reads AS (
    SELECT el.city_code AS read_city, count(*) AS reads_cnt
    FROM public.event_logs el
    WHERE el.created_at >= now() - make_interval(days => p_days)
      AND el.event_name IN ('feed_view', 'page_fetch')
    GROUP BY el.city_code
  ),
  top_rsn AS (
    SELECT DISTINCT ON (reps.rep_city) reps.rep_city, reps.reason, count(*) AS rsn_count
    FROM reps
    WHERE reps.rep_city IS NOT NULL
    GROUP BY reps.rep_city, reps.reason
    ORDER BY reps.rep_city, count(*) DESC
  ),
  totals AS (
    SELECT
      (SELECT count(*) FROM reps)                                                          AS tot_reports,
      (SELECT count(*) FROM reps WHERE reps.rep_city IS NULL)                             AS unk_reports,
      (SELECT count(*) FROM public.event_logs el2
       WHERE el2.created_at >= now() - make_interval(days => p_days)
         AND el2.event_name IN ('feed_view', 'page_fetch'))                               AS tot_reads,
      (SELECT count(*) FROM public.event_logs el3
       WHERE el3.created_at >= now() - make_interval(days => p_days)
         AND el3.event_name IN ('feed_view', 'page_fetch')
         AND el3.city_code IS NULL)                                                       AS unk_reads
  )
  SELECT
    cr.rep_city,
    cr.rep_city,           -- city_label: same as city_code (no separate label table)
    cr.rep_region,
    cr.rep_country,
    cr.reps_count,
    COALESCE(rd.reads_cnt, 0),
    CASE WHEN COALESCE(rd.reads_cnt, 0) > 0
         THEN cr.reps_count * 1000.0 / rd.reads_cnt
         ELSE NULL
    END,
    tr.reason,
    tr.rsn_count,
    t.tot_reports,
    t.unk_reports,
    CASE WHEN t.tot_reports > 0 THEN t.unk_reports * 100.0 / t.tot_reports ELSE 0 END,
    t.tot_reads,
    t.unk_reads,
    CASE WHEN t.tot_reads > 0 THEN t.unk_reads * 100.0 / t.tot_reads ELSE 0 END
  FROM city_reps cr
  LEFT JOIN city_reads rd ON rd.read_city = cr.rep_city
  LEFT JOIN top_rsn    tr ON tr.rep_city  = cr.rep_city
  CROSS JOIN totals t
  ORDER BY cr.reps_count DESC
  LIMIT 20;
END;
$$;

-- ---------------------------------------------------------------------------
-- Least-privilege grants
-- The browser client must never receive service_role.
-- Anon users must not be able to read per-city moderation hotspot data.
-- ---------------------------------------------------------------------------
REVOKE ALL     ON FUNCTION public.get_reports_hotspots_v1(INTEGER, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_hotspots_v1(INTEGER, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_hotspots_v1(INTEGER, TEXT, TEXT) TO authenticated;
