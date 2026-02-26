import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { createLatestOnlyGuard, type LatestOnlyGuard } from '../insights/insightsRpc';
import { logModerationAction } from './useModerationActions';

const HOOK_NAME = 'REPORTS';

// =============================================================================
// TYPES
// =============================================================================

export interface ReportRow {
  report_id: string;
  report_created_at: string;
  reason: string;
  details: string | null;
  report_city_code: string | null;
  confession_id: string;
  confession_region: string;
  confession_text: string;
  confession_is_hidden: boolean;
  handled: boolean;
  handled_at: string | null;
  handled_by: string | null;
}

export interface UseReportsInboxResult {
  rows: ReportRow[];
  loading: boolean;
  error: string | null;
  isAdminError: boolean;
  refetch: () => void;
}

// =============================================================================
// HOOK: useReportsInbox
// =============================================================================

export function useReportsInbox(
  onlyUnhandled: boolean = true,
  limit: number = 50
): UseReportsInboxResult {
  const [rows, setRows] = useState<ReportRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isAdminError, setIsAdminError] = useState(false);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchReports = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);
    setIsAdminError(false);

    try {
      const { data, error: rpcError } = await supabase.rpc('get_reports_inbox', {
        p_limit: limit,
        p_only_unhandled: onlyUnhandled,
      });

      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error('[REPORTS] RPC error:', rpcError);
        }
        if (rpcError.message?.includes('admin only') || 
            rpcError.message?.includes('Access denied')) {
          setIsAdminError(true);
          setError('Admin only');
        } else {
          setError(rpcError.message || 'Failed to load reports');
        }
        setRows([]);
        setLoading(false);
        return;
      }

      setRows((data as ReportRow[]) ?? []);
      setLoading(false);

    } catch (err: unknown) {
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to load reports';
      if (import.meta.env.DEV) {
        console.error('[REPORTS] Fetch error:', err);
      }
      if (message.includes('admin only') || message.includes('Access denied')) {
        setIsAdminError(true);
      }
      setError(message);
      setRows([]);
      setLoading(false);
    }
  }, [onlyUnhandled, limit]);

  useEffect(() => {
    fetchReports();
  }, [fetchReports]);

  return { rows, loading, error, isAdminError, refetch: fetchReports };
}

// =============================================================================
// ACTION: setReportHandled (with logging)
// =============================================================================

export interface HandleReportOptions {
  reportId: string;
  confessionId?: string;
  reason?: string;
  cityCode?: string;
  region?: string;
  handled?: boolean;
}

export async function setReportHandled(
  options: HandleReportOptions | string,
  handled: boolean = true
): Promise<{ success: boolean; error: string | null }> {
  // Support both old signature (string) and new (options object)
  const opts: HandleReportOptions = typeof options === 'string' 
    ? { reportId: options, handled } 
    : options;

  try {
    const { error } = await supabase.rpc('set_report_handled', {
      p_report_id: opts.reportId,
      p_handled: opts.handled ?? true,
    });

    if (error) {
      if (import.meta.env.DEV) console.error('[REPORTS] setReportHandled error:', error);
      return { success: false, error: error.message };
    }

    // Log the moderation action (best effort - don't fail if logging fails)
    logModerationAction({
      actionType: 'MARK_HANDLED',
      reportId: opts.reportId,
      confessionId: opts.confessionId,
      reason: opts.reason,
      cityCode: opts.cityCode,
      region: opts.region,
      source: 'reports_inbox',
    }).catch((err) => {
      if (import.meta.env.DEV) console.warn('[REPORTS] logging failed:', err);
    });

    return { success: true, error: null };
  } catch (err) {
    if (import.meta.env.DEV) console.error('[REPORTS] setReportHandled catch:', err);
    return { success: false, error: err instanceof Error ? err.message : 'Unknown error' };
  }
}

// =============================================================================
// ACTION: setConfessionHidden (with logging)
// =============================================================================

export interface HideConfessionOptions {
  confessionId: string;
  reportId?: string;
  reason?: string;
  cityCode?: string;
  region?: string;
  hidden?: boolean;
}

export async function setConfessionHidden(
  options: HideConfessionOptions | string,
  hidden: boolean = true
): Promise<{ success: boolean; error: string | null }> {
  // Support both old signature (string) and new (options object)
  const opts: HideConfessionOptions = typeof options === 'string' 
    ? { confessionId: options, hidden } 
    : options;

  const shouldHide = opts.hidden ?? true;

  try {
    const { error } = await supabase.rpc('set_confession_hidden', {
      p_confession_id: opts.confessionId,
      p_hidden: shouldHide,
    });

    if (error) {
      if (import.meta.env.DEV) console.error('[REPORTS] setConfessionHidden error:', error);
      return { success: false, error: error.message };
    }

    // Log the moderation action (best effort - don't fail if logging fails)
    logModerationAction({
      actionType: shouldHide ? 'HIDE_CONFESSION' : 'UNHIDE_CONFESSION',
      confessionId: opts.confessionId,
      reportId: opts.reportId,
      reason: opts.reason,
      cityCode: opts.cityCode,
      region: opts.region,
      source: 'reports_inbox',
    }).catch((err) => {
      if (import.meta.env.DEV) console.warn('[REPORTS] logging failed:', err);
    });

    return { success: true, error: null };
  } catch (err) {
    if (import.meta.env.DEV) console.error('[REPORTS] setConfessionHidden catch:', err);
    return { success: false, error: err instanceof Error ? err.message : 'Unknown error' };
  }
}
