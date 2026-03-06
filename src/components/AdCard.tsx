/**
 * AdCard - Native-style sponsored placeholder for in-feed monetization
 * 
 * This component:
 * 1. Renders a visible ad unit in the feed
 * 2. Calls markAdShown() on mount to properly count ad impressions
 * 
 * IMPORTANT: Ad counting only happens when this component mounts,
 * NOT when ad is queued for insertion. This ensures accurate metrics.
 */

import React, { useEffect, useRef } from 'react'
import { markAdShown, getAdPolicyInfo } from '../state/session'

// Debug logging
const DEBUG_ADS = (
  import.meta.env.DEV || 
  (typeof localStorage !== 'undefined' && localStorage.getItem('debug_ads') === '1')
)

function adsLog(...args: unknown[]): void {
  if (DEBUG_ADS) {
    console.log('[ads]', ...args)
  }
}

interface AdCardProps {
  adId: string
  feedMode?: string
}

export function AdCard({ adId, feedMode }: AdCardProps) {
  // Guard to ensure we only mark shown ONCE per ad instance
  const hasMarkedRef = useRef(false)
  
  // On mount: mark ad as shown (this is where counting happens!)
  useEffect(() => {
    if (hasMarkedRef.current) {
      adsLog('AdCard already marked, skipping', { adId })
      return
    }
    
    hasMarkedRef.current = true
    
    // Get state BEFORE marking
    const infoBefore = getAdPolicyInfo()
    
    adsLog('AdCard MOUNTED -> marking shown', { 
      adId,
      feedMode,
      stateBefore: infoBefore.state,
      policy: {
        cap: infoBefore.policy.adsPerSessionCap,
        triggerPages: infoBefore.policy.triggerPages,
        enabled: infoBefore.policy.enabled,
        source: infoBefore.policy.source,
      },
    })
    
    // Actually count the ad (this also emits ad_shown to event_logs via logEvent)
    markAdShown(feedMode)

    if (import.meta.env.DEV) {
      console.debug('[analytics] ad_shown fired')
    }
    
    // Log state AFTER marking
    const infoAfter = getAdPolicyInfo()
    adsLog('AdCard marked shown complete', {
      adId,
      stateAfter: infoAfter.state,
      canShowMore: infoAfter.state.adsShownCount < (infoAfter.policy.adsPerSessionCap ?? 1),
    })
  }, [adId, feedMode])

  // DEV mode: make ad highly visible with distinct styling
  const devStyle: React.CSSProperties = DEBUG_ADS ? {
    background: 'rgba(100, 200, 150, 0.15)',
    border: '2px solid rgba(100, 200, 150, 0.4)',
    boxShadow: '0 0 10px rgba(100, 200, 150, 0.2)',
  } : {}

  return (
    <div className="ad-card" style={devStyle}>
      <span className="ad-label" style={DEBUG_ADS ? { color: 'rgba(100, 200, 150, 0.8)' } : {}}>
        {DEBUG_ADS ? '🧪 TEST AD' : 'Sponsored'}
      </span>
      <div className="ad-content">
        {DEBUG_ADS ? (
          <>
            <p className="ad-main" style={{ color: 'rgba(100, 200, 150, 0.9)' }}>
              ✅ AD VISIBLE IN FEED
            </p>
            <p className="ad-sub" style={{ color: 'rgba(100, 200, 150, 0.7)' }}>
              adId: {adId.slice(0, 12)}...
            </p>
          </>
        ) : (
          <>
            <p className="ad-main">A short break.</p>
            <p className="ad-sub">Back to confessions in a moment.</p>
          </>
        )}
      </div>
    </div>
  )
}
