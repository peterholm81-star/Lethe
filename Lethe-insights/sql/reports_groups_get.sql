-- ============================================================
-- RPC: get_reports_groups
-- ============================================================
-- Returns reports grouped by confession_id for admin moderation.
-- Each row = one confession with aggregated report stats.
--
-- Filters:
-- - p_only_unhandled: if true -> include only confessions with unhandled_reports > 0
-- - p_reason: if not null -> include only confessions that have at least one report with that reason
-- - p_visibility: 'visible' | 'hidden' | null
-- Sort:
-- - p_sort: 'last_reported_desc' | 'total_reports_desc' | 'unhandled_reports_desc'
-- ============================================================

DROP FUNCTION IF EXISTS public.get_reports_groups(int, bool);
DROP FUNCTION IF EXISTS public.get_reports_groups(int, bool, text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_groups(
  p_limit int DEFAULT 50,
  p_only_unhandled bool DEFAULT true,
  p_reason text DEFAULT NULL,
  p_visibility text DEFAULT NULL,
  p_sort text DEFAULT 'last_reported_desc'
)
RETURNS TABLE (
  confession_id uuid,
  confession_text text,
  confession_region text,
  confession_is_hidden boolean,
  total_reports bigint,
  unhandled_reports bigint,
  handled_all boolean,
  first_reported_at timestamptz,
  last_reported_at timestamptz,
  reason_breakdown_json jsonb,
  report_city_code_sample text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  RETURN QUERY
  WITH
  reason_agg AS (
    SELECT
      cr.confession_id AS cid,
      jsonb_object_agg(cr.reason, cr.cnt) AS breakdown
    FROM (
      SELECT
        cr2.confession_id,
        cr2.reason,
        COUNT(*)::bigint AS cnt
      FROM confession_reports cr2
      GROUP BY cr2.confession_id, cr2.reason
    ) cr
    GROUP BY cr.confession_id
  ),
  base AS (
    SELECT
      c.id AS cid,
      c.text AS ctext,
      c.region AS cregion,
      COALESCE(c.is_hidden, false) AS cis_hidden,

      COUNT(r.*)::bigint AS total_reports,
      COUNT(*) FILTER (WHERE r.handled = false)::bigint AS unhandled_reports,
      (COUNT(*) FILTER (WHERE r.handled = false) = 0) AS handled_all,

      MIN(r.created_at) AS first_reported_at,
      MAX(r.created_at) AS last_reported_at,

      COALESCE(ra.breakdown, '{}'::jsonb) AS reason_breakdown_json,
      MAX(r.city_code) AS report_city_code_sample

    FROM confession_reports r
    JOIN confessions c ON c.id = r.confession_id
    LEFT JOIN reason_agg ra ON ra.cid = c.id
    WHERE 1=1
      -- visibility filter
      AND (
        p_visibility IS NULL
        OR (p_visibility = 'visible' AND COALESCE(c.is_hidden, false) = false)
        OR (p_visibility = 'hidden'  AND COALESCE(c.is_hidden, false) = true)
      )
      -- reason filter (exists)
      AND (
        p_reason IS NULL
        OR EXISTS (
          SELECT 1
          FROM confession_reports rr
          WHERE rr.confession_id = c.id
            AND rr.reason = p_reason
        )
      )
    GROUP BY c.id, c.text, c.region, COALESCE(c.is_hidden, false), ra.breakdown
  )
  SELECT
    b.cid AS confession_id,
    COALESCE(b.ctext, '')::text AS confession_text,
    COALESCE(b.cregion, '')::text AS confession_region,
    b.cis_hidden AS confession_is_hidden,
    b.total_reports,
    b.unhandled_reports,
    b.handled_all,
    b.first_reported_at,
    b.last_reported_at,
    b.reason_breakdown_json,
    b.report_city_code_sample::text
  FROM base b
  WHERE
    (CASE WHEN p_only_unhandled THEN b.unhandled_reports > 0 ELSE true END)
  ORDER BY
    CASE WHEN p_sort = 'total_reports_desc' THEN b.total_reports END DESC NULLS LAST,
    CASE WHEN p_sort = 'unhandled_reports_desc' THEN b.unhandled_reports END DESC NULLS LAST,
    CASE WHEN p_sort = 'last_reported_desc' THEN b.last_reported_at END DESC NULLS LAST,
    b.last_reported_at DESC NULLS LAST
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_reports_groups(int, bool, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_reports_groups(int, bool, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Test
-- SELECT * FROM public.get_reports_groups(10, true, NULL, NULL, 'last_reported_desc');
