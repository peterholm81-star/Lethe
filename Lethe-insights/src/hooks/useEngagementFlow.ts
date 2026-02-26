import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import {
  buildWindowArgs,
  createLatestOnlyGuard,
  unwrapRpcRow,
  getUserErrorMessage,
  logRpcError,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';
import type { InsightsFilters, InsightsWindow } from '../contexts/InsightsContext';

const HOOK_NAME = 'ENGAGEMENT';
const RPC_NAME = 'get_engagement_flow_range';

export interface EngagementFlowMetrics {
  sessions: number;
  pages_loaded: number;
  post_attempts: number;
  post_success: number;
  ads_shown: number;
  ads_shown_sessions: number;
  ad_continue_sessions: number;
  ad_drop_sessions: number;
  posts_per_session: number;
  pages_per_session: number;
  ad_continue_rate: number;
}

export interface UseEngagementFlowResult {
  data: EngagementFlowMetrics | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

interface EngagementRow {
  sessions?: number;
  pages_loaded?: number;
  post_attempts?: number;
  post_success?: number;
  ads_shown?: number;
  ads_shown_sessions?: number;
  ad_continue_sessions?: number;
  ad_drop_sessions?: number;
  posts_per_session?: number | string;
  pages_per_session?: number | string;
  ad_continue_rate?: number | string;
}

const EMPTY_METRICS: EngagementFlowMetrics = {
  sessions: 0,
  pages_loaded: 0,
  post_attempts: 0,
  post_success: 0,
  ads_shown: 0,
  ads_shown_sessions: 0,
  ad_continue_sessions: 0,
  ad_drop_sessions: 0,
  posts_per_session: 0,
  pages_per_session: 0,
  ad_continue_rate: 0,
};

/**
 * Fetch Engagement Flow metrics using the standardized window-based RPC.
 * Uses get_engagement_flow_range with p_start_ts/p_end_ts.
 */
export function useEngagementFlow(
  filters: InsightsFilters,
  window: InsightsWindow
): UseEngagementFlowResult {
  const [data, setData] = useState<EngagementFlowMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchMetrics = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    // Use buildWindowArgs (SINGLE SOURCE OF TRUTH)
    const args = buildWindowArgs(filters, window);

    try {
      const { data: result, error: rpcError } = await supabase.rpc(RPC_NAME, args);

      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      if (rpcError) throw rpcError;

      const row = unwrapRpcRow<EngagementRow>(result);

      if (row) {
        setData({
          sessions: Number(row.sessions) || 0,
          pages_loaded: Number(row.pages_loaded) || 0,
          post_attempts: Number(row.post_attempts) || 0,
          post_success: Number(row.post_success) || 0,
          ads_shown: Number(row.ads_shown) || 0,
          ads_shown_sessions: Number(row.ads_shown_sessions) || 0,
          ad_continue_sessions: Number(row.ad_continue_sessions) || 0,
          ad_drop_sessions: Number(row.ad_drop_sessions) || 0,
          posts_per_session: parseFloat(String(row.posts_per_session)) || 0,
          pages_per_session: parseFloat(String(row.pages_per_session)) || 0,
          ad_continue_rate: parseFloat(String(row.ad_continue_rate)) || 0,
        });
      } else {
        setData(EMPTY_METRICS);
      }
      setLoading(false);

    } catch (err: unknown) {
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      // Log error once in DEV
      logRpcError(HOOK_NAME, RPC_NAME, err);
      
      // Set user-friendly error message
      setError(getUserErrorMessage(err, HOOK_NAME));
      setData(null);
      setLoading(false);
    }
  }, [
    window.startUtcIso,
    window.endUtcIso,
    filters.region,
    filters.country_code,
    filters.city_code,
    filters.mode,
  ]);

  useEffect(() => {
    fetchMetrics();
  }, [fetchMetrics]);

  return { data, loading, error, refetch: fetchMetrics };
}
