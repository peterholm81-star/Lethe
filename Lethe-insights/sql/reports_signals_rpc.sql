-- ============================================================
-- RPC: get_reports_signals
-- ============================================================
-- Returns daily signals for Reports moderation dashboard.
-- Combines reports data, moderation_actions, and reader metrics.
--
-- Parameters:
-- - p_date text (YYYY-MM-DD) - required
-- - p_city text - reserved for future (ignored in v1)
-- - p_region text - reserved for future (ignored in v1)
--
-- READS DEFINITION:
-- - reads = COUNT(DISTINCT session_hash) WHERE event_name = 'page_fetch'
-- - Data source: public.event_logs table
-- - A "read" is a unique session that fetched at least one page on the date.
--
-- Returns exactly one row with metrics for the date.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_reports_signals(text, text, text);

CREATE OR REPLACE FUNCTION public.get_reports_signals(
  p_date text,
  p_city text DEFAULT NULL,
  p_region text DEFAULT NULL
)
RETURNS TABLE (
  date date,
  reports_total bigint,
  reports_unhandled bigint,
  confessions_reported bigint,
  actions_total bigint,
  actions_hide bigint,
  actions_unhide bigint,
  actions_handle_reports bigint,
  actions_unhandle_reports bigint,
  severity_score bigint,
  spike_score bigint,
  is_spike boolean,
  -- NEW: Reads metrics
  reads_today bigint,
  reads_prev_day bigint,
  reports_per_1k_reads numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date date;
  v_reports_total bigint;
  v_reports_unhandled bigint;
  v_confessions_reported bigint;
  v_actions_total bigint;
  v_actions_hide bigint;
  v_actions_unhide bigint;
  v_actions_handle_reports bigint;
  v_actions_unhandle_reports bigint;
  v_actions_yesterday bigint;
  v_severity_score bigint;
  v_spike_score bigint;
  v_is_spike boolean;
  -- NEW: Reads variables
  v_reads_today bigint;
  v_reads_prev_day bigint;
  v_reports_per_1k_reads numeric;
BEGIN
  -- Admin check
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Parse date
  v_date := p_date::date;

  -- ===========================================
  -- REPORTS STATS (from confession_reports)
  -- ===========================================
  SELECT
    COALESCE(COUNT(*), 0),
    COALESCE(COUNT(*) FILTER (WHERE handled = false), 0),
    COALESCE(COUNT(DISTINCT confession_id), 0)
  INTO
    v_reports_total,
    v_reports_unhandled,
    v_confessions_reported
  FROM confession_reports
  WHERE created_at::date = v_date;

  -- ===========================================
  -- ACTIONS STATS (from moderation_actions)
  -- ===========================================
  -- Note: action_type uses new uppercase enum values
  SELECT
    COALESCE(COUNT(*), 0),
    COALESCE(COUNT(*) FILTER (WHERE action_type = 'HIDE_CONFESSION'), 0),
    COALESCE(COUNT(*) FILTER (WHERE action_type = 'UNHIDE_CONFESSION'), 0),
    COALESCE(COUNT(*) FILTER (WHERE action_type = 'MARK_HANDLED'), 0),
    COALESCE(COUNT(*) FILTER (WHERE action_type = 'DISMISS_REPORT'), 0)
  INTO
    v_actions_total,
    v_actions_hide,
    v_actions_unhide,
    v_actions_handle_reports,
    v_actions_unhandle_reports
  FROM moderation_actions
  WHERE created_at::date = v_date;

  -- ===========================================
  -- YESTERDAY ACTIONS (for spike detection)
  -- ===========================================
  SELECT COALESCE(COUNT(*), 0)
  INTO v_actions_yesterday
  FROM moderation_actions
  WHERE created_at::date = v_date - 1;

  -- ===========================================
  -- READS STATS (from event_logs)
  -- ===========================================
  -- Reads = distinct sessions that loaded at least one page (event_name = 'page_fetch')
  -- Note: p_city/p_region filters not applied in v1 (reserved for future)
  
  -- Today's reads
  SELECT COALESCE(COUNT(DISTINCT session_hash), 0)
  INTO v_reads_today
  FROM event_logs
  WHERE event_name = 'page_fetch'
    AND created_at::date = v_date;

  -- Previous day's reads
  SELECT COALESCE(COUNT(DISTINCT session_hash), 0)
  INTO v_reads_prev_day
  FROM event_logs
  WHERE event_name = 'page_fetch'
    AND created_at::date = v_date - 1;

  -- ===========================================
  -- CALCULATED SCORES
  -- ===========================================
  
  -- Severity: hide*5 + unhandled*2 + total*1
  v_severity_score := (v_actions_hide * 5) + (v_reports_unhandled * 2) + (v_reports_total * 1);

  -- Spike score: today - yesterday
  v_spike_score := v_actions_total - v_actions_yesterday;

  -- Is spike: today >= yesterday * 1.5 AND today >= 5
  v_is_spike := (
    v_actions_total >= GREATEST(v_actions_yesterday * 1.5, 1)::bigint
    AND v_actions_total >= 5
  );

  -- Reports per 1k reads: (reports / reads) * 1000
  -- NULL if no reads to avoid division by zero
  IF v_reads_today > 0 THEN
    v_reports_per_1k_reads := ROUND((v_reports_total::numeric / v_reads_today) * 1000, 2);
  ELSE
    v_reports_per_1k_reads := NULL;
  END IF;

  -- ===========================================
  -- RETURN
  -- ===========================================
  RETURN QUERY SELECT
    v_date,
    v_reports_total,
    v_reports_unhandled,
    v_confessions_reported,
    v_actions_total,
    v_actions_hide,
    v_actions_unhide,
    v_actions_handle_reports,
    v_actions_unhandle_reports,
    v_severity_score,
    v_spike_score,
    v_is_spike,
    -- NEW fields
    v_reads_today,
    v_reads_prev_day,
    v_reports_per_1k_reads;
END;
$$;

-- Grant execute to authenticated (admin check is in function)
GRANT EXECUTE ON FUNCTION public.get_reports_signals(text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Test query (run in SQL Editor after deploying)
-- ============================================================
-- SELECT * FROM public.get_reports_signals(CURRENT_DATE::text, NULL, NULL);
