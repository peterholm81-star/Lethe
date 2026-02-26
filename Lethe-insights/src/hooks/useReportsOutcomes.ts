import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_OUTCOMES';

// =============================================================================
// TYPES
// =============================================================================

export interface ReportsOutcomesData {
  actionedReports: number;
  handledReports: number;
  hiddenReports: number;
  dismissedReports: number;
  escalatedReports: number;
  handledRatePct: number;
  hiddenRatePct: number;
  dismissedRatePct: number;
  escalatedRatePct: number;
}

export interface UseReportsOutcomesResult {
  outcomes: ReportsOutcomesData | null;
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
// HOOK: useReportsOutcomes
// =============================================================================

export function useReportsOutcomes(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null,
  city: string | null = null
): UseReportsOutcomesResult {
  const [outcomes, setOutcomes] = useState<ReportsOutcomesData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchOutcomes = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${country}|${city}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && outcomes !== null) {
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
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_reports_outcomes_v1', {
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
          setOutcomes(null);
        } else {
          setError(rpcError.message || 'Failed to load outcomes');
          setOutcomes(null);
        }
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      // RPC returns a single row as array
      if (Array.isArray(rpcData) && rpcData.length > 0) {
        const row = rpcData[0];
        setOutcomes({
          actionedReports: row.actioned_reports ?? 0,
          handledReports: row.handled_reports ?? 0,
          hiddenReports: row.hidden_reports ?? 0,
          dismissedReports: row.dismissed_reports ?? 0,
          escalatedReports: row.escalated_reports ?? 0,
          handledRatePct: row.handled_rate_pct ?? 0,
          hiddenRatePct: row.hidden_rate_pct ?? 0,
          dismissedRatePct: row.dismissed_rate_pct ?? 0,
          escalatedRatePct: row.escalated_rate_pct ?? 0,
        });
      } else {
        // Empty result - set defaults
        setOutcomes({
          actionedReports: 0,
          handledReports: 0,
          hiddenReports: 0,
          dismissedReports: 0,
          escalatedReports: 0,
          handledRatePct: 0,
          hiddenRatePct: 0,
          dismissedRatePct: 0,
          escalatedRatePct: 0,
        });
      }

      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load outcomes';
      setError(message);
      setOutcomes(null);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, city, outcomes]);

  // Fetch on mount and filter change
  useEffect(() => {
    fetchOutcomes();
  }, [timeRange, region, country, city]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchOutcomes(true);
  }, [fetchOutcomes]);

  return { outcomes, loading, error, refetch };
}
