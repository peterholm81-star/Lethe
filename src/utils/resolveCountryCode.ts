/**
 * Resolve country code for ad policy lookup (privacy-safe)
 * 
 * Order of precedence:
 * 1. Cached value from sessionStorage (from earlier in session)
 * 2. Geo data from analytics module (set from API response)
 * 3. Locale region from Intl.Locale (browser-derived)
 * 4. Fallback to "ZZ" (unknown)
 * 
 * No network calls. No user identity. Lightweight and offline-first.
 */

import { getGeoDimensions } from '../analytics'

const STORAGE_KEY = 'lethe.country_code'

// Dev override for testing (localStorage key)
const DEV_OVERRIDE_KEY = 'lethe.country_code_override'

/**
 * Resolve the best-effort country code
 * @returns Uppercase 2-letter ISO country code, or "ZZ" if unknown
 */
export function resolveCountryCode(): string {
  // DEV: Allow override for testing
  if (import.meta.env.DEV) {
    try {
      const override = localStorage.getItem(DEV_OVERRIDE_KEY)
      if (override && override.length === 2) {
        return override.toUpperCase()
      }
    } catch {
      // Ignore localStorage errors
    }
  }

  // 1. Check sessionStorage cache
  try {
    const cached = sessionStorage.getItem(STORAGE_KEY)
    if (cached && cached.length === 2) {
      return cached.toUpperCase()
    }
  } catch {
    // sessionStorage unavailable
  }

  // 2. Try geo data from analytics (set from API/feed response)
  const geoDimensions = getGeoDimensions()
  if (geoDimensions.country_code && geoDimensions.country_code.length === 2) {
    const code = geoDimensions.country_code.toUpperCase()
    cacheCountryCode(code)
    return code
  }

  // 3. Try Intl.Locale region
  try {
    if (typeof Intl !== 'undefined' && 'Locale' in Intl) {
      const locale = new Intl.Locale(navigator.language)
      if (locale.region && locale.region.length === 2) {
        const code = locale.region.toUpperCase()
        cacheCountryCode(code)
        return code
      }
    }
  } catch {
    // Intl.Locale not supported or invalid language tag
  }

  // 4. Fallback to unknown
  return 'ZZ'
}

/**
 * Cache country code in sessionStorage
 */
function cacheCountryCode(code: string): void {
  try {
    sessionStorage.setItem(STORAGE_KEY, code)
  } catch {
    // sessionStorage unavailable
  }
}

/**
 * Clear cached country code (useful for testing)
 */
export function clearCountryCodeCache(): void {
  try {
    sessionStorage.removeItem(STORAGE_KEY)
  } catch {
    // Ignore
  }
}
