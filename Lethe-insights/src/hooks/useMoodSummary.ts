import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'MOOD_SUMMARY';

// =============================================================================
// TYPES
// =============================================================================

export interface MoodBucketData {
  mood_bucket: string;
  total_count: number;
}

export interface UseMoodSummaryResult {
  data: MoodBucketData[];
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
// HOOK: useMoodSummary
// =============================================================================

export function useMoodSummary(
  timeRange: string = '7d',
  region: string | null = null,
  countryCode: string | null = null,
  cityCode: string | null = null
): UseMoodSummaryResult {
  const [data, setData] = useState<MoodBucketData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchMoodSummary = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${countryCode}|${cityCode}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && data.length > 0) {
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
      startDate.setDate(startDate.getDate() - rangeToDays(timeRange));

      const { data: rpcData, error: rpcError } = await supabase.rpc('rpc_get_mood_summary', {
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
        setError(rpcError.message || 'Failed to load mood data');
        setData([]);
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      // RPC returns array of { mood_bucket, total_count }
      if (Array.isArray(rpcData)) {
        setData(rpcData.map(row => ({
          mood_bucket: row.mood_bucket,
          total_count: Number(row.total_count) || 0,
        })));
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
      const message = err instanceof Error ? err.message : 'Failed to load mood data';
      setError(message);
      setData([]);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, countryCode, cityCode, data.length]);

  // Fetch on mount and filter change
  useEffect(() => {
    fetchMoodSummary();
  }, [timeRange, region, countryCode, cityCode]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchMoodSummary(true);
  }, [fetchMoodSummary]);

  return { data, loading, error, refetch };
}
