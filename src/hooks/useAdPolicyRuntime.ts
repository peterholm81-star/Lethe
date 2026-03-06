/**
 * useAdPolicyRuntime - Fetch and cache ad policy for runtime use
 * 
 * Fetches from ad_policy_effective view based on resolved country code.
 * Caches in sessionStorage with 10-minute TTL.
 * Falls back to hardcoded defaults if fetch fails.
 * 
 * Privacy: No user identity. Country code resolved locally.
 */

import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../supabase'
import { resolveCountryCode } from '../utils/resolveCountryCode'

// =============================================================================
// TYPES
// =============================================================================

export interface AdPolicy {
  adsPerSessionCap: number
  triggerPages: number
  enabled: boolean
  source?: string
}

export interface UseAdPolicyRuntimeResult {
  policy: AdPolicy
  loading: boolean
  error: string | null
  countryCode: string
  refetch: () => void
}

interface CachedPolicy {
  country_code: string
  ads_per_session_cap: number
  trigger_pages: number
  enabled: boolean
  source?: string
  fetched_at: number
}

// =============================================================================
// CONSTANTS
// =============================================================================

const CACHE_KEY_PREFIX = 'lethe.ad_policy_effective.v1:'
const CACHE_TTL_MS = 10 * 60 * 1000 // 10 minutes

// Hardcoded defaults (fallback if everything fails)
const DEFAULT_POLICY: AdPolicy = {
  adsPerSessionCap: 1,
  triggerPages: 6,
  enabled: true,
  source: 'hardcoded',
}

// DEV override policy - permissive settings for easy testing
const DEV_OVERRIDE_POLICY: AdPolicy = {
  adsPerSessionCap: 10,
  triggerPages: 1,
  enabled: true,
  source: 'dev_override',
}

// Detect development mode
const IS_DEV = typeof window !== 'undefined' && (
  window.location.hostname === 'localhost' ||
  window.location.hostname === '127.0.0.1' ||
  import.meta.env.DEV === true
)

// Debug flag (enable via localStorage.setItem('debug_ads', '1'))
const DEBUG_ADS = typeof localStorage !== 'undefined' && localStorage.getItem('debug_ads') === '1'

function debugLog(...args: unknown[]): void {
  // Always log in DEV or if debug_ads is enabled
  if (import.meta.env.DEV || DEBUG_ADS) {
    console.log('[ad-policy-runtime]', ...args)
  }
}

// Log DEV override status once at startup
if (IS_DEV) {
  console.log('[ad-policy-runtime] DEV override active - using permissive policy for testing', DEV_OVERRIDE_POLICY)
}

// =============================================================================
// CACHE HELPERS
// =============================================================================

function getCacheKey(countryCode: string): string {
  return `${CACHE_KEY_PREFIX}${countryCode}`
}

function getCachedPolicy(countryCode: string): CachedPolicy | null {
  try {
    const key = getCacheKey(countryCode)
    const raw = sessionStorage.getItem(key)
    if (!raw) return null

    const cached: CachedPolicy = JSON.parse(raw)
    const age = Date.now() - cached.fetched_at

    if (age < CACHE_TTL_MS) {
      debugLog('Using cached policy', { countryCode, age: Math.round(age / 1000) + 's' })
      return cached
    }

    debugLog('Cache expired', { countryCode, age: Math.round(age / 1000) + 's' })
    return null
  } catch {
    return null
  }
}

function setCachedPolicy(policy: CachedPolicy): void {
  try {
    const key = getCacheKey(policy.country_code)
    sessionStorage.setItem(key, JSON.stringify(policy))
  } catch {
    // sessionStorage unavailable
  }
}

// =============================================================================
// HOOK
// =============================================================================

export function useAdPolicyRuntime(): UseAdPolicyRuntimeResult {
  const [policy, setPolicy] = useState<AdPolicy>(DEFAULT_POLICY)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [countryCode, setCountryCode] = useState<string>('ZZ')

  // Prevent duplicate fetches
  const fetchingRef = useRef(false)

  const fetchPolicy = useCallback(async () => {
    if (fetchingRef.current) {
      debugLog('Fetch already in progress, skipping')
      return
    }
    fetchingRef.current = true

    setLoading(true)
    setError(null)

    // Resolve country code
    const resolvedCode = resolveCountryCode()
    setCountryCode(resolvedCode)

    debugLog('Resolving policy for country:', resolvedCode)

    // Check cache first
    const cached = getCachedPolicy(resolvedCode)
    if (cached) {
      debugLog('CACHE HIT - using cached policy (no network request)', {
        country: resolvedCode,
        policy: cached,
        cacheAge: Math.round((Date.now() - cached.fetched_at) / 1000) + 's',
      })
      setPolicy({
        adsPerSessionCap: cached.ads_per_session_cap,
        triggerPages: cached.trigger_pages,
        enabled: cached.enabled,
        source: cached.source,
      })
      setLoading(false)
      fetchingRef.current = false
      return
    }

    debugLog('CACHE MISS - will fetch from network')

    // No Supabase client = use defaults
    if (!supabase) {
      debugLog('No Supabase client, using defaults')
      setPolicy(DEFAULT_POLICY)
      setLoading(false)
      fetchingRef.current = false
      return
    }

    try {
      debugLog('NETWORK REQUEST: ad_policy_effective', {
        country: resolvedCode,
        supabaseUrl: (supabase as { supabaseUrl?: string }).supabaseUrl ?? 'check env',
      })

      // Try fetching policy for resolved country
      const { data: effectiveData, error: effectiveError } = await supabase
        .from('ad_policy_effective')
        .select('ads_per_session_cap, trigger_pages, enabled, source')
        .eq('country_code', resolvedCode)
        .limit(1)
        .single()

      if (effectiveError || !effectiveData) {
        debugLog('No policy for country in ad_policy_effective, trying ad_policy_default', { 
          resolvedCode, 
          error: effectiveError?.message,
          errorCode: effectiveError?.code,
        })

        debugLog('NETWORK REQUEST: ad_policy_default')

        // Try fetching default row
        const { data: defaultData, error: defaultError } = await supabase
          .from('ad_policy_default')
          .select('ads_per_session_cap, trigger_pages, enabled')
          .limit(1)
          .single()

        if (defaultError || !defaultData) {
          debugLog('No default row, using hardcoded defaults', { error: defaultError?.message })
          setPolicy(DEFAULT_POLICY)
          setLoading(false)
          fetchingRef.current = false
          return
        }

        // Use default row
        const policyFromDefault: AdPolicy = {
          adsPerSessionCap: defaultData.ads_per_session_cap ?? DEFAULT_POLICY.adsPerSessionCap,
          triggerPages: defaultData.trigger_pages ?? DEFAULT_POLICY.triggerPages,
          enabled: defaultData.enabled ?? DEFAULT_POLICY.enabled,
          source: 'default',
        }

        // Cache it
        setCachedPolicy({
          country_code: resolvedCode,
          ads_per_session_cap: policyFromDefault.adsPerSessionCap,
          trigger_pages: policyFromDefault.triggerPages,
          enabled: policyFromDefault.enabled,
          source: 'default',
          fetched_at: Date.now(),
        })

        debugLog('Policy loaded (default)', policyFromDefault)
        setPolicy(policyFromDefault)
        setLoading(false)
        fetchingRef.current = false
        return
      }

      // Use effective policy
      const effectivePolicy: AdPolicy = {
        adsPerSessionCap: effectiveData.ads_per_session_cap ?? DEFAULT_POLICY.adsPerSessionCap,
        triggerPages: effectiveData.trigger_pages ?? DEFAULT_POLICY.triggerPages,
        enabled: effectiveData.enabled ?? DEFAULT_POLICY.enabled,
        source: effectiveData.source ?? 'effective',
      }

      // Cache it
      setCachedPolicy({
        country_code: resolvedCode,
        ads_per_session_cap: effectivePolicy.adsPerSessionCap,
        trigger_pages: effectivePolicy.triggerPages,
        enabled: effectivePolicy.enabled,
        source: effectivePolicy.source,
        fetched_at: Date.now(),
      })

      debugLog('Policy loaded (effective)', { countryCode: resolvedCode, ...effectivePolicy })
      setPolicy(effectivePolicy)
      setLoading(false)
      fetchingRef.current = false
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error'
      debugLog('Policy fetch failed, using defaults', { error: message })
      setError(message)
      setPolicy(DEFAULT_POLICY)
      setLoading(false)
      fetchingRef.current = false
    }
  }, [])

  useEffect(() => {
    fetchPolicy()
  }, [fetchPolicy])

  // DEV override: return permissive policy for easy testing
  if (IS_DEV) {
    return {
      policy: DEV_OVERRIDE_POLICY,
      loading: false,
      error: null,
      countryCode,
      refetch: fetchPolicy,
    }
  }

  return {
    policy,
    loading,
    error,
    countryCode,
    refetch: fetchPolicy,
  }
}

// =============================================================================
// STANDALONE FETCH (for non-React contexts)
// =============================================================================

/**
 * Fetch ad policy synchronously from cache, or return defaults
 * Use this in non-React contexts where hooks aren't available.
 */
export function getAdPolicySync(): AdPolicy {
  // DEV override: return permissive policy for easy testing
  if (IS_DEV) {
    return DEV_OVERRIDE_POLICY
  }

  const countryCode = resolveCountryCode()
  const cached = getCachedPolicy(countryCode)

  if (cached) {
    return {
      adsPerSessionCap: cached.ads_per_session_cap,
      triggerPages: cached.trigger_pages,
      enabled: cached.enabled,
      source: cached.source,
    }
  }

  return DEFAULT_POLICY
}

/**
 * Fetch ad policy (async) for non-React contexts
 * Attempts network fetch if cache miss.
 */
export async function fetchAdPolicy(): Promise<AdPolicy> {
  // DEV override: return permissive policy for easy testing
  if (IS_DEV) {
    return DEV_OVERRIDE_POLICY
  }

  const countryCode = resolveCountryCode()

  // Check cache
  const cached = getCachedPolicy(countryCode)
  if (cached) {
    return {
      adsPerSessionCap: cached.ads_per_session_cap,
      triggerPages: cached.trigger_pages,
      enabled: cached.enabled,
      source: cached.source,
    }
  }

  // No Supabase = defaults
  if (!supabase) {
    return DEFAULT_POLICY
  }

  try {
    // Try effective
    const { data: effectiveData, error: effectiveError } = await supabase
      .from('ad_policy_effective')
      .select('ads_per_session_cap, trigger_pages, enabled, source')
      .eq('country_code', countryCode)
      .limit(1)
      .single()

    if (!effectiveError && effectiveData) {
      const policy: AdPolicy = {
        adsPerSessionCap: effectiveData.ads_per_session_cap ?? DEFAULT_POLICY.adsPerSessionCap,
        triggerPages: effectiveData.trigger_pages ?? DEFAULT_POLICY.triggerPages,
        enabled: effectiveData.enabled ?? DEFAULT_POLICY.enabled,
        source: effectiveData.source ?? 'effective',
      }

      setCachedPolicy({
        country_code: countryCode,
        ads_per_session_cap: policy.adsPerSessionCap,
        trigger_pages: policy.triggerPages,
        enabled: policy.enabled,
        source: policy.source,
        fetched_at: Date.now(),
      })

      return policy
    }

    // Try default
    const { data: defaultData, error: defaultError } = await supabase
      .from('ad_policy_default')
      .select('ads_per_session_cap, trigger_pages, enabled')
      .limit(1)
      .single()

    if (!defaultError && defaultData) {
      const policy: AdPolicy = {
        adsPerSessionCap: defaultData.ads_per_session_cap ?? DEFAULT_POLICY.adsPerSessionCap,
        triggerPages: defaultData.trigger_pages ?? DEFAULT_POLICY.triggerPages,
        enabled: defaultData.enabled ?? DEFAULT_POLICY.enabled,
        source: 'default',
      }

      setCachedPolicy({
        country_code: countryCode,
        ads_per_session_cap: policy.adsPerSessionCap,
        trigger_pages: policy.triggerPages,
        enabled: policy.enabled,
        source: 'default',
        fetched_at: Date.now(),
      })

      return policy
    }
  } catch {
    // Fall through to defaults
  }

  return DEFAULT_POLICY
}
