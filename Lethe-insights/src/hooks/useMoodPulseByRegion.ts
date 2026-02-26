import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'MOOD_PULSE_BY_REGION';

// =============================================================================
// TYPES
// =============================================================================

export interface RegionPulseData {
  region: string;
  balanceScore: number;
  prevBalanceScore: number;
  deltaBalanceScore: number;
  positiveShare: number;
  negativeShare: number;
  totalConfessions: number;
}

export interface UseMoodPulseByRegionResult {
  data: RegionPulseData[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// =============================================================================
// HELPER: Convert time range to days
// =============================================================================

function rangeToDays(range: string): number {
  switch (range) {
    case '24h': return 1;
    case '7d': return 7;
    case '30d': return 30;
    default: return 7;
  }
}

// =============================================================================
// HELPER: Format date as YYYY-MM-DD
// =============================================================================

function formatDate(date: Date): string {
  return date.toISOString().split('T')[0];
}

// =============================================================================
// HOOK: useMoodPulseByRegion
// =============================================================================

export function useMoodPulseByRegion(
  timeRange: string = '7d'
): UseMoodPulseByRegionResult {
  const [data, setData] = useState<RegionPulseData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchData = useCallback(async (force: boolean = false) => {
    const key = timeRange;
    
    if (!force && key === lastKeyRef.current && data.length > 0) {
      return;
    }

    if (inFlightRef.current) {
      return;
    }

    inFlightRef.current = true;
    lastKeyRef.current = key;
    setLoading(true);
    setError(null);

    try {
      const endDate = new Date();
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - rangeToDays(timeRange) + 1);

      const { data: rpcData, error: rpcError } = await supabase.rpc('rpc_get_mood_pulse_by_region', {
        p_start_date: formatDate(startDate),
        p_end_date: formatDate(endDate),
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        setError(rpcError.message || 'Failed to load regional mood data');
        setData([]);
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      if (Array.isArray(rpcData)) {
        const mapped: RegionPulseData[] = rpcData.map((row) => ({
          region: row.region || 'Unknown',
          balanceScore: Number(row.balance_score) || 0,
          prevBalanceScore: Number(row.prev_balance_score) || 0,
          deltaBalanceScore: Number(row.delta_balance_score) || 0,
          positiveShare: Number(row.positive_share) || 0,
          negativeShare: Number(row.negative_share) || 0,
          totalConfessions: Number(row.total_confessions) || 0,
        }));
        setData(mapped);
      } else {
        setData([]);
      }

      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load regional mood data';
      setError(message);
      setData([]);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, data.length]);

  useEffect(() => {
    fetchData();
  }, [timeRange]); // eslint-disable-line react-hooks/exhaustive-deps

  const refetch = useCallback(() => {
    lastKeyRef.current = '';
    fetchData(true);
  }, [fetchData]);

  return { data, loading, error, refetch };
}
