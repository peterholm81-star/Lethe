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

const HOOK_NAME = 'PULSE';
const RPC_NAME = 'get_pulse_metrics_range';

export interface PulseMetrics {
  sessions: number;
  readers: number;
  posts: number;
}

export interface UsePulseMetricsResult {
  data: PulseMetrics | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

interface PulseRow {
  sessions?: number;
  readers?: number;
  posts?: number;
}

/**
 * Fetch Pulse metrics using the standardized window-based RPC.
 * Uses get_pulse_metrics_range with p_start_ts/p_end_ts.
 */
export function usePulseMetrics(
  filters: InsightsFilters,
  window: InsightsWindow
): UsePulseMetricsResult {
  const [data, setData] = useState<PulseMetrics | null>(null);
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

      const row = unwrapRpcRow<PulseRow>(result);
      const sessions = Number(row?.sessions) || 0;
      const readers = Number(row?.readers) || 0;
      const posts = Number(row?.posts) || 0;

      setData({ sessions, readers, posts });
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
