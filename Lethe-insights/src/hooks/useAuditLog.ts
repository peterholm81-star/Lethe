import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'AUDIT_LOG';

// =============================================================================
// TYPES
// =============================================================================

// Canonical action type values (normalized)
export type ActionTypeFilter = 'all' | 'hidden' | 'dismissed' | 'escalated' | 'handled';

export interface AuditLogEntry {
  id: string;
  created_at: string;
  action_type: string;
  confession_id: string | null;
  report_id: string | null;
  reason: string | null;
  city_code: string | null;
  region: string | null;
  country_code: string | null;
  source: string;
}

export interface UseAuditLogResult {
  entries: AuditLogEntry[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
  loadMore: () => void;
  hasMore: boolean;
  actionFilter: ActionTypeFilter;
  setActionFilter: (filter: ActionTypeFilter) => void;
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
// HOOK: useAuditLog
// =============================================================================

export function useAuditLog(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null,
  city: string | null = null,
  limit: number = 20
): UseAuditLogResult {
  const [entries, setEntries] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const [actionFilter, setActionFilterState] = useState<ActionTypeFilter>('all');

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchEntries = useCallback(async (
    currentOffset: number = 0, 
    append: boolean = false,
    force: boolean = false
  ) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${country}|${city}|${actionFilter}|${currentOffset}`;
    
    // Skip if same params and not forced (and not appending)
    if (!force && !append && key === lastKeyRef.current && entries.length > 0) {
      return;
    }

    // Skip if already in-flight
    if (inFlightRef.current) {
      return;
    }

    inFlightRef.current = true;
    if (!append) {
      lastKeyRef.current = key;
    }
    setLoading(true);
    setError(null);

    try {
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_moderation_actions_v1', {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country: country || null,
        p_city: city || null,
        p_action_type: actionFilter === 'all' ? null : actionFilter,  // Canonical values
        p_limit: limit,
        p_offset: currentOffset,
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        // Handle auth error gracefully
        if (rpcError.message?.includes('admin only') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          if (!append) setEntries([]);
        } else {
          setError(rpcError.message || 'Failed to load audit log');
          if (!append) setEntries([]);
        }
        setHasMore(false);
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      const newEntries = Array.isArray(rpcData) ? rpcData as AuditLogEntry[] : [];
      
      if (append) {
        setEntries(prev => [...prev, ...newEntries]);
      } else {
        setEntries(newEntries);
      }
      
      // If we got fewer rows than limit, there's no more data
      setHasMore(newEntries.length === limit);
      setOffset(currentOffset + newEntries.length);
      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load audit log';
      setError(message);
      if (!append) setEntries([]);
      setHasMore(false);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, city, actionFilter, limit, entries.length]);

  // Fetch on mount and filter change (reset to first page)
  useEffect(() => {
    setOffset(0);
    setHasMore(true);
    lastKeyRef.current = ''; // Force refetch on filter change
    fetchEntries(0, false, true);
  }, [timeRange, region, country, city, actionFilter]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch (reset to first page)
  const refetch = useCallback(() => {
    setOffset(0);
    setHasMore(true);
    lastKeyRef.current = ''; // Force refetch
    fetchEntries(0, false, true);
  }, [fetchEntries]);

  // Load more (append next page)
  const loadMore = useCallback(() => {
    if (!loading && hasMore) {
      fetchEntries(offset, true, true);
    }
  }, [loading, hasMore, offset, fetchEntries]);

  // Set action filter (resets pagination)
  const setActionFilter = useCallback((filter: ActionTypeFilter) => {
    setActionFilterState(filter);
    setOffset(0);
    setHasMore(true);
  }, []);

  return { 
    entries, 
    loading, 
    error, 
    refetch, 
    loadMore, 
    hasMore, 
    actionFilter, 
    setActionFilter 
  };
}
