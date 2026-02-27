import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import {
  buildWindowArgs,
  createLatestOnlyGuard,
  isMissingFunctionError,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';
import type { InsightsFilters, InsightsWindow } from '../contexts/InsightsContext';

const HOOK_NAME = 'TOP_EARNING_COUNTRIES';
const RPC_NAME = 'get_sessions_by_country_range';

// =============================================================================
// TYPES
// =============================================================================

export interface CountrySessionRow {
  country_code: string;
  sessions: number;
}

export interface CountryRevenueData {
  country_code: string;
  sessions: number;
  impressions: number;
  estimated_ad_revenue: number;
  revenue_per_session: number;
}

export interface RevenueAssumptions {
  ecpm: number;
  fillRate: number;
  adsPerSessionCap: number;
  triggerShare: number;
}

export interface UseTopEarningCountriesResult {
  data: CountryRevenueData[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// =============================================================================
// HELPERS
// =============================================================================

function computeCountryRevenue(
  row: CountrySessionRow,
  assumptions: RevenueAssumptions
): CountryRevenueData {
  const { ecpm, fillRate, adsPerSessionCap, triggerShare } = assumptions;
  
  // Compute impressions proxy: sessions * adsPerSessionCap * triggerShare
  const impressions = row.sessions * adsPerSessionCap * triggerShare;
  
  // Compute estimated revenue: (impressions * eCPM / 1000) * fillRate
  const estimated_ad_revenue = (impressions * ecpm / 1000) * fillRate;
  
  // Revenue per session
  const revenue_per_session = row.sessions > 0 
    ? estimated_ad_revenue / row.sessions 
    : 0;
  
  return {
    country_code: row.country_code,
    sessions: row.sessions,
    impressions: Math.round(impressions),
    estimated_ad_revenue,
    revenue_per_session,
  };
}

// =============================================================================
// HOOK
// =============================================================================

/**
 * Fetch sessions by country and compute estimated ad revenue
 * based on Revenue Lab assumptions.
 */
export function useTopEarningCountries(
  filters: InsightsFilters,
  window: InsightsWindow,
  assumptions: RevenueAssumptions
): UseTopEarningCountriesResult {
  const [rawData, setRawData] = useState<CountrySessionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchData = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    const args = buildWindowArgs(filters, window);

    try {
      const { data: result, error: rpcError } = await supabase.rpc(RPC_NAME, args);

      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      if (rpcError) throw rpcError;

      const rows = (result as CountrySessionRow[]) || [];
      setRawData(rows);
      setLoading(false);

    } catch (err: unknown) {
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      // Handle missing function gracefully
      if (isMissingFunctionError(err)) {
        if (import.meta.env.DEV) {
          console.warn(`[${HOOK_NAME}] RPC "${RPC_NAME}" not found - showing empty state`);
        }
        setRawData([]);
        setError(null);
        setLoading(false);
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to load country data';
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Error:`, err);
      }
      setError(message);
      setRawData([]);
      setLoading(false);
    }
  }, [
    window.startUtcIso,
    window.endUtcIso,
    filters.region,
    filters.country_code,
    filters.city_code,
    filters.mode,
  ]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  // Compute revenue data from raw sessions + assumptions
  const data = useMemo(() => {
    return rawData
      .map(row => computeCountryRevenue(row, assumptions))
      .sort((a, b) => b.estimated_ad_revenue - a.estimated_ad_revenue);
  }, [rawData, assumptions]);

  return { data, loading, error, refetch: fetchData };
}
