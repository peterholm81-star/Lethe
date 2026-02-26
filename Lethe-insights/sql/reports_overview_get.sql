-- ============================================================
-- RPC: get_reports_overview
-- ============================================================
-- Returns overview metrics for moderation dashboard:
-- - total_confessions (count of grouped items in current filter context)
-- - total_reports
-- - total_unhandled_reports
-- - reasons_json: jsonb { "SPAM": 12, "THREATS": 3, ... }
--
-- Must respect same filters as list:
-- - p_only_unhandled
-- - p_reason (optional)
-- - p_visibility (optional)
-- ============================================================

DROP FUNCTION IF EXISTS public.get_reports_overview(bool, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_overview(
  p_only_unhandled bool DEFAULT true,
  p_reason text DEFAULT NULL,
  p_visibility text DEFAULT NULL
)
RETURNS TABLE (
  total_confessions bigint,
  total_reports bigint,
  total_unhandled_reports bigint,
  reasons_json jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  RETURN QUERY
  WITH filtered_reports AS (
    SELECT r.*
    FROM confession_reports r
    JOIN confessions c ON c.id = r.confession_id
    WHERE 1=1
      AND (
        p_visibility IS NULL
        OR (p_visibility = 'visible' AND COALESCE(c.is_hidden, false) = false)
        OR (p_visibility = 'hidden'  AND COALESCE(c.is_hidden, false) = true)
      )
      AND (
        p_reason IS NULL
        OR r.reason = p_reason
      )
  ),
  grouped AS (
    SELECT
      fr.confession_id AS cid,
      COUNT(*)::bigint AS reports_cnt,
      COUNT(*) FILTER (WHERE fr.handled = false)::bigint AS unhandled_cnt
    FROM filtered_reports fr
    GROUP BY fr.confession_id
  ),
  grouped_filtered AS (
    SELECT *
    FROM grouped
    WHERE (CASE WHEN p_only_unhandled THEN unhandled_cnt > 0 ELSE true END)
  ),
  reasons AS (
    SELECT
      jsonb_object_agg(x.reason, x.cnt) AS rjson
    FROM (
      SELECT fr.reason, COUNT(*)::bigint AS cnt
      FROM filtered_reports fr
      JOIN grouped_filtered gf ON gf.cid = fr.confession_id
      GROUP BY fr.reason
      ORDER BY COUNT(*) DESC
    ) x
  )
  SELECT
    (SELECT COUNT(*)::bigint FROM grouped_filtered) AS total_confessions,
    (SELECT COALESCE(SUM(reports_cnt),0)::bigint FROM grouped_filtered) AS total_reports,
    (SELECT COALESCE(SUM(unhandled_cnt),0)::bigint FROM grouped_filtered) AS total_unhandled_reports,
    COALESCE((SELECT rjson FROM reasons), '{}'::jsonb) AS reasons_json;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_reports_overview(bool, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_reports_overview(bool, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Test
-- SELECT * FROM public.get_reports_overview(true, NULL, NULL);
