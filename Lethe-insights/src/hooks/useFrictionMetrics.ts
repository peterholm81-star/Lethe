import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import {
  createLatestOnlyGuard,
  unwrapRpcRow,
  getUserErrorMessage,
  logRpcError,
  normalizeText,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';
import type { InsightsFilters, InsightsWindow } from '../contexts/InsightsContext';

const HOOK_NAME = 'FRICTION';
const RPC_NAME = 'get_friction_range';

export interface FrictionMetrics {
  attemptsTotal: number;
  successTotal: number;
  rejectedTotal: number;
  successRate: number; // 0-100
  rejectRate: number;  // 0-100
  frictionScore: number; // rejected / attempts (0-1)
}

export interface UseFrictionMetricsResult {
  data: FrictionMetrics | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

interface FrictionRow {
  attempts_total?: number;
  success_total?: number;
  rejected_total?: number;
}

const EMPTY_METRICS: FrictionMetrics = {
  attemptsTotal: 0,
  successTotal: 0,
  rejectedTotal: 0,
  successRate: 0,
  rejectRate: 0,
  frictionScore: 0,
};

/**
 * Build args for get_friction_range RPC
 * Note: This RPC doesn't use p_mode (friction is mode-agnostic)
 */
function buildFrictionArgs(filters: InsightsFilters, window: InsightsWindow) {
  return {
    p_start_ts: window.startUtcIso,
    p_end_ts: window.endUtcIso,
    p_region: normalizeText(filters.region),
    p_country_code: normalizeText(filters.country_code),
    p_city_code: normalizeText(filters.city_code),
  };
}

/**
 * Fetch Friction metrics using the range-based RPC.
 * Uses get_friction_range with p_start_ts/p_end_ts.
 */
export function useFrictionMetrics(
  filters: InsightsFilters,
  window: InsightsWindow
): UseFrictionMetricsResult {
  const [data, setData] = useState<FrictionMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchMetrics = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    const args = buildFrictionArgs(filters, window);

    try {
      const { data: result, error: rpcError } = await supabase.rpc(RPC_NAME, args);

      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      if (rpcError) throw rpcError;

      const row = unwrapRpcRow<FrictionRow>(result);

      if (row) {
        const attempts = Number(row.attempts_total) || 0;
        const success = Number(row.success_total) || 0;
        const rejected = Number(row.rejected_total) || 0;

        // Calculate rates
        const successRate = attempts > 0 ? Math.round((success / attempts) * 100) : 0;
        const rejectRate = attempts > 0 ? Math.round((rejected / attempts) * 100) : 0;
        const frictionScore = attempts > 0 ? rejected / attempts : 0;

        setData({
          attemptsTotal: attempts,
          successTotal: success,
          rejectedTotal: rejected,
          successRate,
          rejectRate,
          frictionScore,
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
  ]);

  useEffect(() => {
    fetchMetrics();
  }, [fetchMetrics]);

  return { data, loading, error, refetch: fetchMetrics };
}
