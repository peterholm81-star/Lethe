import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_HOTSPOTS';

// =============================================================================
// TYPES
// =============================================================================

export interface HotspotCity {
  city_code: string;
  city_label: string;
  region: string | null;
  country: string | null;
  reports_count: number;
  reads_count: number | null;
  reports_per_1k: number | null;
  top_reason: string | null;
  top_reason_count: number | null;
  // Data quality coverage (same for all rows)
  total_reports_count: number;
  unknown_reports_count: number;
  unknown_reports_pct: number;
  total_reads_count: number;
  unknown_reads_count: number;
  unknown_reads_pct: number;
}

export interface DataQualityCoverage {
  totalReports: number;
  unknownReports: number;
  unknownReportsPct: number;
  totalReads: number;
  unknownReads: number;
  unknownReadsPct: number;
}

export interface UseReportsHotspotsResult {
  hotspots: HotspotCity[];
  coverage: DataQualityCoverage | null;
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
// HOOK: useReportsHotspots
// =============================================================================

export function useReportsHotspots(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null
): UseReportsHotspotsResult {
  const [hotspots, setHotspots] = useState<HotspotCity[]>([]);
  const [coverage, setCoverage] = useState<DataQualityCoverage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchHotspots = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${country}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && hotspots.length >= 0 && !loading) {
      return;
    }

    // Skip if already in-flight
    if (inFlightRef.current && !force) {
      return;
    }

    inFlightRef.current = true;
    lastKeyRef.current = key;
    setLoading(true);
    setError(null);

    try {
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_reports_hotspots_v1', {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country: country || null,
      });

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        // Handle auth error gracefully
        if (rpcError.message?.includes('admin only') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          setHotspots([]);
        } else {
          setError(rpcError.message || 'Failed to load hotspots');
          setHotspots([]);
        }
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      const rows = Array.isArray(rpcData) ? rpcData as HotspotCity[] : [];
      setHotspots(rows);
      
      // Extract data quality coverage from first row (same for all rows)
      if (rows.length > 0) {
        const first = rows[0];
        setCoverage({
          totalReports: first.total_reports_count ?? 0,
          unknownReports: first.unknown_reports_count ?? 0,
          unknownReportsPct: first.unknown_reports_pct ?? 0,
          totalReads: first.total_reads_count ?? 0,
          unknownReads: first.unknown_reads_count ?? 0,
          unknownReadsPct: first.unknown_reads_pct ?? 0,
        });
      } else {
        // No rows - coverage might still exist, but we can't know without data
        setCoverage(null);
      }
      
      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load hotspots';
      setError(message);
      setHotspots([]);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, hotspots.length, loading]);

  // Fetch on mount and filter change
  useEffect(() => {
    lastKeyRef.current = ''; // Force refetch on filter change
    fetchHotspots(true);
  }, [timeRange, region, country]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchHotspots(true);
  }, [fetchHotspots]);

  return { hotspots, coverage, loading, error, refetch };
}
