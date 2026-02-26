import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'MOOD_PULSE';

// =============================================================================
// TYPES
// =============================================================================

export interface MoodPulseData {
  balanceScore: number;
  prevBalanceScore: number;
  deltaBalanceScore: number;
  positiveShare: number;
  negativeShare: number;
  totalConfessions: number;
}

export interface UseMoodPulseResult {
  data: MoodPulseData | null;
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
// HOOK: useMoodPulse
// =============================================================================

export function useMoodPulse(
  timeRange: string = '7d',
  region: string | null = null,
  countryCode: string | null = null,
  cityCode: string | null = null
): UseMoodPulseResult {
  const [data, setData] = useState<MoodPulseData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchPulse = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${countryCode}|${cityCode}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && data !== null) {
      return;
    }

    // Skip if already in-flight
    if (inFlightRef.current) {
      return;
    }

    inFlightRef.current = true;
    lastKeyRef.current = key;
    setLoading(true);
    setError(null);

    try {
      // Calculate date range
      const endDate = new Date();
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - rangeToDays(timeRange) + 1);

      const { data: rpcData, error: rpcError } = await supabase.rpc('rpc_get_mood_pulse', {
        p_start_date: formatDate(startDate),
        p_end_date: formatDate(endDate),
        p_region: region || null,
        p_country_code: countryCode || null,
        p_city_code: cityCode || null,
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        setError(rpcError.message || 'Failed to load mood pulse');
        setData(null);
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      // RPC returns single row as array
      if (Array.isArray(rpcData) && rpcData.length > 0) {
        const row = rpcData[0];
        setData({
          balanceScore: Number(row.balance_score) || 0,
          prevBalanceScore: Number(row.prev_balance_score) || 0,
          deltaBalanceScore: Number(row.delta_balance_score) || 0,
          positiveShare: Number(row.positive_share) || 0,
          negativeShare: Number(row.negative_share) || 0,
          totalConfessions: Number(row.total_confessions) || 0,
        });
      } else {
        setData({
          balanceScore: 0,
          prevBalanceScore: 0,
          deltaBalanceScore: 0,
          positiveShare: 0,
          negativeShare: 0,
          totalConfessions: 0,
        });
      }

      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load mood pulse';
      setError(message);
      setData(null);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, countryCode, cityCode, data]);

  // Fetch on mount and filter change
  useEffect(() => {
    fetchPulse();
  }, [timeRange, region, countryCode, cityCode]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchPulse(true);
  }, [fetchPulse]);

  return { data, loading, error, refetch };
}
