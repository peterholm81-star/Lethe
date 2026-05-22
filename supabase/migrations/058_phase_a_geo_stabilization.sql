-- =============================================================================
-- Migration 058: Phase A — Production Geo Stabilization
--
-- Goal: Prevent ALL production runtime crashes caused by missing geo columns.
--
-- Columns absent from production schema (added only by dev seed):
--   confessions : region, country_code, city_code, emotion_bucket
--   event_logs  : region, country_code
--
-- Three-tier strategy:
--
--   [A] OPERATIONAL REPORTS (034–038) — exception handler + NULL fallback
--       Admins can still view reports/moderation actions without geo data.
--       Geo output columns return NULL; geo WHERE filters are silently skipped.
--
--   [B] AGGREGATE REPORTS (040–050) — exception handler + empty RETURN
--       Analytics/aggregate widgets return "no data" gracefully.
--
--   [C] ANALYTICS / TRENDS (051–056) — exception handler + empty RETURN
--       Trend/chart widgets return "no data" gracefully.
--
--   [D] FILTER OPTIONS (057) — information_schema guard + exception fallback
--       Region/country dropdowns return empty (correct: no such column = no
--       options).  City-code dropdown falls back to unfiltered list (city_code
--       column DOES exist in production; only the region/country filter clauses
--       are missing).
--
-- All function signatures and return types are preserved exactly.
-- All admin gates (is_insights_admin) are preserved exactly.
-- GRANT/REVOKE re-issued for safety in case dev-seed shims had overwritten them.
-- =============================================================================


-- =============================================================================
-- [A] OPERATIONAL REPORTS — NULL-substitution fallback
-- =============================================================================

-- ---------------------------------------------------------------------------
-- A1: get_reports_inbox
-- Reports moderation inbox. Returns raw confession text to admins only.
-- Fallback: city_code = NULL, region = NULL — reports still visible.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_inbox(
  p_limit          INTEGER DEFAULT 50,
  p_only_unhandled BOOLEAN DEFAULT true
)
RETURNS TABLE(
  report_id            UUID,
  report_created_at    TIMESTAMPTZ,
  reason               TEXT,
  details              TEXT,
  report_city_code     TEXT,
  confession_id        UUID,
  confession_region    TEXT,
  confession_text      TEXT,
  confession_is_hidden BOOLEAN,
  handled              BOOLEAN,
  handled_at           TIMESTAMPTZ,
  handled_by           TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    -- Primary path: full query with confession geo columns
    RETURN QUERY
    SELECT
      r.id,
      r.created_at,
      r.reason,
      r.details,
      c.city_code,
      c.id,
      c.region,
      c.text,
      COALESCE(c.is_hidden, false),
      COALESCE(r.handled, r.status <> 'open'),
      r.handled_at,
      r.handled_by
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE (NOT p_only_unhandled OR r.status = 'open')
    ORDER BY r.created_at DESC
    LIMIT p_limit;
  EXCEPTION WHEN undefined_column THEN
    -- Geo columns (and/or r.handled/handled_at/handled_by) absent in production
    -- schema — return reports with NULL for all missing fields.
    -- r.status is always present; handled is derived from it.
    RETURN QUERY
    SELECT
      r.id,
      r.created_at,
      r.reason,
      r.details,
      NULL::TEXT,                               -- report_city_code (c.city_code missing)
      c.id,
      NULL::TEXT,                               -- confession_region (c.region missing)
      c.text,
      COALESCE(c.is_hidden, false),
      r.status <> 'open',                       -- handled derived from status
      NULL::TIMESTAMPTZ,                        -- handled_at (not in production schema)
      NULL::TEXT                                -- handled_by (not in production schema)
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE (NOT p_only_unhandled OR r.status = 'open')
    ORDER BY r.created_at DESC
    LIMIT p_limit;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_inbox(INTEGER, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_inbox(INTEGER, BOOLEAN) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_inbox(INTEGER, BOOLEAN) TO authenticated;


-- ---------------------------------------------------------------------------
-- A2: get_reports_groups
-- Groups reports by confession with aggregation. Returns confession text.
-- Fallback: region = NULL, city_code_sample = NULL — groups still visible.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_groups(
  p_limit          INTEGER DEFAULT 50,
  p_only_unhandled BOOLEAN DEFAULT true,
  p_reason         TEXT    DEFAULT NULL,
  p_visibility     TEXT    DEFAULT NULL,
  p_sort           TEXT    DEFAULT 'last_reported_desc'
)
RETURNS TABLE(
  confession_id           UUID,
  confession_text         TEXT,
  confession_region       TEXT,
  confession_is_hidden    BOOLEAN,
  total_reports           BIGINT,
  unhandled_reports       BIGINT,
  handled_all             BOOLEAN,
  first_reported_at       TIMESTAMPTZ,
  last_reported_at        TIMESTAMPTZ,
  reason_breakdown_json   JSONB,
  report_city_code_sample TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    -- Primary path: full query with confession geo columns
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
  EXCEPTION WHEN undefined_column THEN
    -- Geo columns absent — return groups with NULL region/city_code
    RETURN QUERY
    WITH r AS (
      SELECT r.*, c.text, NULL::TEXT AS region, c.is_hidden, NULL::TEXT AS city_code
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
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_groups(INTEGER, BOOLEAN, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_groups(INTEGER, BOOLEAN, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_groups(INTEGER, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- A3: get_reports_pending_v1
-- Open moderation queue with geo context.
-- Fallback: region/country_code/city_code = NULL, geo WHERE skipped.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_pending_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL,
  p_limit   INTEGER DEFAULT 25,
  p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE(
  report_id     UUID,
  confession_id UUID,
  reason        TEXT,
  created_at    TIMESTAMPTZ,
  region        TEXT,
  country_code  TEXT,
  city_code     TEXT,
  hours_open    NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    SELECT
      r.id,
      r.confession_id,
      r.reason,
      r.created_at,
      c.region,
      c.country_code,
      c.city_code,
      EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    WHERE r.status = 'open'
      AND r.created_at >= now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
    ORDER BY r.created_at DESC
    LIMIT p_limit OFFSET p_offset;
  EXCEPTION WHEN undefined_column THEN
    -- Geo columns absent — return pending reports without geo context
    RETURN QUERY
    SELECT
      r.id,
      r.confession_id,
      r.reason,
      r.created_at,
      NULL::TEXT,   -- region
      NULL::TEXT,   -- country_code
      NULL::TEXT,   -- city_code
      EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600
    FROM public.reports r
    WHERE r.status = 'open'
      AND r.created_at >= now() - make_interval(days => p_days)
    ORDER BY r.created_at DESC
    LIMIT p_limit OFFSET p_offset;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_pending_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_pending_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_pending_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;


-- ---------------------------------------------------------------------------
-- A4: get_reports_escalated_v1
-- Escalated moderation queue. Fallback: geo columns = NULL, filters skipped.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_escalated_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL,
  p_limit   INTEGER DEFAULT 20,
  p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE(
  report_id        UUID,
  confession_id    UUID,
  reason           TEXT,
  region           TEXT,
  country_code     TEXT,
  city_code        TEXT,
  created_at       TIMESTAMPTZ,
  hours_open       NUMERIC,
  latest_action    TEXT,
  latest_action_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    SELECT
      r.id,
      r.confession_id,
      r.reason,
      c.region,
      c.country_code,
      c.city_code,
      r.created_at,
      EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600,
      COALESCE(a.action_type, 'ESCALATE'),
      COALESCE(a.created_at, r.created_at)
    FROM public.reports r
    LEFT JOIN public.confessions c ON c.id = r.confession_id
    LEFT JOIN LATERAL (
      SELECT ma.action_type, ma.created_at
      FROM public.moderation_actions ma
      WHERE ma.report_id = r.id
      ORDER BY ma.created_at DESC
      LIMIT 1
    ) a ON true
    WHERE (
        (r.status = 'open' AND r.created_at < now() - INTERVAL '12 hours')
        OR COALESCE(a.action_type, '') = 'ESCALATE'
      )
      AND r.created_at >= now() - make_interval(days => p_days)
      AND (p_region  IS NULL OR c.region       = p_region)
      AND (p_country IS NULL OR c.country_code = p_country)
      AND (p_city    IS NULL OR c.city_code    = p_city)
    ORDER BY r.created_at DESC
    LIMIT p_limit OFFSET p_offset;
  EXCEPTION WHEN undefined_column OR undefined_table THEN
    -- Geo columns absent (confessions) OR moderation_actions table absent.
    -- Return empty set — cannot determine escalated state without moderation history.
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_escalated_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_escalated_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_escalated_v1(INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;


-- ---------------------------------------------------------------------------
-- A5: get_moderation_actions_v1
-- Moderation audit log. Fallback: city_code/region/country_code = NULL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_moderation_actions_v1(
  p_days        INTEGER DEFAULT 7,
  p_region      TEXT    DEFAULT NULL,
  p_country     TEXT    DEFAULT NULL,
  p_city        TEXT    DEFAULT NULL,
  p_action_type TEXT    DEFAULT NULL,
  p_limit       INTEGER DEFAULT 25,
  p_offset      INTEGER DEFAULT 0
)
RETURNS TABLE(
  id            UUID,
  created_at    TIMESTAMPTZ,
  action_type   TEXT,
  confession_id UUID,
  report_id     UUID,
  reason        TEXT,
  city_code     TEXT,
  region        TEXT,
  country_code  TEXT,
  source        TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    SELECT
      a.id,
      a.created_at,
      a.action_type,
      a.confession_id,
      a.report_id,
      a.reason,
      c.city_code,
      c.region,
      c.country_code,
      COALESCE(a.context->>'source', 'dev_seed')
    FROM public.moderation_actions a
    LEFT JOIN public.confessions c ON c.id = a.confession_id
    WHERE a.created_at >= now() - make_interval(days => p_days)
      AND (p_region      IS NULL OR c.region       = p_region)
      AND (p_country     IS NULL OR c.country_code = p_country)
      AND (p_city        IS NULL OR c.city_code    = p_city)
      AND (p_action_type IS NULL OR a.action_type  = p_action_type)
    ORDER BY a.created_at DESC
    LIMIT p_limit OFFSET p_offset;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    -- moderation_actions table absent, geo columns missing, OR helper function absent.
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_moderation_actions_v1(INTEGER, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_moderation_actions_v1(INTEGER, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_moderation_actions_v1(INTEGER, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO authenticated;


-- =============================================================================
-- [B] AGGREGATE REPORTS — exception handler + empty RETURN
-- =============================================================================

-- ---------------------------------------------------------------------------
-- B1: get_reports_overview_v2
-- References c.region/country_code/city_code (confessions) AND
-- e.region/country_code (event_logs) — both absent in production.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_overview_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  reports_total        BIGINT,
  reports_per_1k_reads NUMERIC,
  hidden_total         BIGINT,
  severity_score       NUMERIC,
  spike_detected       BOOLEAN,
  actions_total        BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH params AS (
      SELECT public._lethe_reports_range_days(p_range) AS days
    ),
    reports_filtered AS (
      SELECT r.*, c.region, c.country_code, c.city_code, c.is_hidden
      FROM public.reports r
      LEFT JOIN public.confessions c ON c.id = r.confession_id
      CROSS JOIN params p
      WHERE r.created_at >= now() - make_interval(days => p.days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    ),
    reads AS (
      SELECT count(*) AS reads_count
      FROM public.event_logs e
      CROSS JOIN params p
      WHERE e.created_at >= now() - make_interval(days => p.days)
        AND e.event_name IN ('feed_view', 'page_fetch')
        AND (p_region  IS NULL OR e.region       = p_region)
        AND (p_country IS NULL OR e.country_code = p_country)
        AND (p_city    IS NULL OR e.city_code    = p_city)
    ),
    actions AS (
      SELECT count(*) AS actions_count
      FROM public.moderation_actions a
      LEFT JOIN public.confessions c ON c.id = a.confession_id
      CROSS JOIN params p
      WHERE a.created_at >= now() - make_interval(days => p.days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    ),
    totals AS (
      SELECT
        count(*)                                                              AS reports_count,
        count(*) FILTER (WHERE COALESCE(is_hidden, false))                   AS hidden_count,
        count(*) FILTER (WHERE reason IN ('threats', 'identifying', 'contact')) AS severe_count
      FROM reports_filtered
    )
    SELECT
      totals.reports_count,
      CASE WHEN reads.reads_count > 0
           THEN totals.reports_count * 1000.0 / reads.reads_count
           ELSE NULL
      END,
      totals.hidden_count,
      CASE WHEN totals.reports_count > 0
           THEN ROUND(totals.severe_count * 100.0 / totals.reports_count, 2)
           ELSE 0
      END,
      totals.reports_count > 50,
      actions.actions_count
    FROM totals, reads, actions;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    -- Geo columns absent, moderation_actions table absent, OR helper function absent.
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_overview_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_overview_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_overview_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B2: get_reports_outcomes_v1
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_outcomes_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  actioned_reports   BIGINT,
  handled_reports    BIGINT,
  hidden_reports     BIGINT,
  dismissed_reports  BIGINT,
  escalated_reports  BIGINT,
  handled_rate_pct   NUMERIC,
  hidden_rate_pct    NUMERIC,
  dismissed_rate_pct NUMERIC,
  escalated_rate_pct NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH r AS (
      SELECT r.*, c.region, c.country_code, c.city_code, c.is_hidden
      FROM public.reports r
      LEFT JOIN public.confessions c ON c.id = r.confession_id
      WHERE r.created_at >= now() - make_interval(days => p_days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    ),
    a AS (
      SELECT
        count(*)                                                                          AS total,
        count(*) FILTER (WHERE status = 'actioned')                                      AS actioned,
        count(*) FILTER (WHERE handled OR status <> 'open')                              AS handled_count,
        count(*) FILTER (WHERE COALESCE(is_hidden, false))                               AS hidden,
        count(*) FILTER (WHERE status = 'dismissed')                                     AS dismissed,
        count(*) FILTER (WHERE status = 'open' AND created_at < now() - INTERVAL '12 hours') AS escalated
      FROM r
    )
    SELECT
      actioned,
      handled_count,
      hidden,
      dismissed,
      escalated,
      CASE WHEN total > 0 THEN handled_count * 100.0 / total ELSE 0 END,
      CASE WHEN total > 0 THEN hidden       * 100.0 / total ELSE 0 END,
      CASE WHEN total > 0 THEN dismissed    * 100.0 / total ELSE 0 END,
      CASE WHEN total > 0 THEN escalated    * 100.0 / total ELSE 0 END
    FROM a;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_outcomes_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_outcomes_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_outcomes_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B3: get_reports_sla_v1
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.get_reports_sla_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  median_minutes         NUMERIC,
  p90_minutes            NUMERIC,
  oldest_pending_minutes NUMERIC,
  actioned_reports       BIGINT,
  pending_reports        BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH r AS (
      SELECT r.*, c.region, c.country_code, c.city_code
      FROM public.reports r
      LEFT JOIN public.confessions c ON c.id = r.confession_id
      WHERE r.created_at >= now() - make_interval(days => p_days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    )
    SELECT
      (percentile_cont(0.50) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (handled_at - created_at)) / 60
      ) FILTER (WHERE handled_at IS NOT NULL))::NUMERIC,
      (percentile_cont(0.90) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (handled_at - created_at)) / 60
      ) FILTER (WHERE handled_at IS NOT NULL))::NUMERIC,
      (EXTRACT(EPOCH FROM (now() - min(created_at) FILTER (WHERE status = 'open'))) / 60)::NUMERIC,
      count(*) FILTER (WHERE handled OR status <> 'open'),
      count(*) FILTER (WHERE status = 'open')
    FROM r;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_sla_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B4: get_reports_geo_coverage_v1
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v1(
  p_days    INTEGER DEFAULT 7,
  p_region  TEXT    DEFAULT NULL,
  p_country TEXT    DEFAULT NULL,
  p_city    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  total_reports    BIGINT,
  reports_with_geo BIGINT,
  geo_coverage_pct NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH r AS (
      SELECT r.*, c.region, c.country_code, c.city_code
      FROM public.reports r
      LEFT JOIN public.confessions c ON c.id = r.confession_id
      WHERE r.created_at >= now() - make_interval(days => p_days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    ),
    a AS (
      SELECT
        count(*)                                                                    AS total,
        count(*) FILTER (WHERE city_code IS NOT NULL OR country_code IS NOT NULL)  AS with_geo
      FROM r
    )
    SELECT
      total,
      with_geo,
      CASE WHEN total > 0 THEN with_geo * 100.0 / total ELSE 0 END
    FROM a;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_geo_coverage_v1(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_geo_coverage_v1(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_geo_coverage_v1(INTEGER, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B5: get_reports_geo_coverage_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_geo_coverage_v2(
  p_days         INTEGER DEFAULT 7,
  p_region       TEXT    DEFAULT NULL,
  p_country_code TEXT    DEFAULT NULL,
  p_city_code    TEXT    DEFAULT NULL
)
RETURNS TABLE(
  total_reports        BIGINT,
  backfillable_reports BIGINT,
  ungeocodable_reports BIGINT,
  region_covered       BIGINT,
  city_covered         BIGINT,
  country_covered      BIGINT,
  region_pct           NUMERIC,
  city_pct             NUMERIC,
  country_pct          NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH r AS (
      SELECT r.*, c.region, c.country_code, c.city_code
      FROM public.reports r
      LEFT JOIN public.confessions c ON c.id = r.confession_id
      WHERE r.created_at >= now() - make_interval(days => p_days)
        AND (p_region       IS NULL OR c.region       = p_region)
        AND (p_country_code IS NULL OR c.country_code = p_country_code)
        AND (p_city_code    IS NULL OR c.city_code    = p_city_code)
    ),
    a AS (
      SELECT
        count(*)                                              AS total,
        count(*) FILTER (WHERE confession_id IS NOT NULL)    AS backfillable,
        count(*) FILTER (WHERE confession_id IS NULL)        AS ungeocodable,
        count(*) FILTER (WHERE region       IS NOT NULL)     AS region_count,
        count(*) FILTER (WHERE city_code    IS NOT NULL)     AS city_count,
        count(*) FILTER (WHERE country_code IS NOT NULL)     AS country_count
      FROM r
    )
    SELECT
      total, backfillable, ungeocodable,
      region_count, city_count, country_count,
      CASE WHEN backfillable > 0 THEN region_count  * 100.0 / backfillable ELSE 0 END,
      CASE WHEN backfillable > 0 THEN city_count    * 100.0 / backfillable ELSE 0 END,
      CASE WHEN backfillable > 0 THEN country_count * 100.0 / backfillable ELSE 0 END
    FROM a;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_geo_coverage_v2(INTEGER, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(INTEGER, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_geo_coverage_v2(INTEGER, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B6: get_reports_hotspots_v1
-- ---------------------------------------------------------------------------
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
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH reps AS (
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
      cr.rep_city,
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
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_hotspots_v1(INTEGER, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_hotspots_v1(INTEGER, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_hotspots_v1(INTEGER, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B7: get_reports_breakdown_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_breakdown_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  top_reasons   JSONB,
  top_locations JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH params AS (
      SELECT public._lethe_reports_range_days(p_range) AS days
    ),
    reps AS (
      SELECT rep.reason, c.city_code AS rep_city, c.region AS rep_region, c.country_code AS rep_country
      FROM public.reports rep
      LEFT JOIN public.confessions c ON c.id = rep.confession_id
      CROSS JOIN params p
      WHERE rep.created_at >= now() - make_interval(days => p.days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    ),
    total AS (
      SELECT count(*)::NUMERIC AS n FROM reps
    ),
    reasons AS (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'key',   x.reason,
            'count', x.cnt,
            'pct',   CASE WHEN tot.n > 0 THEN ROUND(x.cnt * 100.0 / tot.n, 1) ELSE 0 END
          ) ORDER BY x.cnt DESC
        ),
        '[]'::jsonb
      ) AS reasons_data
      FROM (SELECT reason, count(*) AS cnt FROM reps GROUP BY reason LIMIT 8) x,
           total tot
    ),
    locations AS (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'key',   x.city_code,
            'count', x.cnt,
            'pct',   CASE WHEN tot.n > 0 THEN ROUND(x.cnt * 100.0 / tot.n, 1) ELSE 0 END
          ) ORDER BY x.cnt DESC
        ),
        '[]'::jsonb
      ) AS locations_data
      FROM (SELECT COALESCE(rep_city, 'unknown') AS city_code, count(*) AS cnt
            FROM reps
            GROUP BY COALESCE(rep_city, 'unknown')
            LIMIT 8) x,
           total tot
    )
    SELECT rsn.reasons_data, loc.locations_data
    FROM reasons rsn, locations loc;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_breakdown_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_breakdown_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_breakdown_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B8: get_reports_trend_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_trend_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  trend JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH params AS (
      SELECT public._lethe_reports_range_days(p_range) AS days
    ),
    date_series AS (
      SELECT generate_series(
        (current_date - ((SELECT days FROM params) - 1)),
        current_date,
        interval '1 day'
      )::DATE AS d
    ),
    counts AS (
      SELECT rep.created_at::DATE AS d, count(*) AS cnt
      FROM public.reports rep
      LEFT JOIN public.confessions c ON c.id = rep.confession_id
      CROSS JOIN params p
      WHERE rep.created_at >= now() - make_interval(days => p.days)
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
      GROUP BY 1
    )
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'ts',    ds.d::TEXT,
          'label', to_char(ds.d, 'Mon DD'),
          'count', COALESCE(c.cnt, 0)
        ) ORDER BY ds.d
      ),
      '[]'::jsonb
    )
    FROM date_series ds
    LEFT JOIN counts c ON c.d = ds.d;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_trend_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_trend_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_trend_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- B9: get_reports_map_v2
-- Also references c.lat/c.lng (PRESENT in production) but c.region/c.city_code
-- are absent. Exception handler returns empty map safely.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_reports_map_v2(
  p_range   TEXT DEFAULT '7d',
  p_region  TEXT DEFAULT NULL,
  p_country TEXT DEFAULT NULL,
  p_city    TEXT DEFAULT NULL
)
RETURNS TABLE(
  markers JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH params AS (
      SELECT public._lethe_reports_range_days(p_range) AS days
    ),
    reps AS (
      SELECT rep.reason, c.city_code AS rep_city, c.region AS rep_region,
             c.lat AS rep_lat, c.lng AS rep_lng, c.is_hidden
      FROM public.reports rep
      JOIN public.confessions c ON c.id = rep.confession_id
      CROSS JOIN params p
      WHERE rep.created_at >= now() - make_interval(days => p.days)
        AND c.lat IS NOT NULL
        AND c.lng IS NOT NULL
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
        AND (p_city    IS NULL OR c.city_code    = p_city)
    ),
    city_counts AS (
      SELECT
        rep_city,
        rep_region,
        avg(rep_lat)                                             AS avg_lat,
        avg(rep_lng)                                             AS avg_lng,
        count(*)                                                 AS reps_count,
        count(*) FILTER (WHERE COALESCE(is_hidden, false))      AS hidden_count
      FROM reps
      GROUP BY rep_city, rep_region
    ),
    top_reason AS (
      SELECT DISTINCT ON (rep_city) rep_city, reason
      FROM (
        SELECT rep_city, reason, count(*) AS cnt
        FROM reps
        GROUP BY rep_city, reason
      ) x
      ORDER BY rep_city, cnt DESC
    )
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'city_code',  cc.rep_city,
          'region',     cc.rep_region,
          'lat',        cc.avg_lat,
          'lng',        cc.avg_lng,
          'reports',    cc.reps_count,
          'hidden',     cc.hidden_count,
          'top_reason', tr.reason
        ) ORDER BY cc.reps_count DESC
      ),
      '[]'::jsonb
    )
    FROM city_counts cc
    LEFT JOIN top_reason tr ON tr.rep_city = cc.rep_city;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_reports_map_v2(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_reports_map_v2(TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_reports_map_v2(TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- =============================================================================
-- [C] ANALYTICS / TRENDS — exception handler + empty RETURN
-- =============================================================================

-- ---------------------------------------------------------------------------
-- C1: get_sessions_by_country_range
-- Uses _lethe_event_filtered which returns SETOF event_logs.
-- In production event_logs has no country_code → undefined_column on e.country_code.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_sessions_by_country_range(
  p_start_ts     TIMESTAMPTZ,
  p_end_ts       TIMESTAMPTZ,
  p_region       TEXT DEFAULT NULL,
  p_country_code TEXT DEFAULT NULL,
  p_city_code    TEXT DEFAULT NULL,
  p_mode         TEXT DEFAULT NULL
)
RETURNS TABLE(
  country_code TEXT,
  sessions     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    SELECT e.country_code, count(DISTINCT e.session_hash)::BIGINT AS sess_count
    FROM public._lethe_event_filtered(
      p_start_ts, p_end_ts, p_region, p_country_code, p_city_code, p_mode
    ) e
    WHERE e.event_name = 'session_start'
      AND e.country_code IS NOT NULL
    GROUP BY e.country_code
    ORDER BY 2 DESC;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_sessions_by_country_range(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_sessions_by_country_range(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_sessions_by_country_range(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- C2: get_latest_metrics_day
-- References event_logs.region in WHERE clause.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_latest_metrics_day(
  p_city   TEXT DEFAULT NULL,
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE(
  day_bucket DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    SELECT max(e.day_bucket)
    FROM public.event_logs e
    WHERE e.event_name = 'session_start'
      AND (p_region IS NULL OR p_region = 'WORLD' OR e.region    = p_region)
      AND (p_city   IS NULL OR p_city   = 'WORLD' OR e.city_code = p_city);
  EXCEPTION WHEN undefined_column THEN
    -- event_logs.region absent — return latest day without region filter
    RETURN QUERY
    SELECT max(e.day_bucket)
    FROM public.event_logs e
    WHERE e.event_name = 'session_start'
      AND (p_city IS NULL OR p_city = 'WORLD' OR e.city_code = p_city);
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_latest_metrics_day(TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_latest_metrics_day(TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_latest_metrics_day(TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- C3: get_trends_comparison_v1
-- References event_logs.country_code and event_logs.region.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trends_comparison_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 7,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  scope_key      TEXT,
  metric_key     TEXT,
  current_value  NUMERIC,
  previous_value NUMERIC,
  delta_abs      NUMERIC,
  delta_pct      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH bounds AS (
      SELECT
        p_end_date - (p_days - 1)       AS cur_start,
        p_end_date                       AS cur_end,
        p_end_date - (p_days * 2 - 1)   AS prev_start,
        p_end_date - p_days              AS prev_end
    ),
    evt_scopes AS (
      SELECT
        CASE WHEN p_scope = 'country' THEN e.country_code
             ELSE COALESCE(p_region, 'global')
        END AS sk,
        e.*
      FROM public.event_logs e
      WHERE (p_region IS NULL OR e.region = p_region OR e.country_code = p_region)
        AND (p_scope <> 'country' OR e.country_code IS NOT NULL)
    ),
    agg AS (
      SELECT x.sk, x.mk, x.period, x.val
      FROM (
        SELECT
          m.sk,
          m.mk,
          CASE WHEN m.day_bucket BETWEEN b.cur_start AND b.cur_end
               THEN 'cur' ELSE 'prev'
          END AS period,
          CASE
            WHEN m.mk = 'sessions' THEN count(DISTINCT m.session_hash)::NUMERIC
            ELSE count(*)::NUMERIC
          END AS val
        FROM (
          SELECT sk, day_bucket, session_hash, 'sessions'  AS mk FROM evt_scopes WHERE event_name = 'session_start'
          UNION ALL
          SELECT sk, day_bucket, session_hash, 'reads'     AS mk FROM evt_scopes WHERE event_name IN ('feed_view','page_fetch')
          UNION ALL
          SELECT sk, day_bucket, session_hash, 'posts'     AS mk FROM evt_scopes WHERE event_name = 'post_success'
          UNION ALL
          SELECT sk, day_bucket, session_hash, 'ads_shown' AS mk FROM evt_scopes WHERE event_name = 'ad_shown'
        ) m, bounds b
        WHERE m.day_bucket BETWEEN b.prev_start AND b.cur_end
        GROUP BY m.sk, m.mk,
                 CASE WHEN m.day_bucket BETWEEN b.cur_start AND b.cur_end
                      THEN 'cur' ELSE 'prev' END
      ) x
    ),
    pivot AS (
      SELECT
        a.sk,
        a.mk,
        COALESCE(sum(a.val) FILTER (WHERE a.period = 'cur'),  0) AS cur_val,
        COALESCE(sum(a.val) FILTER (WHERE a.period = 'prev'), 0) AS prev_val
      FROM agg a
      GROUP BY a.sk, a.mk
    )
    SELECT
      pv.sk,
      pv.mk,
      pv.cur_val,
      pv.prev_val,
      pv.cur_val - pv.prev_val,
      CASE WHEN pv.prev_val > 0
           THEN (pv.cur_val - pv.prev_val) * 100.0 / pv.prev_val
           ELSE NULL
      END
    FROM pivot pv
    ORDER BY pv.mk, pv.cur_val DESC;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_comparison_v1(TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_comparison_v1(TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_comparison_v1(TEXT, TEXT, INTEGER, DATE) TO authenticated;


-- ---------------------------------------------------------------------------
-- C4: get_trends_trendline_v1
-- References event_logs.region and event_logs.country_code.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trends_trendline_v1(
  p_region   TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 30,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  day        DATE,
  metric_key TEXT,
  value      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH date_series AS (
      SELECT generate_series(
        p_end_date - (p_days - 1),
        p_end_date,
        interval '1 day'
      )::DATE AS d
    ),
    filtered AS (
      SELECT el.*
      FROM public.event_logs el
      WHERE (p_region IS NULL OR el.region = p_region OR el.country_code = p_region)
    ),
    metrics AS (
      SELECT ds.d, 'sessions' AS mk, count(DISTINCT e.session_hash)::NUMERIC AS val
      FROM date_series ds
      LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name = 'session_start'
      GROUP BY ds.d
      UNION ALL
      SELECT ds.d, 'reads', count(e.*)::NUMERIC
      FROM date_series ds
      LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name IN ('feed_view','page_fetch')
      GROUP BY ds.d
      UNION ALL
      SELECT ds.d, 'posts', count(e.*)::NUMERIC
      FROM date_series ds
      LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name = 'post_success'
      GROUP BY ds.d
      UNION ALL
      SELECT ds.d, 'ads_shown', count(e.*)::NUMERIC
      FROM date_series ds
      LEFT JOIN filtered e ON e.day_bucket = ds.d AND e.event_name = 'ad_shown'
      GROUP BY ds.d
    )
    SELECT m.d, m.mk, m.val
    FROM metrics m
    ORDER BY m.d, m.mk;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_trendline_v1(TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_trendline_v1(TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_trendline_v1(TEXT, INTEGER, DATE) TO authenticated;


-- ---------------------------------------------------------------------------
-- C5: get_trends_movers_v1 (4-arg core)
-- References confessions.region, confessions.country_code, confessions.emotion_bucket.
-- All three are dev-seed-only.
-- The 5-arg wrapper delegates here; it receives the empty set automatically.
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
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
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
      cur.etag,
      cur.cnt,
      COALESCE(base.bline, 0),
      CASE WHEN COALESCE(base.bline, 0) > 0
           THEN (cur.cnt - base.bline) * 100.0 / base.bline
           ELSE NULL
      END,
      CASE
        WHEN COALESCE(base.bline, 0) < 1 AND cur.cnt >= 5 THEN 'emerging'
        WHEN cur.cnt >= COALESCE(base.bline, 0)            THEN 'rising'
        ELSE 'falling'
      END
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
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_trends_movers_v1(TEXT, TEXT, TEXT, DATE) TO authenticated;


-- ---------------------------------------------------------------------------
-- C6: get_year_wheel_v1 (5-arg core)
-- References event_logs.region/country_code AND confessions.region/country_code/
-- emotion_bucket. All geo cols absent in production; emotion_bucket absent too.
-- The 6-arg wrapper delegates here; it receives the empty set automatically.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_year_wheel_v1(
  p_scope    TEXT    DEFAULT 'global',
  p_region   TEXT    DEFAULT NULL,
  p_country  TEXT    DEFAULT NULL,
  p_days     INTEGER DEFAULT 365,
  p_end_date DATE    DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  month_start       DATE,
  sessions          BIGINT,
  posts             BIGINT,
  posts_per_session NUMERIC,
  mood_pos          BIGINT,
  mood_neg          BIGINT,
  mood_balance      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    RETURN QUERY
    WITH months AS (
      SELECT generate_series(
        date_trunc('month', p_end_date::TIMESTAMP - make_interval(days => p_days)),
        date_trunc('month', p_end_date::TIMESTAMP),
        interval '1 month'
      )::DATE AS m
    ),
    event_months AS (
      SELECT
        date_trunc('month', e.created_at)::DATE                                    AS em_month,
        count(DISTINCT e.session_hash) FILTER (WHERE e.event_name = 'session_start') AS em_sessions,
        count(*) FILTER (WHERE e.event_name = 'post_success')                      AS em_posts
      FROM public.event_logs e
      WHERE e.day_bucket >= p_end_date - p_days
        AND (p_region  IS NULL OR e.region       = p_region)
        AND (p_country IS NULL OR e.country_code = p_country)
      GROUP BY 1
    ),
    confession_months AS (
      SELECT
        date_trunc('month', c.created_at)::DATE                                                        AS cm_month,
        count(*) FILTER (WHERE c.emotion_bucket IN ('hopeful','calm','grateful'))                      AS cm_mood_pos,
        count(*) FILTER (WHERE c.emotion_bucket IN ('lonely','anxious','sad','tired','restless'))      AS cm_mood_neg,
        count(*)                                                                                        AS cm_total
      FROM public.confessions c
      WHERE c.created_at::DATE >= p_end_date - p_days
        AND (p_region  IS NULL OR c.region       = p_region)
        AND (p_country IS NULL OR c.country_code = p_country)
      GROUP BY 1
    )
    SELECT
      m.m,
      COALESCE(e.em_sessions, 0),
      COALESCE(e.em_posts, 0),
      CASE WHEN COALESCE(e.em_sessions, 0) > 0
           THEN e.em_posts::NUMERIC / e.em_sessions
           ELSE NULL
      END,
      COALESCE(c.cm_mood_pos, 0),
      COALESCE(c.cm_mood_neg, 0),
      CASE WHEN COALESCE(c.cm_total, 0) > 0
           THEN (c.cm_mood_pos - c.cm_mood_neg)::NUMERIC / c.cm_total
           ELSE NULL
      END
    FROM months m
    LEFT JOIN event_months      e ON e.em_month = m.m
    LEFT JOIN confession_months c ON c.cm_month = m.m
    ORDER BY m.m;
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_year_wheel_v1(TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;


-- ---------------------------------------------------------------------------
-- C7: get_emotion_fingerprint_v1 (5-arg core)
-- References confessions.region, confessions.country_code, confessions.emotion_bucket.
-- The 6-arg wrapper delegates here; it receives the empty set automatically.
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
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
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
  EXCEPTION WHEN undefined_column OR undefined_table OR undefined_function THEN
    RETURN;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, INTEGER, DATE) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_emotion_fingerprint_v1(TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;


-- =============================================================================
-- [D] FILTER OPTIONS — information_schema guard + exception fallback
-- =============================================================================

-- ---------------------------------------------------------------------------
-- D1: get_insights_region_options
-- event_logs.region absent in production → guard returns empty list (correct).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_insights_region_options()
RETURNS TABLE(region TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Guard: if event_logs.region column absent, return empty options
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'event_logs'
      AND column_name  = 'region'
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT e.region
  FROM public.event_logs e
  WHERE e.region IS NOT NULL
  ORDER BY e.region;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_insights_region_options() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_insights_region_options() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_insights_region_options() TO authenticated;


-- ---------------------------------------------------------------------------
-- D2: get_insights_country_options
-- event_logs.country_code (and .region for filtering) absent in production.
-- Guard returns empty list (correct: no country dimension available).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_insights_country_options(
  p_region TEXT DEFAULT NULL
)
RETURNS TABLE(country_code TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  -- Guard: if event_logs.country_code absent, return empty options
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'event_logs'
      AND column_name  = 'country_code'
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT e.country_code
  FROM public.event_logs e
  WHERE e.country_code IS NOT NULL
    AND (p_region IS NULL OR e.region = p_region)
  ORDER BY e.country_code;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_insights_country_options(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_insights_country_options(TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_insights_country_options(TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- D3: get_insights_city_options
-- event_logs.city_code IS present in production; the WHERE filter clauses
-- for p_country_code (e.country_code) and p_region (e.region) are NOT.
-- Fallback: return all city codes without geo hierarchy filtering.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_insights_city_options(
  p_country_code TEXT DEFAULT NULL,
  p_region       TEXT DEFAULT NULL
)
RETURNS TABLE(city_code TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    RETURN;
  END IF;

  BEGIN
    -- Primary path: full hierarchy filtering (requires country_code and region cols)
    RETURN QUERY
    SELECT DISTINCT e.city_code
    FROM public.event_logs e
    WHERE e.city_code IS NOT NULL
      AND (p_country_code IS NULL OR e.country_code = p_country_code)
      AND (p_region       IS NULL OR e.region       = p_region)
    ORDER BY e.city_code;
  EXCEPTION WHEN undefined_column THEN
    -- Geo filter columns absent — return all city codes without hierarchy filtering
    RETURN QUERY
    SELECT DISTINCT e.city_code
    FROM public.event_logs e
    WHERE e.city_code IS NOT NULL
    ORDER BY e.city_code;
  END;
END;
$$;

REVOKE ALL     ON FUNCTION public.get_insights_city_options(TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_insights_city_options(TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_insights_city_options(TEXT, TEXT) TO authenticated;
