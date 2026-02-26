import { useEffect, useRef } from 'react';
import type { PulseMetrics } from './usePulseMetrics';
import type { EngagementFlowMetrics } from './useEngagementFlow';

interface ConsistencyCheckParams {
  pulseData: PulseMetrics | null;
  pulseLoading: boolean;
  engagementData: EngagementFlowMetrics | null;
  engagementLoading: boolean;
  lensLabel: string;
  windowLabel: string;
}

/**
 * DEV-only hook to check consistency between Pulse and EngagementFlow sessions.
 * 
 * Since both Pulse and EngagementFlow should use the same window and lens,
 * their session counts MUST match. If they differ, something is wrong with
 * the data fetching or SQL definitions.
 * 
 * This hook logs a warning once per data change (not on every render).
 */
export function useInsightsConsistencyCheck({
  pulseData,
  pulseLoading,
  engagementData,
  engagementLoading,
  lensLabel,
  windowLabel,
}: ConsistencyCheckParams): void {
  // Only run in DEV
  if (!import.meta.env.DEV) return;

  // Track last checked values to avoid spam
  const lastCheckRef = useRef<{
    pulseSessions: number | null;
    engagementSessions: number | null;
  }>({ pulseSessions: null, engagementSessions: null });

  useEffect(() => {
    // Wait until both have loaded
    if (pulseLoading || engagementLoading) return;
    
    // Skip if either is null (error state)
    if (pulseData === null || engagementData === null) return;

    const pulseSessions = pulseData.sessions;
    const engagementSessions = engagementData.sessions;

    // Check if we already logged for these exact values
    const last = lastCheckRef.current;
    if (last.pulseSessions === pulseSessions && last.engagementSessions === engagementSessions) {
      return; // Already checked this combination
    }

    // Update last check
    lastCheckRef.current = { pulseSessions, engagementSessions };

    // Compare sessions
    if (pulseSessions !== engagementSessions) {
      console.warn(
        `[CONSISTENCY] Sessions mismatch!\n` +
        `  Pulse:      ${pulseSessions} sessions\n` +
        `  Engagement: ${engagementSessions} sessions\n` +
        `  Lens:       ${lensLabel}\n` +
        `  Window:     ${windowLabel}\n` +
        `  This indicates a bug in SQL definitions or data fetching.`
      );
    } else if (pulseSessions > 0) {
      // Optional: Log success in DEV for confirmation
      console.debug(
        `[CONSISTENCY] OK: Pulse (${pulseSessions}) == Engagement (${engagementSessions}) sessions | ${lensLabel} | ${windowLabel}`
      );
    }
  }, [pulseData, pulseLoading, engagementData, engagementLoading, lensLabel, windowLabel]);
}
