import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { createLatestOnlyGuard, type LatestOnlyGuard } from '../insights/insightsRpc';

const HOOK_NAME = 'MODERATION_ACTIONS';

// =============================================================================
// TYPES
// =============================================================================

export interface ModerationAction {
  id: string;
  created_at: string;
  action_type: string;
  confession_id: string | null;
  report_id: string | null;
  reason: string | null;
  city_code: string | null;
  region: string | null;
  country_code: string | null;
  source: string;
}

export interface UseModerationActionsResult {
  actions: ModerationAction[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// =============================================================================
// HELPER: Convert time range to days
// =============================================================================

function rangeToDays(range: string): number {
  switch (range) {
    case '60m': return 1;
    case '24h': return 1;
    case '7d': return 7;
    case '30d': return 30;
    default: return 7;
  }
}

// =============================================================================
// HOOK: useModerationActions
// =============================================================================

export function useModerationActions(
  timeRange: string = '7d',
  region: string | null = null,
  city: string | null = null,
  limit: number = 25
): UseModerationActionsResult {
  const [actions, setActions] = useState<ModerationAction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());
  const lastKeyRef = useRef<string>('');

  const fetchActions = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${city}|${limit}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && actions.length >= 0 && !loading) {
      return;
    }
    lastKeyRef.current = key;

    const reqId = guardRef.current.nextRequestId();
    setLoading(true);
    setError(null);

    try {
      const { data, error: rpcError } = await supabase.rpc('get_moderation_actions_v1', {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country: null, // Ignored in v1
        p_city: city || null,
        p_limit: limit,
        p_offset: 0,
      });

      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error('[MODERATION_ACTIONS] RPC error:', rpcError);
        }
        // Don't show admin error as error state (just empty list)
        if (rpcError.message?.includes('admin only') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          setActions([]);
        } else {
          setError(rpcError.message || 'Failed to load actions');
          setActions([]);
        }
        setLoading(false);
        return;
      }

      setActions((data as ModerationAction[]) ?? []);
      setLoading(false);

    } catch (err: unknown) {
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to load actions';
      if (import.meta.env.DEV) {
        console.error('[MODERATION_ACTIONS] Fetch error:', err);
      }
      setError(message);
      setActions([]);
      setLoading(false);
    }
  }, [timeRange, region, city, limit, actions.length, loading]);

  useEffect(() => {
    fetchActions();
  }, [timeRange, region, city, limit]); // eslint-disable-line react-hooks/exhaustive-deps

  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchActions(true);
  }, [fetchActions]);

  return { actions, loading, error, refetch };
}

// =============================================================================
// ACTION: logModerationAction
// =============================================================================

export interface LogActionParams {
  actionType: 'HIDE_CONFESSION' | 'UNHIDE_CONFESSION' | 'MARK_HANDLED' | 'DISMISS_REPORT' | 'ESCALATE' | 'ADD_NOTE';
  confessionId?: string;
  reportId?: string;
  reason?: string;
  notes?: string;
  cityCode?: string;
  region?: string;
  countryCode?: string;
  source?: string;
}

export async function logModerationAction(
  params: LogActionParams
): Promise<{ success: boolean; actionId: string | null; error: string | null }> {
  try {
    const context = {
      source: params.source || 'reports_inbox',
      cityCode: params.cityCode || null,
      region: params.region || null,
      countryCode: params.countryCode || null,
      ui_version: 'reports_v2',
      ts: new Date().toISOString(),
    };

    const { data, error } = await supabase.rpc('log_moderation_action', {
      p_action_type: params.actionType,
      p_report_id: params.reportId || null,
      p_confession_id: params.confessionId || null,
      p_reason: params.reason || null,
      p_notes: params.notes || null,
      p_context: context,
    });

    if (error) {
      if (import.meta.env.DEV) {
        console.warn('[MODERATION_ACTIONS] log error:', error);
      }
      return { success: false, actionId: null, error: error.message };
    }

    return { success: true, actionId: data as string, error: null };
  } catch (err) {
    if (import.meta.env.DEV) {
      console.warn('[MODERATION_ACTIONS] log catch:', err);
    }
    return { 
      success: false, 
      actionId: null, 
      error: err instanceof Error ? err.message : 'Unknown error' 
    };
  }
}
