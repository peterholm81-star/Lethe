import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import {
  createLatestOnlyGuard,
  isMissingFunctionError,
  normalizeText,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';

// =============================================================================
// CONSTANTS
// =============================================================================

const HOOK_NAME = 'REVENUE_GEO';
const RPC_NAME = 'get_revenue_by_country_range';

// =============================================================================
// TYPES
// =============================================================================

/**
 * Raw row returned by the RPC.
 * Note: Supabase may return numeric fields as strings, so we normalize them.
 */
export interface RevenueGeoRowRaw {
  country_code: string;
  sessions: string | number;
  ad_impressions: string | number;
  revenue_total: string | number;
  ad_revenue: string | number;
  premium_revenue: string | number;
  revenue_per_session: string | number;
}

/**
 * Normalized row with all numeric fields as JS numbers.
 */
export interface RevenueGeoRow {
  countryCode: string;         // Uppercase country code (e.g., 'NO', 'US')
  sessions: number;            // Total distinct sessions
  adImpressions: number;       // Count of ad_shown events
  revenueTotal: number;        // Total revenue (ad + premium)
  adRevenue: number;           // Revenue from ads
  premiumRevenue: number;      // Revenue from premium (placeholder: 0)
  revenuePerSession: number;   // revenue_total / sessions
}

/**
 * Parameters for the useRevenueGeo hook.
 */
export interface RevenueGeoParams {
  /** Number of days to look back from 'end' (default: 30) */
  timeRangeDays?: number;
  /** Override start date (if provided, ignores timeRangeDays) */
  start?: Date;
  /** Override end date (default: now) */
  end?: Date;
  /** Filter by region (null or 'all' = all regions) */
  region?: string | null;
  /** Enable/disable the query (default: true) */
  enabled?: boolean;
  /** Also fetch the previous period for comparison (default: false) */
  compareToPrevious?: boolean;
}

/**
 * Aggregated totals across all countries.
 */
export interface RevenueGeoTotals {
  sessions: number;
  adImpressions: number;
  revenueTotal: number;
  adRevenue: number;
  premiumRevenue: number;
}

/**
 * Map-ready data format (simplified for visualization).
 */
export interface RevenueGeoMapItem {
  countryCode: string;
  sessions: number;
  adImpressions: number;
  revenueTotal: number;
  revenuePerSession: number;
}

/**
 * Previous period data (when compareToPrevious is enabled).
 */
export interface RevenueGeoPreviousPeriod {
  mapData: RevenueGeoMapItem[];
  totals: RevenueGeoTotals;
  topCountries: RevenueGeoRow[];
}

/**
 * Hook return type.
 */
export interface UseRevenueGeoResult {
  /** All rows, normalized and sorted by sessions DESC */
  data: RevenueGeoRow[];
  /** Top 10 countries by revenue (falls back to sessions if revenue is 0) */
  topCountries: RevenueGeoRow[];
  /** Aggregated totals across all countries */
  totals: RevenueGeoTotals;
  /** Map-ready data array */
  mapData: RevenueGeoMapItem[];
  /** Previous period data (null if compareToPrevious is false) */
  previous: RevenueGeoPreviousPeriod | null;
  /** Loading state */
  loading: boolean;
  /** Error message (null if no error) */
  error: string | null;
  /** Manually refetch data */
  refetch: () => void;
}

// =============================================================================
// HELPERS
// =============================================================================

/**
 * Safely parse a value to a number.
 * Handles strings, numbers, null, undefined.
 */
function toNumber(value: unknown): number {
  if (value === null || value === undefined) return 0;
  if (typeof value === 'number') return isNaN(value) ? 0 : value;
  if (typeof value === 'string') {
    const parsed = parseFloat(value);
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

/**
 * Normalize a raw RPC row to typed RevenueGeoRow.
 * Converts all numeric fields and uppercases country code.
 */
function normalizeRow(raw: RevenueGeoRowRaw): RevenueGeoRow {
  const countryCode = (raw.country_code ?? '').toUpperCase().trim();
  
  return {
    countryCode,
    sessions: Math.round(toNumber(raw.sessions)),
    adImpressions: Math.round(toNumber(raw.ad_impressions)),
    revenueTotal: toNumber(raw.revenue_total),
    adRevenue: toNumber(raw.ad_revenue),
    premiumRevenue: toNumber(raw.premium_revenue),
    revenuePerSession: toNumber(raw.revenue_per_session),
  };
}

/**
 * Convert Date to ISO string for Supabase timestamptz.
 */
function toIsoString(date: Date): string {
  return date.toISOString();
}

/**
 * Calculate start date from end date and days.
 */
function getStartDate(end: Date, days: number): Date {
  const start = new Date(end);
  start.setDate(start.getDate() - days);
  return start;
}

// =============================================================================
// HOOK
// =============================================================================

/**
 * Fetch geo revenue metrics from the database.
 * Powers the Monetization "Revenue Map" feature.
 * 
 * @example
 * // Basic usage with defaults (last 30 days, all regions)
 * const { data, topCountries, totals, mapData, loading, error } = useRevenueGeo({});
 * 
 * @example
 * // With custom params
 * const { data, loading } = useRevenueGeo({
 *   timeRangeDays: 7,
 *   region: 'Europe',
 * });
 * 
 * @example
 * // With explicit date range
 * const { data, loading } = useRevenueGeo({
 *   start: new Date('2026-01-01'),
 *   end: new Date('2026-01-31'),
 *   region: null,
 * });
 */
export function useRevenueGeo(params: RevenueGeoParams = {}): UseRevenueGeoResult {
  const {
    timeRangeDays = 30,
    start: startOverride,
    end: endOverride,
    region = null,
    enabled = true,
    compareToPrevious = false,
  } = params;

  // State - current period
  const [data, setData] = useState<RevenueGeoRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // State - previous period (for comparison)
  const [previousData, setPreviousData] = useState<RevenueGeoRow[]>([]);

  // Guard to prevent stale responses from overwriting state
  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  // Calculate date ranges (current and previous)
  // Memoize to prevent unnecessary refetches
  const { startIso, endIso, prevStartIso, prevEndIso } = useMemo(() => {
    const endDate = endOverride ?? new Date();
    const startDate = startOverride ?? getStartDate(endDate, timeRangeDays);
    
    // Calculate duration in milliseconds for previous period
    const duration = endDate.getTime() - startDate.getTime();
    
    // Previous period: [start - duration, start)
    const prevEnd = new Date(startDate.getTime());
    const prevStart = new Date(startDate.getTime() - duration);
    
    return {
      startIso: toIsoString(startDate),
      endIso: toIsoString(endDate),
      prevStartIso: toIsoString(prevStart),
      prevEndIso: toIsoString(prevEnd),
    };
  }, [
    startOverride?.getTime(),
    endOverride?.getTime(),
    timeRangeDays,
  ]);

  // Normalize region parameter
  const normalizedRegion = useMemo(() => normalizeText(region), [region]);

  // ==========================================================================
  // FETCH FUNCTION
  // ==========================================================================

  const fetchData = useCallback(async () => {
    // Skip if disabled
    if (!enabled) {
      setData([]);
      setPreviousData([]);
      setLoading(false);
      setError(null);
      return;
    }

    // Get unique request ID to detect stale responses
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    try {
      // Fetch current period
      const currentPromise = supabase.rpc(RPC_NAME, {
        p_start: startIso,
        p_end: endIso,
        p_region: normalizedRegion,
      });

      // Fetch previous period (only if compareToPrevious is enabled)
      const previousPromise = compareToPrevious
        ? supabase.rpc(RPC_NAME, {
            p_start: prevStartIso,
            p_end: prevEndIso,
            p_region: normalizedRegion,
          })
        : Promise.resolve({ data: null, error: null });

      // Wait for both fetches
      const [currentResult, previousResult] = await Promise.all([
        currentPromise,
        previousPromise,
      ]);

      // Check if this response is stale (newer request was made)
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return; // Ignore stale response
      }

      // Handle RPC error
      if (currentResult.error) throw currentResult.error;

      // Normalize current rows
      const rawRows = (currentResult.data as RevenueGeoRowRaw[]) || [];
      const normalizedRows = rawRows
        .map(normalizeRow)
        .filter(row => row.countryCode !== '');

      // Normalize previous rows (if available)
      let prevNormalizedRows: RevenueGeoRow[] = [];
      if (compareToPrevious && previousResult.data && !previousResult.error) {
        prevNormalizedRows = (previousResult.data as RevenueGeoRowRaw[])
          .map(normalizeRow)
          .filter(row => row.countryCode !== '');
      }

      setData(normalizedRows);
      setPreviousData(prevNormalizedRows);
      setLoading(false);

    } catch (err: unknown) {
      // Check if stale before handling error
      if (guardRef.current.warnIfStale(reqId, HOOK_NAME)) {
        return;
      }

      // Handle missing function gracefully (RPC not deployed yet)
      if (isMissingFunctionError(err)) {
        if (import.meta.env.DEV) {
          console.warn(`[${HOOK_NAME}] RPC "${RPC_NAME}" not found - showing empty state`);
        }
        setData([]);
        setPreviousData([]);
        setError(null);
        setLoading(false);
        return;
      }

      // Handle other errors
      const message = err instanceof Error ? err.message : 'Failed to load revenue geo data';
      if (import.meta.env.DEV) {
        console.error(`[${HOOK_NAME}] Error:`, err);
      }
      setError(message);
      setData([]);
      setPreviousData([]);
      setLoading(false);
    }
  }, [startIso, endIso, prevStartIso, prevEndIso, normalizedRegion, enabled, compareToPrevious]);

  // ==========================================================================
  // EFFECT: Fetch on mount and when params change
  // ==========================================================================

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  // ==========================================================================
  // DERIVED DATA
  // ==========================================================================

  /**
   * Top 10 countries by revenue.
   * Falls back to sorting by sessions if revenue is 0 across all rows.
   */
  const topCountries = useMemo(() => {
    if (data.length === 0) return [];

    // Check if any row has revenue > 0
    const hasRevenue = data.some(row => row.revenueTotal > 0);

    // Sort by revenue or sessions
    const sorted = [...data].sort((a, b) => {
      if (hasRevenue) {
        return b.revenueTotal - a.revenueTotal;
      }
      return b.sessions - a.sessions;
    });

    return sorted.slice(0, 10);
  }, [data]);

  /**
   * Aggregated totals across all countries.
   */
  const totals = useMemo((): RevenueGeoTotals => {
    return data.reduce(
      (acc, row) => ({
        sessions: acc.sessions + row.sessions,
        adImpressions: acc.adImpressions + row.adImpressions,
        revenueTotal: acc.revenueTotal + row.revenueTotal,
        adRevenue: acc.adRevenue + row.adRevenue,
        premiumRevenue: acc.premiumRevenue + row.premiumRevenue,
      }),
      {
        sessions: 0,
        adImpressions: 0,
        revenueTotal: 0,
        adRevenue: 0,
        premiumRevenue: 0,
      }
    );
  }, [data]);

  /**
   * Map-ready data format (simplified for visualization).
   * Sorted by sessions DESC.
   */
  const mapData = useMemo((): RevenueGeoMapItem[] => {
    return data.map(row => ({
      countryCode: row.countryCode,
      sessions: row.sessions,
      adImpressions: row.adImpressions,
      revenueTotal: row.revenueTotal,
      revenuePerSession: row.revenuePerSession,
    }));
  }, [data]);

  // ==========================================================================
  // PREVIOUS PERIOD DERIVED DATA
  // ==========================================================================

  /**
   * Previous period: top countries
   */
  const previousTopCountries = useMemo(() => {
    if (previousData.length === 0) return [];
    const hasRevenue = previousData.some(row => row.revenueTotal > 0);
    const sorted = [...previousData].sort((a, b) => {
      if (hasRevenue) return b.revenueTotal - a.revenueTotal;
      return b.sessions - a.sessions;
    });
    return sorted.slice(0, 10);
  }, [previousData]);

  /**
   * Previous period: totals
   */
  const previousTotals = useMemo((): RevenueGeoTotals => {
    return previousData.reduce(
      (acc, row) => ({
        sessions: acc.sessions + row.sessions,
        adImpressions: acc.adImpressions + row.adImpressions,
        revenueTotal: acc.revenueTotal + row.revenueTotal,
        adRevenue: acc.adRevenue + row.adRevenue,
        premiumRevenue: acc.premiumRevenue + row.premiumRevenue,
      }),
      { sessions: 0, adImpressions: 0, revenueTotal: 0, adRevenue: 0, premiumRevenue: 0 }
    );
  }, [previousData]);

  /**
   * Previous period: map data
   */
  const previousMapData = useMemo((): RevenueGeoMapItem[] => {
    return previousData.map(row => ({
      countryCode: row.countryCode,
      sessions: row.sessions,
      adImpressions: row.adImpressions,
      revenueTotal: row.revenueTotal,
      revenuePerSession: row.revenuePerSession,
    }));
  }, [previousData]);

  /**
   * Packaged previous period data (null if comparison not enabled)
   */
  const previous = useMemo((): RevenueGeoPreviousPeriod | null => {
    if (!compareToPrevious) return null;
    return {
      mapData: previousMapData,
      totals: previousTotals,
      topCountries: previousTopCountries,
    };
  }, [compareToPrevious, previousMapData, previousTotals, previousTopCountries]);

  // ==========================================================================
  // RETURN
  // ==========================================================================

  return {
    data,
    topCountries,
    totals,
    mapData,
    previous,
    loading,
    error,
    refetch: fetchData,
  };
}
