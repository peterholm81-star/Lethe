/**
 * Lethe Session Manager v2
 * 
 * Manages anonymous sessions for metrics + monetization without user identifiers.
 * 
 * Session Rules (LOCKED):
 * - New session starts on: cold start OR foreground after >= 10 min background
 * - Session continues if backgrounded < 10 min
 * - No idle timeout while in foreground
 * 
 * Persistence:
 * - lastBackgroundAt stored in localStorage (for threshold detection)
 * - pageFetchCount and adsShownCount stored in sessionStorage (survives refresh within session)
 * - Other state (sessionId, adArmed) is in-memory only
 * 
 * Monetization Rules (POLICY-DRIVEN):
 * - pageFetchCount increments on "next page" fetches (not initial load)
 * - When pageFetchCount reaches policy.triggerPages, adArmed becomes true
 * - Max ads per session = policy.adsPerSessionCap (can be > 1)
 * - If policy.enabled = false, ads never show
 * - After showing an ad, pageFetchCount resets to re-arm for next ad (up to cap)
 */

import { getAdPolicySync, type AdPolicy } from '../hooks/useAdPolicyRuntime'
import { resolveCountryCode } from '../utils/resolveCountryCode'

// Debug logging (dev only, enabled via localStorage debug_ads=1)
const DEBUG = import.meta.env.DEV
const DEBUG_ADS = (
  DEBUG && typeof localStorage !== 'undefined' && localStorage.getItem('debug_ads') === '1'
) || (typeof localStorage !== 'undefined' && localStorage.getItem('debug_ads') === '1')

function log(...args: unknown[]) {
  if (DEBUG) {
    console.log('[session]', ...args)
  }
}

function adLog(...args: unknown[]) {
  if (DEBUG_ADS || DEBUG) {
    console.log('[session:ad]', ...args)
  }
}

function adsLog(...args: unknown[]) {
  if (DEBUG_ADS || DEBUG) {
    console.log('[ads]', ...args)
  }
}

function adPolicyEventLog(eventName: string, policyMeta: PolicyEventMeta): void {
  if (DEBUG_ADS) {
    console.log(
      `[ad-policy-event] ${eventName}`,
      `country=${policyMeta.country_code}`,
      `cap=${policyMeta.ads_per_session_cap}`,
      `trigger=${policyMeta.trigger_pages}`,
      `source=${policyMeta.source}`
    )
  }
}

// =============================================================================
// POLICY EVENT METADATA
// =============================================================================

/**
 * Policy metadata included in ad-related events
 */
interface PolicyEventMeta {
  country_code: string
  ads_per_session_cap: number
  trigger_pages: number
  enabled: boolean
  source: 'default' | 'override' | 'fallback'
}

/**
 * Build policy metadata for event logging
 * Uses cached policy, falls back to safe defaults if missing
 */
function buildPolicyEventMeta(): PolicyEventMeta {
  const policy = getPolicy()
  const countryCode = resolveCountryCode()
  
  // If policy is missing or incomplete, use fallback
  if (!policy || policy.adsPerSessionCap === undefined) {
    return {
      country_code: countryCode || 'ZZ',
      ads_per_session_cap: FALLBACK_ADS_PER_SESSION_CAP,
      trigger_pages: FALLBACK_TRIGGER_PAGES,
      enabled: true,
      source: 'fallback',
    }
  }
  
  return {
    country_code: countryCode || 'ZZ',
    ads_per_session_cap: policy.adsPerSessionCap ?? FALLBACK_ADS_PER_SESSION_CAP,
    trigger_pages: policy.triggerPages ?? FALLBACK_TRIGGER_PAGES,
    enabled: policy.enabled ?? true,
    source: (policy.source === 'override' || policy.source === 'default') 
      ? policy.source 
      : 'fallback',
  }
}

// Constants
const BACKGROUND_THRESHOLD_MS = 10 * 60 * 1000 // 10 minutes
const STORAGE_KEY_BACKGROUND = 'lethe:lastBackgroundAt'
const STORAGE_KEY_PAGE_FETCH_COUNT = 'lethe.ad_session.pageFetchCount'
const STORAGE_KEY_ADS_SHOWN_COUNT = 'lethe.ad_session.adsShownCount'

// Fallback defaults (used if policy not yet loaded)
const FALLBACK_TRIGGER_PAGES = 6
const FALLBACK_ADS_PER_SESSION_CAP = 1

// Session state interface
interface SessionState {
  sessionId: string
  pageFetchCount: number
  adsShownCount: number
  adArmed: boolean
}

// In-memory state (source of truth during runtime)
let state: SessionState = {
  sessionId: '',
  pageFetchCount: 0,
  adsShownCount: 0,
  adArmed: false,
}

// Cached policy (updated via setAdPolicy)
let cachedPolicy: AdPolicy | null = null

/**
 * Generate a random session ID (UUID-like)
 */
function generateSessionId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

/**
 * Get lastBackgroundAt from localStorage
 */
function getLastBackgroundAt(): number | null {
  try {
    const stored = localStorage.getItem(STORAGE_KEY_BACKGROUND)
    if (stored) {
      const ts = parseInt(stored, 10)
      return Number.isNaN(ts) ? null : ts
    }
  } catch {
    // localStorage may be unavailable
  }
  return null
}

/**
 * Set lastBackgroundAt in localStorage
 */
function setLastBackgroundAt(timestamp: number): void {
  try {
    localStorage.setItem(STORAGE_KEY_BACKGROUND, String(timestamp))
  } catch {
    // localStorage may be unavailable
  }
}

/**
 * Clear lastBackgroundAt from localStorage
 */
function clearLastBackgroundAt(): void {
  try {
    localStorage.removeItem(STORAGE_KEY_BACKGROUND)
  } catch {
    // localStorage may be unavailable
  }
}

/**
 * Get session counters from sessionStorage
 */
function getSessionCounters(): { pageFetchCount: number; adsShownCount: number } {
  try {
    const pageFetch = sessionStorage.getItem(STORAGE_KEY_PAGE_FETCH_COUNT)
    const adsShown = sessionStorage.getItem(STORAGE_KEY_ADS_SHOWN_COUNT)
    return {
      pageFetchCount: pageFetch ? parseInt(pageFetch, 10) || 0 : 0,
      adsShownCount: adsShown ? parseInt(adsShown, 10) || 0 : 0,
    }
  } catch {
    return { pageFetchCount: 0, adsShownCount: 0 }
  }
}

/**
 * Save session counters to sessionStorage
 */
function saveSessionCounters(): void {
  try {
    sessionStorage.setItem(STORAGE_KEY_PAGE_FETCH_COUNT, String(state.pageFetchCount))
    sessionStorage.setItem(STORAGE_KEY_ADS_SHOWN_COUNT, String(state.adsShownCount))
  } catch {
    // sessionStorage unavailable
  }
}

/**
 * Clear session counters from sessionStorage
 */
function clearSessionCounters(): void {
  try {
    sessionStorage.removeItem(STORAGE_KEY_PAGE_FETCH_COUNT)
    sessionStorage.removeItem(STORAGE_KEY_ADS_SHOWN_COUNT)
  } catch {
    // sessionStorage unavailable
  }
}

/**
 * Get current effective policy (cached or sync fetch)
 */
function getPolicy(): AdPolicy {
  if (cachedPolicy) {
    return cachedPolicy
  }
  // Try to get from sync cache (if hook has run before)
  return getAdPolicySync()
}

/**
 * Set ad policy (called from React component after hook loads)
 */
export function setAdPolicy(policy: AdPolicy): void {
  cachedPolicy = policy
  adLog('Policy set:', policy)
  
  // Re-evaluate ad armed state with new policy
  evaluateAdArmed()
}

/**
 * Evaluate whether ad should be armed based on current state and policy
 */
function evaluateAdArmed(): void {
  const policy = getPolicy()
  const triggerPages = policy.triggerPages ?? FALLBACK_TRIGGER_PAGES
  const cap = policy.adsPerSessionCap ?? FALLBACK_ADS_PER_SESSION_CAP

  // If ads disabled or cap reached, never arm
  if (!policy.enabled) {
    state.adArmed = false
    adsLog('evaluateAdArmed: ads disabled by policy')
    return
  }
  
  if (state.adsShownCount >= cap) {
    state.adArmed = false
    adsLog('evaluateAdArmed: cap reached', { adsShownCount: state.adsShownCount, cap })
    return
  }

  // Arm if we've reached trigger threshold
  if (state.pageFetchCount >= triggerPages) {
    if (!state.adArmed) {
      state.adArmed = true
      adsLog('AD ARMED!', { 
        pageFetchCount: state.pageFetchCount, 
        triggerPages, 
        adsShownCount: state.adsShownCount, 
        cap,
        source: policy.source,
      })
    }
  } else {
    adsLog('evaluateAdArmed: not yet armed', { 
      pageFetchCount: state.pageFetchCount, 
      triggerPages, 
      needMore: triggerPages - state.pageFetchCount,
    })
  }
}

/**
 * Start a new session: generate new ID, reset all counters/flags
 */
export function startNewSession(): void {
  state = {
    sessionId: generateSessionId(),
    pageFetchCount: 0,
    adsShownCount: 0,
    adArmed: false,
  }
  // Clear storage when starting new session
  clearLastBackgroundAt()
  clearSessionCounters()
  log('NEW SESSION started', { sessionId: state.sessionId })
}

// Guard against double-init in React strict mode
let sessionInitialized = false

/**
 * Initialize session on app load (cold start)
 * Restores counters from sessionStorage if available (survives page refresh).
 * Guarded against double-init in React strict mode.
 */
export function initSessionIfNeeded(): void {
  // Prevent double-init in React strict mode
  if (sessionInitialized && state.sessionId) {
    log('Session already initialized, skipping', { sessionId: state.sessionId })
    return
  }
  
  sessionInitialized = true
  
  // Generate new session ID only if we don't have one
  if (!state.sessionId) {
    state.sessionId = generateSessionId()
  }
  
  // Restore counters from sessionStorage (survives refresh)
  const counters = getSessionCounters()
  state.pageFetchCount = counters.pageFetchCount
  state.adsShownCount = counters.adsShownCount
  state.adArmed = false
  
  // Re-evaluate ad armed state
  evaluateAdArmed()
  
  log('Session initialized', { 
    sessionId: state.sessionId, 
    pageFetchCount: state.pageFetchCount,
    adsShownCount: state.adsShownCount,
    adArmed: state.adArmed,
  })
}

/**
 * Called when app goes to background (hidden)
 */
export function onAppBackground(): void {
  const timestamp = Date.now()
  setLastBackgroundAt(timestamp)
  log('App backgrounded at', new Date(timestamp).toISOString())
}

/**
 * Called when app returns to foreground (visible)
 * If backgrounded >= 10 min, start new session
 */
export function onAppForeground(): void {
  const lastBackgroundAt = getLastBackgroundAt()
  
  if (lastBackgroundAt !== null) {
    const elapsed = Date.now() - lastBackgroundAt
    log('App foregrounded, elapsed:', Math.round(elapsed / 1000), 'seconds')
    
    if (elapsed >= BACKGROUND_THRESHOLD_MS) {
      log('Background threshold exceeded, starting new session')
      startNewSession()
    } else {
      // Clear background timestamp, session continues
      clearLastBackgroundAt()
      log('Session continues (background < 10 min)')
    }
  }
}

/**
 * Record a "next page" fetch (pagination beyond initial load)
 * Increments counter and arms ad when threshold reached.
 * Also logs page_fetch event for analytics with policy context.
 */
export function recordPageFetch(): void {
  // Build policy metadata for event
  const policyMeta = buildPolicyEventMeta()
  
  // Log the event with policy context
  import('../analytics').then(({ logEvent }) => {
    logEvent('page_fetch', { policy: policyMeta })
    adPolicyEventLog('page_fetch', policyMeta)
  }).catch(() => {
    // Fail silently - analytics must never block UX
  })

  const policy = getPolicy()
  const cap = policy.adsPerSessionCap ?? FALLBACK_ADS_PER_SESSION_CAP

  // Don't count for ad triggering if cap reached or ads disabled
  if (!policy.enabled) {
    log('Page fetch ignored for ad (ads disabled by policy)')
    return
  }

  if (state.adsShownCount >= cap) {
    log('Page fetch ignored for ad (session cap reached)', { adsShown: state.adsShownCount, cap })
    return
  }
  
  state.pageFetchCount++
  saveSessionCounters()
  log('Page fetch recorded, count:', state.pageFetchCount)
  
  // Evaluate if ad should be armed
  evaluateAdArmed()
}

/**
 * Mark ad as shown (called when AdCard mounts, NOT when ad is queued)
 * Increments adsShownCount and resets pageFetchCount for next ad cycle.
 * Also logs ad_shown event for analytics with policy context.
 * 
 * IMPORTANT: This should ONLY be called from AdCard component on mount,
 * never from ad insertion/queueing logic.
 */
export function markAdShown(mode?: string): void {
  const policy = getPolicy()
  const cap = policy.adsPerSessionCap ?? FALLBACK_ADS_PER_SESSION_CAP
  
  // Build policy metadata for event BEFORE incrementing counters
  const policyMeta = buildPolicyEventMeta()
  
  // Capture state before change for logging
  const countBefore = state.adsShownCount
  
  state.adsShownCount++
  state.adArmed = false
  
  // Reset page fetch count to start counting for next ad (if under cap)
  state.pageFetchCount = 0
  
  saveSessionCounters()
  
  const canShowMore = state.adsShownCount < cap
  
  adsLog('markAdShown called (from AdCard mount)', {
    mode,
    countBefore,
    countAfter: state.adsShownCount,
    cap,
    canShowMore,
    policy: { 
      enabled: policy.enabled, 
      triggerPages: policy.triggerPages, 
      source: policy.source,
    },
  })
  
  // Log ad_shown event for analytics with policy context
  import('../analytics').then(({ logEvent }) => {
    logEvent('ad_shown', { 
      mode,
      policy: policyMeta,
      ads_shown_count: state.adsShownCount,
      can_show_more: canShowMore,
    })
    adPolicyEventLog('ad_shown', policyMeta)
  }).catch(() => {
    // Fail silently - analytics must never block UX
  })
}

/**
 * Get current session state (read-only snapshot)
 */
export function getSessionState(): Readonly<SessionState> {
  return { ...state }
}

/**
 * Check if ad is currently armed and ready to show
 * Respects policy.enabled flag.
 */
export function isAdArmed(): boolean {
  const policy = getPolicy()
  
  // Never armed if disabled
  if (!policy.enabled) {
    return false
  }
  
  // Never armed if cap reached
  const cap = policy.adsPerSessionCap ?? FALLBACK_ADS_PER_SESSION_CAP
  if (state.adsShownCount >= cap) {
    return false
  }
  
  return state.adArmed
}

/**
 * Check if session ad cap has been reached
 */
export function hasReachedAdCap(): boolean {
  const policy = getPolicy()
  const cap = policy.adsPerSessionCap ?? FALLBACK_ADS_PER_SESSION_CAP
  return state.adsShownCount >= cap
}

/**
 * Check if ad has already been shown this session (at least once)
 * @deprecated Use hasReachedAdCap() for cap-aware check
 */
export function hasAdShown(): boolean {
  return state.adsShownCount > 0
}

/**
 * Get current session ID
 */
export function getSessionId(): string {
  return state.sessionId
}

/**
 * Get current page fetch count
 */
export function getPageFetchCount(): number {
  return state.pageFetchCount
}

/**
 * Get current ads shown count
 */
export function getAdsShownCount(): number {
  return state.adsShownCount
}

/**
 * Get current policy info (for debugging)
 */
export function getAdPolicyInfo(): { policy: AdPolicy; state: { pageFetchCount: number; adsShownCount: number; adArmed: boolean } } {
  return {
    policy: getPolicy(),
    state: {
      pageFetchCount: state.pageFetchCount,
      adsShownCount: state.adsShownCount,
      adArmed: state.adArmed,
    },
  }
}

/**
 * DEV ONLY: Reset all ad-related session state and storage.
 * Clears the following keys:
 * 
 * sessionStorage:
 *   - lethe.ad_session.pageFetchCount
 *   - lethe.ad_session.adsShownCount
 *   - lethe.ad_policy_effective.v1:* (all cached policies)
 *   - lethe.country_code
 * 
 * localStorage:
 *   - lethe:lastBackgroundAt
 *   - lethe.country_code_override (DEV override)
 * 
 * In-memory:
 *   - pageFetchCount -> 0
 *   - adsShownCount -> 0
 *   - adArmed -> false
 *   - cachedPolicy -> null
 *   - sessionInitialized -> false (allows re-init)
 * 
 * Does NOT clear:
 *   - debug_ads (preserve debug setting)
 *   - lethe_onboarding_seen (preserve onboarding state)
 *   - SESSION_HASH_KEY / SESSION_CREATED_KEY (analytics session)
 */
export function devResetAdSession(): void {
  // Clear sessionStorage keys
  const sessionKeysToRemove = [
    STORAGE_KEY_PAGE_FETCH_COUNT,
    STORAGE_KEY_ADS_SHOWN_COUNT,
    'lethe.country_code',
  ]
  
  // Also clear any cached policy keys (lethe.ad_policy_effective.v1:*)
  for (let i = sessionStorage.length - 1; i >= 0; i--) {
    const key = sessionStorage.key(i)
    if (key && key.startsWith('lethe.ad_policy_effective.v1:')) {
      sessionStorage.removeItem(key)
    }
  }
  
  sessionKeysToRemove.forEach(key => {
    sessionStorage.removeItem(key)
  })
  
  // Clear localStorage keys
  const localKeysToRemove = [
    STORAGE_KEY_BACKGROUND,
    'lethe.country_code_override',
  ]
  
  localKeysToRemove.forEach(key => {
    localStorage.removeItem(key)
  })
  
  // Reset in-memory state
  state.pageFetchCount = 0
  state.adsShownCount = 0
  state.adArmed = false
  state.sessionId = generateSessionId()
  cachedPolicy = null
  sessionInitialized = false
  
  console.log('[ads] DEV reset complete', {
    clearedSessionStorage: [...sessionKeysToRemove, 'lethe.ad_policy_effective.v1:*'],
    clearedLocalStorage: localKeysToRemove,
    newSessionId: state.sessionId,
  })
}
