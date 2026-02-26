import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_OVERVIEW';

// =============================================================================
// TYPES
// =============================================================================

export type VisibilityFilter = 'all' | 'visible' | 'hidden';

export interface ReportsOverview {
  totalConfessions: number;
  totalReports: number;
  totalUnhandledReports: number;
  reasonsJson: Record<string, number>;
}

export interface UseReportsOverviewResult {
  overview: ReportsOverview;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// Default empty overview
const EMPTY_OVERVIEW: ReportsOverview = {
  totalConfessions: 0,
  totalReports: 0,
  totalUnhandledReports: 0,
  reasonsJson: {},
};

// =============================================================================
// HOOK
// =============================================================================

export function useReportsOverview(
  onlyUnhandled: boolean = true,
  reason: string | null = null,
  visibility: VisibilityFilter = 'all'
): UseReportsOverviewResult {
  const [overview, setOverview] = useState<ReportsOverview>(EMPTY_OVERVIEW);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Refs for fetch guards - don't use state in useCallback deps
  const inFlightRef = useRef(false);
  const lastParamsKeyRef = useRef<string>('');
  const loggedErrorKeyRef = useRef<string>('');
  const requestIdRef = useRef(0);
  const mountedRef = useRef(true);

  // Stable fetch function - NO state dependencies to avoid loops
  const fetchOverview = useCallback(async (
    p_onlyUnhandled: boolean,
    p_reason: string | null,
    p_visibility: VisibilityFilter,
    force: boolean = false
  ) => {
    // Build params - ALWAYS use null, never undefined
    const visibilityMapped = p_visibility === 'all' ? null : p_visibility;
    const params = {
      p_only_unhandled: p_onlyUnhandled ?? true,
      p_reason: p_reason ?? null,
      p_visibility: visibilityMapped ?? null,
    };

    const paramsKey = JSON.stringify(params);

    // Guard: skip if same params and already fetched (unless forced)
    if (!force && lastParamsKeyRef.current === paramsKey && !inFlightRef.current) {
      return;
    }

    // Guard: skip if already in flight for same params
    if (inFlightRef.current && lastParamsKeyRef.current === paramsKey) {
      return;
    }

    // Increment request ID
    requestIdRef.current += 1;
    const thisRequestId = requestIdRef.current;

    inFlightRef.current = true;
    lastParamsKeyRef.current = paramsKey;

    // Only set loading if component is still mounted
    if (mountedRef.current) {
      setLoading(true);
      setError(null);
    }

    try {
      const { data, error: rpcError } = await supabase.rpc('get_reports_overview', params);

      // Guard: ignore if component unmounted or newer request started
      if (!mountedRef.current || thisRequestId !== requestIdRef.current) {
        return;
      }

      if (rpcError) {
        // Log error only once per params key
        if (loggedErrorKeyRef.current !== paramsKey) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError.message);
          loggedErrorKeyRef.current = paramsKey;
        }

        setError(rpcError.message || 'Failed to load overview');
        setOverview(EMPTY_OVERVIEW);
        return;
      }

      // Safely extract first row from result
      let row: Record<string, unknown> | null = null;
      if (Array.isArray(data) && data.length > 0 && data[0] != null) {
        row = data[0] as Record<string, unknown>;
      } else if (data != null && typeof data === 'object' && !Array.isArray(data)) {
        row = data as Record<string, unknown>;
      }

      if (row) {
        setOverview({
          totalConfessions: typeof row.total_confessions === 'number' ? row.total_confessions : 0,
          totalReports: typeof row.total_reports === 'number' ? row.total_reports : 0,
          totalUnhandledReports: typeof row.total_unhandled_reports === 'number' ? row.total_unhandled_reports : 0,
          reasonsJson: (row.reasons_json && typeof row.reasons_json === 'object') 
            ? row.reasons_json as Record<string, number> 
            : {},
        });
      } else {
        setOverview(EMPTY_OVERVIEW);
      }

      loggedErrorKeyRef.current = ''; // Clear on success

    } catch (err: unknown) {
      // Guard: ignore if component unmounted or newer request started
      if (!mountedRef.current || thisRequestId !== requestIdRef.current) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to load overview';

      // Log error only once per params key
      if (loggedErrorKeyRef.current !== paramsKey) {
        console.error(`[${HOOK_NAME}] Exception:`, message);
        loggedErrorKeyRef.current = paramsKey;
      }

      setError(message);
      setOverview(EMPTY_OVERVIEW);
    } finally {
      inFlightRef.current = false;
      if (mountedRef.current) {
        setLoading(false);
      }
    }
  }, []); // NO dependencies - all params passed as arguments

  // Effect to fetch when params change
  useEffect(() => {
    fetchOverview(onlyUnhandled, reason, visibility, false);
  }, [fetchOverview, onlyUnhandled, reason, visibility]);

  // Cleanup on unmount
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Refetch function for manual refresh
  const refetch = useCallback(() => {
    fetchOverview(onlyUnhandled, reason, visibility, true);
  }, [fetchOverview, onlyUnhandled, reason, visibility]);

  return { overview, loading, error, refetch };
}
