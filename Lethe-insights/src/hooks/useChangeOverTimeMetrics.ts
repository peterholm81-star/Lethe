import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import {
  buildWindowArgs,
  createLatestOnlyGuard,
  getUserErrorMessage,
  logRpcError,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';
import type { InsightsFilters, InsightsWindow } from '../contexts/InsightsContext';

const HOOK_NAME = 'CHANGE_OVER_TIME';
const RPC_NAME = 'get_change_over_time_range';

/**
 * Daily metrics for Change Over Time chart (investor-grade KPIs)
 * 
 * Definitions:
 *   sessions         = unique app sessions per day
 *   posts            = successful post submissions per day
 *   post_rate        = posts / sessions (conversion rate, 0-1)
 *   pages_loaded     = pagination events per day (load more clicks)
 *   pages_per_session = pages_loaded / sessions (engagement depth)
 */
export interface DailyMetric {
  day_bucket: string;
  sessions: number;
  posts: number;
  post_rate: number;
  pages_loaded: number;
  pages_per_session: number;
}

export interface UseChangeOverTimeResult {
  data: DailyMetric[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

interface DailyMetricRow {
  day_bucket?: string;
  sessions?: number;
  posts?: number;
  post_rate?: number | string;
  pages_loaded?: number;
  pages_per_session?: number | string;
}

/**
 * Fetch Change Over Time metrics using the standardized window-based RPC.
 * Uses get_change_over_time_range with p_start_ts/p_end_ts.
 * Returns one row per day within the window.
 */
export function useChangeOverTimeMetrics(
  filters: InsightsFilters,
  window: InsightsWindow
): UseChangeOverTimeResult {
  const [data, setData] = useState<DailyMetric[]>([]);
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

      const rows: DailyMetric[] = ((result as DailyMetricRow[]) || []).map((row) => ({
        day_bucket: String(row.day_bucket ?? ''),
        sessions: Number(row.sessions) || 0,
        posts: Number(row.posts) || 0,
        post_rate: Number(row.post_rate) || 0,
        pages_loaded: Number(row.pages_loaded) || 0,
        pages_per_session: Number(row.pages_per_session) || 0,
      }));

      setData(rows);
      setLoading(false);

    } catch (err: unknown) {
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      // Log error once in DEV
      logRpcError(HOOK_NAME, RPC_NAME, err);
      
      // Set user-friendly error message
      setError(getUserErrorMessage(err, HOOK_NAME));
      setData([]);
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
