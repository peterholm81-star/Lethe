/**
 * Shared utilities for Insights RPC calls
 * 
 * This module provides:
 * - Argument normalization (text, mode)
 * - Request ID guard for preventing stale response overwrites
 * - Response unwrapping (array vs object)
 * - Standardized args builders for each RPC using InsightsWindow
 */

import type { InsightsWindow, InsightsFilters } from '../contexts/InsightsContext';

// =============================================================================
// DEBUG FLAG
// =============================================================================

/**
 * Enable verbose Insights debug logging (stale response warnings, etc.)
 * Set VITE_INSIGHTS_DEBUG=1 in .env.local and restart dev server to enable.
 */
const INSIGHTS_DEBUG = import.meta.env.VITE_INSIGHTS_DEBUG === '1';

// =============================================================================
// TEXT NORMALIZATION
// =============================================================================

/**
 * Normalize text: trim, null/undefined/empty => null
 */
export function normalizeText(x: string | null | undefined): string | null {
  if (x === null || x === undefined) return null;
  const trimmed = x.trim();
  return trimmed === '' ? null : trimmed;
}

/**
 * Normalize mode: normalizeText + "all" (case-insensitive) => null
 */
export function normalizeMode(x: string | null | undefined): string | null {
  const normalized = normalizeText(x);
  if (normalized === null) return null;
  if (normalized.toLowerCase() === 'all') return null;
  return normalized;
}

// =============================================================================
// REQUEST ID GUARD (prevents stale response overwrites)
// =============================================================================

export interface LatestOnlyGuard {
  /** Get next request ID and increment counter */
  nextRequestId(): number;
  /** Check if given ID is still the latest */
  isLatest(id: number): boolean;
  /** Get current latest ID (for debugging) */
  current(): number;
  /**
   * Log a warning if response is stale (DEV only).
   * Only logs if at least 2 requests have been made (to avoid mount/refresh noise).
   * Returns true if stale, false if latest.
   */
  warnIfStale(id: number, hookName: string): boolean;
}

/**
 * Create a guard that tracks request IDs to prevent stale responses
 * from overwriting state.
 * 
 * Usage:
 *   const guardRef = useRef(createLatestOnlyGuard());
 *   const reqId = guardRef.current.nextRequestId();
 *   // ... await RPC ...
 *   if (guardRef.current.warnIfStale(reqId, 'PULSE')) return; // ignore stale
 */
export function createLatestOnlyGuard(): LatestOnlyGuard {
  let latestId = 0;
  
  return {
    nextRequestId(): number {
      latestId += 1;
      return latestId;
    },
    isLatest(id: number): boolean {
      return id === latestId;
    },
    current(): number {
      return latestId;
    },
    warnIfStale(id: number, hookName: string): boolean {
      const isStale = id !== latestId;
      if (isStale && INSIGHTS_DEBUG && latestId >= 2) {
        // Only log if debug enabled and >= 2 requests sent (avoids mount noise)
        console.warn(`[${hookName}] IGNORED stale response (req #${id})`);
      }
      return isStale;
    },
  };
}

// =============================================================================
// ERROR DETECTION
// =============================================================================

/**
 * Check if error is a "function not found" error from Supabase
 * This happens when the RPC function hasn't been deployed yet.
 */
export function isMissingFunctionError(err: unknown): boolean {
  if (!err) return false;
  const msg = (err as { message?: string })?.message ?? '';
  const code = (err as { code?: string })?.code ?? '';
  
  // Supabase/PostgREST returns these patterns for missing functions:
  // - "Could not find the function ... in the schema cache"
  // - PGRST202 error code
  // - 404 status with function reference
  return (
    msg.includes('Could not find the function') ||
    msg.includes('schema cache') ||
    code === 'PGRST202' ||
    code === '42883' // PostgreSQL "function does not exist"
  );
}

/**
 * Get user-friendly error message based on error type
 */
export function getUserErrorMessage(err: unknown, hookName: string): string {
  if (isMissingFunctionError(err)) {
    if (import.meta.env.DEV) {
      return `Backend not deployed: missing RPC function for ${hookName}`;
    }
    return 'Failed to load metrics';
  }
  
  const supaError = err as { message?: string };
  return supaError?.message ?? 'Failed to load metrics';
}

/**
 * Log error in DEV mode (one concise line per hook)
 */
export function logRpcError(hookName: string, rpcName: string, err: unknown): void {
  if (!import.meta.env.DEV) return;
  
  if (isMissingFunctionError(err)) {
    console.error(`[${hookName}] RPC "${rpcName}" not found - deploy SQL first`);
  } else {
    const msg = (err as { message?: string })?.message ?? 'Unknown error';
    console.error(`[${hookName}] RPC error: ${msg}`);
  }
}

// =============================================================================
// RESPONSE UNWRAPPING
// =============================================================================

/**
 * Unwrap RPC result: array => first element, object => object, null => null
 */
export function unwrapRpcRow<T>(result: unknown): T | null {
  if (result === null || result === undefined) return null;
  if (Array.isArray(result)) return (result[0] as T) ?? null;
  return result as T;
}

// =============================================================================
// WINDOW-BASED ARGS BUILDERS
// =============================================================================

/**
 * Standard lens parameters used by all window-based RPCs
 */
export interface WindowRpcArgs {
  p_start_ts: string;
  p_end_ts: string;
  p_region: string | null;
  p_country_code: string | null;
  p_city_code: string | null;
  p_mode: string | null;
}

/**
 * Build standard window + lens args for any Insights RPC
 * This is the SINGLE SOURCE OF TRUTH for all time-window-based queries.
 */
export function buildWindowArgs(filters: InsightsFilters, window: InsightsWindow): WindowRpcArgs {
  return {
    p_start_ts: window.startUtcIso,
    p_end_ts: window.endUtcIso,
    p_region: normalizeText(filters.region),
    p_country_code: normalizeText(filters.country_code),
    p_city_code: normalizeText(filters.city_code),
    p_mode: normalizeMode(filters.mode),
  };
}

// =============================================================================
// SPECIFIC RPC ARGS BUILDERS (all using window now)
// =============================================================================

/**
 * Build args for get_pulse_metrics_range RPC (new range-based version)
 */
export function buildPulseRangeArgs(filters: InsightsFilters, window: InsightsWindow): WindowRpcArgs {
  return buildWindowArgs(filters, window);
}

/**
 * Build args for get_engagement_flow_range RPC
 */
export function buildEngagementFlowRangeArgs(filters: InsightsFilters, window: InsightsWindow): WindowRpcArgs {
  return buildWindowArgs(filters, window);
}

/**
 * Build args for get_readers_writers_range RPC
 */
export function buildReadersWritersRangeArgs(filters: InsightsFilters, window: InsightsWindow): WindowRpcArgs {
  return buildWindowArgs(filters, window);
}

/**
 * Build args for get_change_over_time_range RPC
 */
export function buildChangeOverTimeRangeArgs(filters: InsightsFilters, window: InsightsWindow): WindowRpcArgs {
  return buildWindowArgs(filters, window);
}

// =============================================================================
// FILTER OPTIONS ARGS BUILDERS (unchanged - not time-based)
// =============================================================================

/**
 * Build args for filter options RPCs
 */
export function buildCountryOptionsArgs(region?: string | null): { p_region: string | null } {
  return { p_region: normalizeText(region) };
}

export function buildCityOptionsArgs(
  countryCode?: string | null,
  region?: string | null
): { p_country_code: string | null; p_region: string | null } {
  return {
    p_country_code: normalizeText(countryCode),
    p_region: normalizeText(region),
  };
}

// =============================================================================
// LEGACY BUILDERS (kept for useInsightsActiveDay bootstrap only)
// =============================================================================

/**
 * @deprecated Use buildWindowArgs for new code
 * Only used by useInsightsActiveDay for initial bootstrap check
 */
export function buildPulseArgsLegacy(date: string): {
  p_date: string;
  p_region: null;
  p_country_code: null;
  p_city_code: null;
  p_mode: null;
} {
  return {
    p_date: date,
    p_region: null,
    p_country_code: null,
    p_city_code: null,
    p_mode: null,
  };
}
