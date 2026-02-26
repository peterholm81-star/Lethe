import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORT_GROUPS';

// =============================================================================
// TYPES
// =============================================================================

export type VisibilityFilter = 'all' | 'visible' | 'hidden';
export type SortOption = 'last_reported_desc' | 'total_reports_desc' | 'unhandled_reports_desc';

export interface ReportGroup {
  confession_id: string;
  confession_text: string;
  confession_region: string;
  confession_is_hidden: boolean;
  total_reports: number;
  unhandled_reports: number;
  handled_all: boolean;
  first_reported_at: string;
  last_reported_at: string;
  reason_breakdown_json: Record<string, number>;
  report_city_code_sample: string | null;
}

export interface UseReportGroupsResult {
  groups: ReportGroup[];
  loading: boolean;
  error: string | null;
  isAdminError: boolean;
  refetch: () => void;
}

// =============================================================================
// HOOK: useReportGroups
// =============================================================================

export function useReportGroups(
  onlyUnhandled: boolean = true,
  limit: number = 50,
  reason: string | null = null,
  visibility: VisibilityFilter = 'all',
  sort: SortOption = 'last_reported_desc'
): UseReportGroupsResult {
  const [groups, setGroups] = useState<ReportGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isAdminError, setIsAdminError] = useState(false);

  // Refs for fetch guards - don't use state in useCallback deps
  const inFlightRef = useRef(false);
  const lastParamsKeyRef = useRef<string>('');
  const loggedErrorKeyRef = useRef<string>('');
  const requestIdRef = useRef(0);
  const mountedRef = useRef(true);

  // Stable fetch function - NO state dependencies to avoid loops
  const fetchGroups = useCallback(async (
    p_onlyUnhandled: boolean,
    p_limit: number,
    p_reason: string | null,
    p_visibility: VisibilityFilter,
    p_sort: SortOption,
    force: boolean = false
  ) => {
    // Build params - ALWAYS use null, never undefined
    const visibilityMapped = p_visibility === 'all' ? null : p_visibility;
    const params = {
      p_limit: p_limit ?? 50,
      p_only_unhandled: p_onlyUnhandled ?? true,
      p_reason: p_reason ?? null,
      p_visibility: visibilityMapped ?? null,
      p_sort: p_sort ?? 'last_reported_desc',
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
      setIsAdminError(false);
    }

    try {
      const { data, error: rpcError } = await supabase.rpc('get_reports_groups', params);

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

        const isAdmin = rpcError.message?.includes('admin only') || 
                        rpcError.message?.includes('Access denied');
        
        setIsAdminError(isAdmin);
        setError(isAdmin ? 'Admin only' : (rpcError.message || 'Failed to load report groups'));
        setGroups([]);
        return;
      }

      // Safely extract data - ensure it's an array
      const rows = Array.isArray(data) ? data : [];
      setGroups(rows as ReportGroup[]);
      loggedErrorKeyRef.current = ''; // Clear on success

    } catch (err: unknown) {
      // Guard: ignore if component unmounted or newer request started
      if (!mountedRef.current || thisRequestId !== requestIdRef.current) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to load report groups';
      
      // Log error only once per params key
      if (loggedErrorKeyRef.current !== paramsKey) {
        console.error(`[${HOOK_NAME}] Exception:`, message);
        loggedErrorKeyRef.current = paramsKey;
      }

      const isAdmin = message.includes('admin only') || message.includes('Access denied');
      setIsAdminError(isAdmin);
      setError(message);
      setGroups([]);
    } finally {
      inFlightRef.current = false;
      if (mountedRef.current) {
        setLoading(false);
      }
    }
  }, []); // NO dependencies - all params passed as arguments

  // Effect to fetch when params change
  useEffect(() => {
    fetchGroups(onlyUnhandled, limit, reason, visibility, sort, false);
  }, [fetchGroups, onlyUnhandled, limit, reason, visibility, sort]);

  // Cleanup on unmount
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Refetch function for manual refresh
  const refetch = useCallback(() => {
    fetchGroups(onlyUnhandled, limit, reason, visibility, sort, true);
  }, [fetchGroups, onlyUnhandled, limit, reason, visibility, sort]);

  return { groups, loading, error, isAdminError, refetch };
}

// =============================================================================
// ACTION: setReportsHandledForConfession
// =============================================================================

export async function setReportsHandledForConfession(
  confessionId: string,
  handled: boolean = true
): Promise<{ success: boolean; error: string | null; updatedCount?: number }> {
  try {
    const { data, error } = await supabase.rpc('set_reports_handled_for_confession', {
      p_confession_id: confessionId,
      p_handled: handled,
    });

    if (error) {
      return { success: false, error: error.message };
    }

    // Safely access data - could be null, array, or object
    let updatedCount = 0;
    if (Array.isArray(data) && data.length > 0 && data[0] != null) {
      updatedCount = data[0].updated_count ?? 0;
    } else if (data != null && typeof data === 'object' && 'updated_count' in data) {
      updatedCount = (data as { updated_count?: number }).updated_count ?? 0;
    }

    return { success: true, error: null, updatedCount };
  } catch (err) {
    return { success: false, error: err instanceof Error ? err.message : 'Unknown error' };
  }
}
