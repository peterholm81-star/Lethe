import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_PENDING';

// =============================================================================
// TYPES
// =============================================================================

export interface PendingReportRow {
  report_id: string;
  confession_id: string;
  reason: string;
  created_at: string;
  region: string | null;
  country_code: string | null;
  city_code: string | null;
  hours_open: number;
}

export interface UseReportsPendingResult {
  rows: PendingReportRow[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
  loadMore: () => void;
  hasMore: boolean;
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
// HOOK: useReportsPending
// =============================================================================

export function useReportsPending(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null,
  city: string | null = null,
  limit: number = 25
): UseReportsPendingResult {
  const [rows, setRows] = useState<PendingReportRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchPending = useCallback(async (
    currentOffset: number = 0, 
    append: boolean = false,
    force: boolean = false
  ) => {
    // Build key for deduplication (only for initial fetch, not pagination)
    const key = `${timeRange}|${region}|${country}|${city}|${currentOffset}`;
    
    // Skip if same params and not forced (and not appending)
    if (!force && !append && key === lastKeyRef.current && rows.length > 0) {
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
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_reports_pending_v1', {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country: country || null,
        p_city: city || null,
        p_limit: limit,
        p_offset: currentOffset,
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        // Handle auth error gracefully
        if (rpcError.message?.includes('authentication required') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          if (!append) setRows([]);
        } else {
          setError(rpcError.message || 'Failed to load pending reports');
          if (!append) setRows([]);
        }
        setHasMore(false);
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      const newRows = Array.isArray(rpcData) ? rpcData as PendingReportRow[] : [];
      
      if (append) {
        setRows(prev => [...prev, ...newRows]);
      } else {
        setRows(newRows);
      }
      
      // If we got fewer rows than limit, there's no more data
      setHasMore(newRows.length === limit);
      setOffset(currentOffset + newRows.length);
      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load pending reports';
      setError(message);
      if (!append) setRows([]);
      setHasMore(false);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, city, limit, rows.length]);

  // Fetch on mount and filter change (reset to first page)
  useEffect(() => {
    setOffset(0);
    setHasMore(true);
    lastKeyRef.current = ''; // Force refetch on filter change
    fetchPending(0, false, true);
  }, [timeRange, region, country, city]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch (reset to first page)
  const refetch = useCallback(() => {
    setOffset(0);
    setHasMore(true);
    lastKeyRef.current = ''; // Force refetch
    fetchPending(0, false, true);
  }, [fetchPending]);

  // Load more (append next page)
  const loadMore = useCallback(() => {
    if (!loading && hasMore) {
      fetchPending(offset, true, true);
    }
  }, [loading, hasMore, offset, fetchPending]);

  return { rows, loading, error, refetch, loadMore, hasMore };
}
