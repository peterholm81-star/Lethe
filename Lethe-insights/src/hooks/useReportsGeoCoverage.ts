import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

const HOOK_NAME = 'REPORTS_GEO_COVERAGE';

// =============================================================================
// TYPES (v2 - honest coverage with backfillable/ungeocodable split)
// =============================================================================

export interface GeoCoverageData {
  // Totals
  totalReports: number;
  backfillableReports: number;
  ungeocodableReports: number;
  
  // Coverage counts (within backfillable only)
  regionCovered: number;
  cityCovered: number;
  countryCovered: number;
  
  // Coverage percentages (based on backfillable, not total)
  regionPct: number;
  cityPct: number;
  countryPct: number;
}

export interface UseReportsGeoCoverageResult {
  coverage: GeoCoverageData | null;
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
// HOOK: useReportsGeoCoverage (v2)
// =============================================================================

export function useReportsGeoCoverage(
  timeRange: string = '7d',
  region: string | null = null,
  country: string | null = null,
  city: string | null = null
): UseReportsGeoCoverageResult {
  const [coverage, setCoverage] = useState<GeoCoverageData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Guards to prevent request storms
  const inFlightRef = useRef(false);
  const lastKeyRef = useRef<string>('');

  const fetchCoverage = useCallback(async (force: boolean = false) => {
    // Build key for deduplication
    const key = `${timeRange}|${region}|${country}|${city}`;
    
    // Skip if same params and not forced
    if (!force && key === lastKeyRef.current && coverage !== null && !loading) {
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
      // Use v2 RPC with honest backfillable/ungeocodable split
      const rpcParams = {
        p_days: rangeToDays(timeRange),
        p_region: region || null,
        p_country_code: country || null,
        p_city_code: city || null,
      };
      
      // DEBUG: Only log in dev mode
      if (import.meta.env.DEV) {
        console.log('[GEO_COVERAGE] RPC call:', rpcParams);
      }
      
      const { data: rpcData, error: rpcError } = await supabase.rpc('get_reports_geo_coverage_v2', rpcParams);

      if (rpcError) {
        if (import.meta.env.DEV) {
          console.error(`[${HOOK_NAME}] RPC error:`, rpcError);
        }
        // Handle auth error gracefully
        if (rpcError.message?.includes('admin only') || 
            rpcError.message?.includes('Access denied')) {
          setError(null);
          setCoverage(null);
        } else {
          setError(rpcError.message || 'Failed to load geo coverage');
          setCoverage(null);
        }
        setLoading(false);
        inFlightRef.current = false;
        return;
      }

      // Extract first row
      const row = Array.isArray(rpcData) && rpcData.length > 0 ? rpcData[0] : null;
      
      if (row) {
        setCoverage({
          totalReports: row.total_reports ?? 0,
          backfillableReports: row.backfillable_reports ?? 0,
          ungeocodableReports: row.ungeocodable_reports ?? 0,
          regionCovered: row.region_covered ?? 0,
          cityCovered: row.city_covered ?? 0,
          countryCovered: row.country_covered ?? 0,
          regionPct: row.region_pct ?? 0,
          cityPct: row.city_pct ?? 0,
          countryPct: row.country_pct ?? 0,
        });
      } else {
        setCoverage(null);
      }
      
      setError(null);
      setLoading(false);
      inFlightRef.current = false;

    } catch (err: unknown) {
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Fetch error:`, err);
      }
      const message = err instanceof Error ? err.message : 'Failed to load geo coverage';
      setError(message);
      setCoverage(null);
      setLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, country, city, coverage, loading]);

  // Fetch on mount and filter change
  useEffect(() => {
    lastKeyRef.current = ''; // Force refetch on filter change
    fetchCoverage(true);
  }, [timeRange, region, country, city]); // eslint-disable-line react-hooks/exhaustive-deps

  // Manual refetch
  const refetch = useCallback(() => {
    lastKeyRef.current = ''; // Force refetch
    fetchCoverage(true);
  }, [fetchCoverage]);

  return { coverage, loading, error, refetch };
}
