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

const HOOK_NAME = 'READERS_WRITERS';
const RPC_NAME = 'get_readers_writers_range';

export interface ReadersWritersMetrics {
  readers: number;
  writers: number;
  writerShare: number; // 0..1
}

export interface UseReadersWritersMetricsResult {
  data: ReadersWritersMetrics | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

interface ReadersWritersRow {
  readers?: number;
  writers?: number;
  writer_share?: number | string;
}

const EMPTY_METRICS: ReadersWritersMetrics = {
  readers: 0,
  writers: 0,
  writerShare: 0,
};

/**
 * Fetch Readers vs Writers metrics using the standardized window-based RPC.
 * Uses get_readers_writers_range with p_start_ts/p_end_ts.
 */
export function useReadersWritersMetrics(
  filters: InsightsFilters,
  window: InsightsWindow
): UseReadersWritersMetricsResult {
  const [data, setData] = useState<ReadersWritersMetrics | null>(null);
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

      const row = unwrapRpcRow<ReadersWritersRow>(result);

      if (row) {
        setData({
          readers: Number(row.readers) || 0,
          writers: Number(row.writers) || 0,
          writerShare: Number(row.writer_share) || 0,
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
      setData(EMPTY_METRICS);
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
