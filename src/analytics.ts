/**
 * Lethe Analytics - Privacy-first event logging
 * 
 * Metrics Spine v1 - All events include:
 *   day_bucket, time_bucket, dow_bucket, country_code, region, city_code,
 *   mode (feed_scope), session_hash, meta
 * 
 * NO user identity, NO IP, NO device fingerprint.
 */

import { supabase } from './supabase'

const SESSION_HASH_KEY = 'lethe_session_hash'
const SESSION_CREATED_KEY = 'lethe_session_created_at'
const SESSION_TTL_MS = 24 * 60 * 60 * 1000 // 24 hours

// Cached geo data (set once per session from feed response)
let cachedGeo: { country_code?: string; region?: string; city_code?: string } = {}

// DEV flag for logging
const DEV = import.meta.env.DEV

/**
 * Set geo dimensions from feed response (called once per session)
 * This avoids extra geo lookups - we piggyback on the feed's geo context.
 */
export function setGeoDimensions(geo: {
  country_code?: string
  region?: string
  city_code?: string
}): void {
  // Only set fields that have actual values (not empty strings)
  cachedGeo = {
    country_code: geo.country_code || undefined,
    region: geo.region || undefined,
    city_code: geo.city_code || undefined,
  }
  if (DEV) {
    console.log('[GEO DEBUG] setGeoDimensions called with:', geo)
    console.log('[GEO DEBUG] cachedGeo is now:', cachedGeo)
  }
}

/**
 * Get cached geo dimensions (for report submission, etc.)
 * Returns the geo context set by setGeoDimensions.
 */
export function getGeoDimensions(): {
  country_code?: string
  region?: string
  city_code?: string
} {
  if (DEV) {
    console.log('[GEO DEBUG] getGeoDimensions returning:', cachedGeo)
  }
  return { ...cachedGeo }
}

// Generate a random UUID
function generateUUID(): string {
  return crypto.randomUUID()
}

// Get current session hash, rotating if older than 24 hours
function getSessionHash(): string {
  try {
    const existingHash = localStorage.getItem(SESSION_HASH_KEY)
    const createdAt = localStorage.getItem(SESSION_CREATED_KEY)
    
    if (existingHash && createdAt) {
      const age = Date.now() - parseInt(createdAt, 10)
      if (age < SESSION_TTL_MS) {
        return existingHash
      }
    }
    
    // Create new session hash
    const newHash = generateUUID()
    localStorage.setItem(SESSION_HASH_KEY, newHash)
    localStorage.setItem(SESSION_CREATED_KEY, String(Date.now()))
    return newHash
  } catch {
    // Fallback if localStorage unavailable
    return generateUUID()
  }
}

// Get current local date as YYYY-MM-DD
function getDayBucket(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// Get current local hour (0-23)
function getTimeBucket(): number {
  return new Date().getHours()
}

// Get day of week (0=Sunday, 6=Saturday)
function getDowBucket(): number {
  return new Date().getDay()
}

/**
 * Event metadata interface
 */
export interface EventMeta {
  mode?: string          // feed_scope: 'world' | 'near'
  city_code?: string     // Override cached city
  language_detected?: string
  emotion_bucket?: string
  reason_bucket?: string // for post_reject
  [key: string]: unknown // Extensible via meta JSON
}

/**
 * Log an analytics event (best effort, fail silently)
 * 
 * Event types:
 *   session_start  - New session began
 *   page_fetch     - User fetched next page of confessions
 *   feed_view      - User viewed a feed tab
 *   feed_refresh   - User manually refreshed feed
 *   post_attempt   - User attempted to post
 *   post_success   - Post was successful
 *   post_reject    - Post was rejected (with reason_bucket)
 *   ad_shown       - Ad was displayed to user
 */
export async function logEvent(
  eventName: string,
  meta?: EventMeta
): Promise<void> {
  if (!supabase) return

  // Extract known columns from meta, put rest in meta JSON
  const {
    mode,
    city_code,
    language_detected,
    emotion_bucket,
    reason_bucket,
    ...extraMeta
  } = meta ?? {}

  // Build meta JSON only if there's extra data
  const metaJson = Object.keys(extraMeta).length > 0 ? extraMeta : null

  try {
    await supabase.from('event_logs').insert({
      event_name: eventName,
      day_bucket: getDayBucket(),
      time_bucket: getTimeBucket(),
      dow_bucket: getDowBucket(),
      session_hash: getSessionHash(),
      // Geo dimensions (from cache or override)
      country_code: cachedGeo.country_code ?? null,
      region: cachedGeo.region ?? null,
      city_code: city_code ?? cachedGeo.city_code ?? null,
      // Event-specific dimensions
      mode: mode ?? null,
      language_detected: language_detected ?? null,
      emotion_bucket: emotion_bucket ?? null,
      reason_bucket: reason_bucket ?? null,
      // Extensible metadata
      meta: metaJson,
    })
  } catch {
    // Fail silently - analytics must never block UX
  }
}
