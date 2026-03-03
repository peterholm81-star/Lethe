import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

// =============================================================================
// DEBUG
// =============================================================================

const DEBUG_ADS = typeof localStorage !== 'undefined' && localStorage.getItem('debug_ads') === '1';

function debugLog(...args: unknown[]): void {
  if (DEBUG_ADS || import.meta.env.DEV) {
    console.log('[ad-policy-effective]', ...args);
  }
}

// =============================================================================
// TYPES
// =============================================================================

export type AdPolicyEffectiveRow = {
  country_code: string;
  ads_per_session_cap: number;
  trigger_pages: number;
  enabled: boolean;
  source: 'override' | 'default';
  updated_at: string;
};

export interface UseAdPolicyEffectiveResult {
  data: AdPolicyEffectiveRow[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// =============================================================================
// HOOK
// =============================================================================

/**
 * Fetch effective ad policy from Supabase view.
 * 
 * @param countryCodes - Optional list of country codes to filter by
 * @returns Policy data with loading/error states
 * 
 * @example
 * // Fetch all
 * const { data } = useAdPolicyEffective();
 * 
 * // Fetch specific countries
 * const { data } = useAdPolicyEffective(['US', 'NO', 'DE']);
 */
export function useAdPolicyEffective(
  countryCodes?: string[]
): UseAdPolicyEffectiveResult {
  const [data, setData] = useState<AdPolicyEffectiveRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const fetchCount = useRef(0);

  // Stable key for dependency tracking
  const countryCodesKey = countryCodes?.sort().join(',') ?? '';

  const fetchData = useCallback(async () => {
    fetchCount.current += 1;
    const fetchId = fetchCount.current;
    
    debugLog(`[fetch #${fetchId}] Starting fetch`, {
      countryCodes: countryCodes ?? 'ALL',
      countryCodesKey,
      supabaseUrl: (supabase as { supabaseUrl?: string }).supabaseUrl ?? 'unknown',
    });

    setLoading(true);
    setError(null);

    try {
      let query = supabase
        .from('ad_policy_effective')
        .select('*');

      // Filter by country codes if provided
      if (countryCodes && countryCodes.length > 0) {
        query = query.in('country_code', countryCodes);
      }

      debugLog(`[fetch #${fetchId}] Executing query: ad_policy_effective`, {
        filter: countryCodes ? `IN (${countryCodes.join(', ')})` : 'none',
      });

      const { data: rows, error: queryError } = await query;

      if (queryError) {
        debugLog(`[fetch #${fetchId}] Query error:`, queryError);
        throw queryError;
      }

      debugLog(`[fetch #${fetchId}] Success:`, {
        rowCount: rows?.length ?? 0,
        rows: rows?.slice(0, 3), // Log first 3 rows
      });

      setData((rows || []) as AdPolicyEffectiveRow[]);
      setLoading(false);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load policy data';
      
      debugLog(`[fetch #${fetchId}] Error:`, message);

      // Handle missing view gracefully
      if (message.includes('does not exist') || message.includes('relation')) {
        console.warn('[useAdPolicyEffective] View not found — returning empty');
        setData([]);
        setError(null);
      } else {
        console.error('[useAdPolicyEffective] Error:', err);
        setError(message);
      }
      
      setLoading(false);
    }
  }, [countryCodesKey, countryCodes]);

  useEffect(() => {
    debugLog('Hook mounted/updated, triggering fetch', { countryCodesKey });
    fetchData();
  }, [fetchData]);

  return {
    data,
    loading,
    error,
    refetch: fetchData,
  };
}
