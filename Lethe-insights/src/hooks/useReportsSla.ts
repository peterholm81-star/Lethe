import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_SLA';

// =============================================================================
// TYPES
// =============================================================================

export interface ReportsSlaData {
  medianMinutes: number | null;
  p90Minutes: number | null;
  oldestPendingMinutes: number | null;
  actionedReports: number;
  pendingReports: number;
}

export interface UseReportsSlaResult {
  data: ReportsSlaData | null;
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
// HOOK: useReportsSla
// =============================================================================

export function useReportsSla(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null,
  city: string | null = null
): UseReportsSlaResult {
  const [data, setData] = useState<ReportsSlaData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchSla = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${country}|${city}`;
    
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
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_reports_sla_v1', {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country: country || null,
        p_city: city || null,
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        // Handle admin-only error gracefully
        if (rpcError.message?.includes('admin only') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          setData(null);
        } else {
          setError(rpcError.message || 'Failed to load SLA data');
          setData(null);
        }
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      // RPC returns a single row as array
      if (Array.isArray(rpcData) && rpcData.length > 0) {
        const row = rpcData[0];
        setData({
          // Preserve null for SLA metrics (null = no data, distinct from 0)
          medianMinutes: row.median_minutes,
          p90Minutes: row.p90_minutes,
          oldestPendingMinutes: row.oldest_pending_minutes,
          actionedReports: row.actioned_reports ?? 0,
          pendingReports: row.pending_reports ?? 0,
        });
      } else {
        // Empty result - set defaults
        setData({
          medianMinutes: null,
          p90Minutes: null,
          oldestPendingMinutes: null,
          actionedReports: 0,
          pendingReports: 0,
        });
      }

      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load SLA data';
      setError(message);
      setData(null);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, city, data]);

  // Fetch on mount and filter change
  useEffect(() => {
    fetchSla();
  }, [timeRange, region, country, city]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchSla(true);
  }, [fetchSla]);

  return { data, loading, error, refetch };
}
