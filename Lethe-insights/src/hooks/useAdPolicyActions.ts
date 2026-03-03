import { useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';

// =============================================================================
// DEBUG
// =============================================================================

const DEBUG_ADS = typeof localStorage !== 'undefined' && localStorage.getItem('debug_ads') === '1';

function debugLog(...args: unknown[]): void {
  if (DEBUG_ADS || import.meta.env.DEV) {
    console.log('[ad-policy-actions]', ...args);
  }
}

// =============================================================================
// TYPES
// =============================================================================

export interface CountryPolicyPatch {
  ads_per_session_cap?: number;
  trigger_pages?: number;
  enabled?: boolean;
}

export interface CountryPolicyFull {
  ads_per_session_cap: number;
  trigger_pages: number;
  enabled: boolean;
}

export interface UseAdPolicyActionsResult {
  upsertCountryPolicy: (countryCode: string, patch: CountryPolicyPatch) => Promise<boolean>;
  upsertCountryPolicyFull: (countryCode: string, policy: CountryPolicyFull) => Promise<boolean>;
  deleteCountryPolicy: (countryCode: string) => Promise<boolean>;
  loading: boolean;
  error: string | null;
  clearError: () => void;
}

// =============================================================================
// HOOK
// =============================================================================

/**
 * Provides actions to modify ad policy.
 * 
 * @example
 * const { upsertCountryPolicy, deleteCountryPolicy, loading, error } = useAdPolicyActions();
 * 
 * // Partial update
 * await upsertCountryPolicy('US', { ads_per_session_cap: 2 });
 * 
 * // Full update
 * await upsertCountryPolicyFull('US', { ads_per_session_cap: 3, trigger_pages: 4, enabled: true });
 * 
 * // Reset to default
 * await deleteCountryPolicy('US');
 */
export function useAdPolicyActions(): UseAdPolicyActionsResult {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const clearError = useCallback(() => {
    setError(null);
  }, []);

  /**
   * Upsert a country policy override (partial - only specified fields).
   */
  const upsertCountryPolicy = useCallback(async (
    countryCode: string,
    patch: CountryPolicyPatch
  ): Promise<boolean> => {
    setLoading(true);
    setError(null);

    const payload = {
      country_code: countryCode,
      ...patch,
    };

    debugLog('UPSERT (partial) starting:', payload);

    try {
      const { error: upsertError } = await supabase
        .from('ad_policy_country')
        .upsert(payload, { 
          onConflict: 'country_code',
        });

      if (upsertError) {
        debugLog('UPSERT failed:', upsertError);
        setError(upsertError.message);
        setLoading(false);
        return false;
      }

      debugLog('UPSERT success:', countryCode, patch);
      setLoading(false);
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to update policy';
      debugLog('UPSERT exception:', message);
      setError(message);
      setLoading(false);
      return false;
    }
  }, []);

  /**
   * Upsert a country policy override (full - all three fields).
   */
  const upsertCountryPolicyFull = useCallback(async (
    countryCode: string,
    policy: CountryPolicyFull
  ): Promise<boolean> => {
    setLoading(true);
    setError(null);

    const payload = {
      country_code: countryCode,
      ads_per_session_cap: policy.ads_per_session_cap,
      trigger_pages: policy.trigger_pages,
      enabled: policy.enabled,
    };

    debugLog('UPSERT (full) starting:', payload);

    try {
      const { error: upsertError } = await supabase
        .from('ad_policy_country')
        .upsert(payload, { 
          onConflict: 'country_code',
        });

      if (upsertError) {
        debugLog('UPSERT (full) failed:', upsertError);
        setError(upsertError.message);
        setLoading(false);
        return false;
      }

      debugLog('UPSERT (full) success:', countryCode, policy);
      setLoading(false);
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to save policy';
      debugLog('UPSERT (full) exception:', message);
      setError(message);
      setLoading(false);
      return false;
    }
  }, []);

  /**
   * Delete a country policy override (resets to default).
   */
  const deleteCountryPolicy = useCallback(async (
    countryCode: string
  ): Promise<boolean> => {
    setLoading(true);
    setError(null);

    debugLog('DELETE starting:', countryCode);

    try {
      const { error: deleteError } = await supabase
        .from('ad_policy_country')
        .delete()
        .eq('country_code', countryCode);

      if (deleteError) {
        debugLog('DELETE failed:', deleteError);
        setError(deleteError.message);
        setLoading(false);
        return false;
      }

      debugLog('DELETE success - reset to default:', countryCode);
      setLoading(false);
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to reset policy';
      debugLog('DELETE exception:', message);
      setError(message);
      setLoading(false);
      return false;
    }
  }, []);

  return {
    upsertCountryPolicy,
    upsertCountryPolicyFull,
    deleteCountryPolicy,
    loading,
    error,
    clearError,
  };
}
