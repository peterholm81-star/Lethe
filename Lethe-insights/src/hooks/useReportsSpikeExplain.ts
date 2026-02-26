import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_SPIKE_EXPLAIN';

// =============================================================================
// TYPES
// =============================================================================

export interface SpikeExplainData {
  spikeDetected: boolean;
  windowHours: number;
  recentReports: number;
  prevReports: number;
  deltaReports: number;
  pctIncrease: number;
  topReason: string | null;
  topRegion: string | null;
  topCity: string | null;
}

export interface UseReportsSpikeExplainResult {
  spike: SpikeExplainData | null;
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
// HOOK: useReportsSpikeExplain
// =============================================================================

export function useReportsSpikeExplain(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null,
  city: string | null = null
): UseReportsSpikeExplainResult {
  const [spike, setSpike] = useState<SpikeExplainData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchSpike = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${country}|${city}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && spike !== null) {
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
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_reports_spike_explain_v1', {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country: country || null,
        p_city: city || null,
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        // Handle auth error gracefully
        if (rpcError.message?.includes('authentication required') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          setSpike(null);
        } else {
          setError(rpcError.message || 'Failed to load spike data');
          setSpike(null);
        }
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      // RPC returns a single row as array
      if (Array.isArray(rpcData) && rpcData.length > 0) {
        const row = rpcData[0];
        setSpike({
          spikeDetected: row.spike_detected ?? false,
          windowHours: row.window_hours ?? 24,
          recentReports: row.recent_reports ?? 0,
          prevReports: row.prev_reports ?? 0,
          deltaReports: row.delta_reports ?? 0,
          pctIncrease: row.pct_increase ?? 0,
          topReason: row.top_reason ?? null,
          topRegion: row.top_region ?? null,
          topCity: row.top_city ?? null,
        });
      } else {
        // Empty result - log in dev and set null
        if (import.meta.env.DEV) {
          console.warn(`[${HOOK_NAME}] Empty result from RPC`);
        }
        setSpike(null);
      }

      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load spike data';
      setError(message);
      setSpike(null);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, city, spike]);

  // Fetch on mount and filter change
  useEffect(() => {
    fetchSpike();
  }, [timeRange, region, country, city]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchSpike(true);
  }, [fetchSpike]);

  return { spike, loading, error, refetch };
}
