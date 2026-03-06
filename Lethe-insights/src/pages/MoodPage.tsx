import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { useMoodSummary } from '../hooks/useMoodSummary';
import { useMoodPulse } from '../hooks/useMoodPulse';
import { useMoodPulseByRegion } from '../hooks/useMoodPulseByRegion';
import { MoodWorldMap } from '../components/mood/MoodWorldMap';
import { InfoHint } from '../components/ui/InfoHint';
import { moodInfo } from './mood/moodInfo';

// =============================================================================
// STYLES - AI Observer Theme
// =============================================================================

const HEADER_OFFSET = 56;

const styles = {
  container: {
    '--moodHeaderOffset': `${HEADER_OFFSET}px`,
    padding: '16px 28px 20px',
    height: `calc(100vh - ${HEADER_OFFSET}px)`,
    maxHeight: `calc(100vh - ${HEADER_OFFSET}px)`,
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column' as const,
    background: 'linear-gradient(180deg, rgba(12, 12, 18, 0.95) 0%, rgba(8, 8, 12, 1) 100%)',
  } as React.CSSProperties,

  filterRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    marginBottom: 14,
    flexWrap: 'wrap' as const,
    flexShrink: 0,
  } as React.CSSProperties,

  filterGroup: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  } as React.CSSProperties,

  filterLabel: {
    fontSize: 11,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  filterSelect: {
    padding: '8px 12px',
    fontSize: 12,
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.9)',
    background: 'rgba(255, 255, 255, 0.04)',
    border: '1px solid rgba(255, 255, 255, 0.08)',
    borderRadius: 8,
    cursor: 'pointer',
    minWidth: 120,
    transition: 'all 0.2s ease',
  } as React.CSSProperties,

  refreshBtn: {
    padding: '8px 18px',
    fontSize: 11,
    fontWeight: 600,
    color: 'rgba(100, 180, 255, 0.95)',
    background: 'rgba(100, 180, 255, 0.1)',
    border: '1px solid rgba(100, 180, 255, 0.2)',
    borderRadius: 8,
    cursor: 'pointer',
    marginLeft: 'auto',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
    transition: 'all 0.2s ease',
  } as React.CSSProperties,

  heroSection: {
    display: 'grid',
    gridTemplateColumns: '2fr 3fr',
    gap: 16,
    marginBottom: 14,
    flex: 1,
    minHeight: 0,
    height: 'clamp(280px, 52vh, 420px)',
  } as React.CSSProperties,

  narrativePanel: {
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    borderRadius: 12,
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRight: '1px solid rgba(255, 255, 255, 0.04)',
    padding: '18px 20px',
    display: 'flex',
    flexDirection: 'column' as const,
    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.03)',
    position: 'relative' as const,
    height: '100%',
    minHeight: 0,
    overflow: 'hidden',
  } as React.CSSProperties,

  narrativeDivider: {
    position: 'absolute' as const,
    right: -8,
    top: 24,
    bottom: 24,
    width: 1,
    background: 'linear-gradient(180deg, transparent 0%, rgba(255, 255, 255, 0.06) 20%, rgba(255, 255, 255, 0.06) 80%, transparent 100%)',
  } as React.CSSProperties,

  narrativeHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 4,
    flexShrink: 0,
  } as React.CSSProperties,

  narrativeTitle: {
    fontSize: 14,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.7)',
    letterSpacing: '-0.01em',
  } as React.CSSProperties,

  headerMetaRight: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.5)',
    marginLeft: 'auto',
    paddingLeft: 12,
    fontWeight: 400,
  } as React.CSSProperties,

  headerMetaSeparator: {
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,

  liveStatus: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 2,
    marginTop: 4,
    marginBottom: 8,
  } as React.CSSProperties,

  liveStatusLine: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.5)',
    letterSpacing: '0.05em',
    flexWrap: 'wrap' as const,
  } as React.CSSProperties,


  confidenceBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
    padding: '2px 8px',
    fontSize: 8,
    fontWeight: 600,
    borderRadius: 4,
    marginLeft: 8,
    letterSpacing: '0.04em',
    cursor: 'help',
  } as React.CSSProperties,

  confidenceLow: {
    background: 'rgba(255, 180, 100, 0.12)',
    color: 'rgba(255, 180, 100, 0.8)',
    border: '1px solid rgba(255, 180, 100, 0.2)',
  } as React.CSSProperties,

  confidenceMedium: {
    background: 'rgba(180, 180, 255, 0.1)',
    color: 'rgba(180, 180, 255, 0.75)',
    border: '1px solid rgba(180, 180, 255, 0.15)',
  } as React.CSSProperties,

  confidenceHigh: {
    background: 'rgba(100, 200, 150, 0.1)',
    color: 'rgba(100, 200, 150, 0.8)',
    border: '1px solid rgba(100, 200, 150, 0.2)',
  } as React.CSSProperties,

  liveDot: {
    width: 4,
    height: 4,
    borderRadius: '50%',
    background: 'rgba(100, 200, 150, 0.6)',
  } as React.CSSProperties,

  liveLabel: {
    fontSize: 8,
    fontWeight: 700,
    color: 'rgba(100, 200, 150, 0.7)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.1em',
  } as React.CSSProperties,

  liveText: {
    color: 'rgba(255, 255, 255, 0.45)',
    fontWeight: 400,
  } as React.CSSProperties,

  updatedAgo: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.35)',
    fontWeight: 400,
  } as React.CSSProperties,

  observerStatusLine: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.55)',
    letterSpacing: 'normal',
    marginTop: 6,
    marginBottom: 12,
    lineHeight: 1.5,
  } as React.CSSProperties,

  focusTransitionLine: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 10,
    color: 'rgba(100, 180, 255, 0.7)',
    letterSpacing: '0.02em',
    marginBottom: 8,
    minHeight: 16,
    opacity: 0,
    transition: 'opacity 150ms ease-in-out',
  } as React.CSSProperties,

  focusTransitionLineVisible: {
    opacity: 1,
  } as React.CSSProperties,

  focusTransitionDot: {
    width: 4,
    height: 4,
    borderRadius: '50%',
    background: 'rgba(100, 180, 255, 0.6)',
    animation: 'focusPulse 400ms ease-in-out infinite',
  } as React.CSSProperties,

  observerPulseDot: {
    width: 5,
    height: 5,
    borderRadius: '50%',
    background: 'rgba(100, 180, 255, 0.5)',
    animation: 'observerPulse 2s ease-in-out infinite',
    flexShrink: 0,
  } as React.CSSProperties,

  observerStatusText: {
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  narrativeSubtitle: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.35)',
    marginBottom: 8,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.12em',
  } as React.CSSProperties,

  narrativeContent: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column' as const,
    minHeight: 0,
    transition: 'opacity 0.7s ease-in-out',
  } as React.CSSProperties,

  narrativeScoreSection: {
    position: 'relative' as const,
    display: 'flex',
    alignItems: 'center',
    gap: 16,
    marginBottom: 4,
  } as React.CSSProperties,

  narrativeScoreContent: {
    position: 'relative' as const,
    flex: 1,
  } as React.CSSProperties,

  balanceRingContainer: {
    position: 'relative' as const,
    width: 56,
    height: 56,
    flexShrink: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  } as React.CSSProperties,

  balanceRingGlow: {
    position: 'absolute' as const,
    top: '50%',
    left: '50%',
    transform: 'translate(-50%, -50%)',
    width: 70,
    height: 70,
    borderRadius: '50%',
    pointerEvents: 'none' as const,
    transition: 'background 1s ease, opacity 1s ease',
    opacity: 0.6,
  } as React.CSSProperties,

  narrativeScoreGlow: {
    position: 'absolute' as const,
    top: '50%',
    left: '50%',
    transform: 'translate(-50%, -50%)',
    width: 200,
    height: 120,
    borderRadius: '50%',
    pointerEvents: 'none' as const,
    transition: 'background 1s ease',
  } as React.CSSProperties,

  regionHeroLabel: {
    fontSize: 20,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.85)',
    letterSpacing: '-0.01em',
    marginBottom: 4,
    transition: 'opacity 0.7s ease',
  } as React.CSSProperties,

  narrativeRegionLabel: {
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(100, 180, 255, 0.5)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.15em',
    marginBottom: 2,
    transition: 'opacity 0.7s ease',
  } as React.CSSProperties,

  referenceTimeContainer: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    marginBottom: 6,
    position: 'relative' as const,
  } as React.CSSProperties,

  referenceTimeText: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.4)',
    fontWeight: 400,
    transition: 'opacity 0.7s ease',
  } as React.CSSProperties,

  referenceTimeZone: {
    fontSize: 9,
    color: 'rgba(100, 180, 255, 0.4)',
    fontWeight: 500,
  } as React.CSSProperties,

  referenceTimeHint: {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: 14,
    height: 14,
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.3)',
    background: 'rgba(255, 255, 255, 0.06)',
    borderRadius: '50%',
    cursor: 'help',
    transition: 'all 0.2s ease',
  } as React.CSSProperties,

  referenceTimeTooltip: {
    position: 'absolute' as const,
    top: '100%',
    left: 0,
    marginTop: 6,
    padding: '8px 12px',
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.7)',
    background: 'rgba(20, 22, 30, 0.95)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: 6,
    whiteSpace: 'nowrap' as const,
    zIndex: 20,
    boxShadow: '0 4px 12px rgba(0, 0, 0, 0.3)',
    backdropFilter: 'blur(8px)',
    pointerEvents: 'none' as const,
  } as React.CSSProperties,

  narrativeScore: {
    fontSize: 'clamp(48px, 8vh, 68px)',
    fontWeight: 800,
    lineHeight: 1,
    letterSpacing: '-0.03em',
    position: 'relative' as const,
    zIndex: 1,
    transition: 'color 0.7s ease, text-shadow 0.7s ease',
  } as React.CSSProperties,

  narrativeDelta: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 5,
    fontSize: 12,
    fontWeight: 600,
    marginTop: 2,
    marginBottom: 12,
    transition: 'color 0.7s ease',
  } as React.CSSProperties,

  narrativeDeltaArrow: {
    fontSize: 11,
    fontWeight: 700,
  } as React.CSSProperties,

  narrativeAiLabel: {
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(100, 180, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.15em',
    marginBottom: 4,
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  } as React.CSSProperties,

  narrativeAiDot: {
    width: 4,
    height: 4,
    borderRadius: '50%',
    background: 'rgba(100, 180, 255, 0.5)',
  } as React.CSSProperties,

  narrativeDescription: {
    fontSize: 13,
    color: 'rgba(255, 255, 255, 0.5)',
    lineHeight: 1.7,
    marginBottom: 12,
    fontWeight: 400,
    transition: 'opacity 0.7s ease',
  } as React.CSSProperties,

  insightsSection: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 7,
    flex: 1,
    minHeight: 0,
    overflow: 'hidden',
    transition: 'opacity 0.7s ease',
  } as React.CSSProperties,

  insightLine: {
    fontSize: 11.5,
    color: 'rgba(255, 255, 255, 0.55)',
    lineHeight: 1.5,
    fontWeight: 500,
    display: 'flex',
    alignItems: 'center',
    gap: 7,
  } as React.CSSProperties,

  insightArrow: {
    fontSize: 12,
    fontWeight: 600,
    width: 16,
    textAlign: 'center' as const,
  } as React.CSSProperties,

  insightLabel: {
    color: 'rgba(255, 255, 255, 0.35)',
    marginRight: 4,
  } as React.CSSProperties,

  insightValue: {
    color: 'rgba(255, 255, 255, 0.6)',
  } as React.CSSProperties,

  insightPositive: {
    color: 'rgba(100, 200, 150, 0.7)',
  } as React.CSSProperties,

  insightNegative: {
    color: 'rgba(200, 120, 120, 0.7)',
  } as React.CSSProperties,

  insightNeutral: {
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  narrativeStats: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 10,
    marginTop: 'auto',
    paddingTop: 12,
    borderTop: '1px solid rgba(255, 255, 255, 0.05)',
    flexShrink: 0,
  } as React.CSSProperties,

  narrativeStat: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 2,
  } as React.CSSProperties,

  narrativeStatLabel: {
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.3)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.1em',
  } as React.CSSProperties,

  narrativeStatValue: {
    fontSize: 16,
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.85)',
    transition: 'color 0.7s ease',
  } as React.CSSProperties,

  mapPanel: {
    position: 'relative' as const,
    background: 'linear-gradient(135deg, rgba(18, 18, 28, 0.9) 0%, rgba(12, 12, 18, 0.95) 100%)',
    borderRadius: 12,
    border: '1px solid rgba(100, 180, 255, 0.1)',
    overflow: 'hidden',
    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), 0 0 60px rgba(100, 180, 255, 0.03)',
    height: '100%',
    minHeight: 0,
  } as React.CSSProperties,

  mapLabel: {
    position: 'absolute' as const,
    top: 14,
    left: 16,
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(100, 180, 255, 0.5)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.1em',
    zIndex: 10,
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  } as React.CSSProperties,

  mapLabelDot: {
    width: 5,
    height: 5,
    borderRadius: '50%',
    background: 'rgba(100, 180, 255, 0.4)',
  } as React.CSSProperties,

  bottomSection: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: 14,
    height: 'clamp(140px, 22vh, 180px)',
    flexShrink: 0,
  } as React.CSSProperties,

  card: {
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.8) 0%, rgba(15, 15, 22, 0.9) 100%)',
    borderRadius: 12,
    border: '1px solid rgba(255, 255, 255, 0.05)',
    padding: '14px 16px',
    boxShadow: '0 4px 20px rgba(0, 0, 0, 0.2)',
    height: '100%',
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column' as const,
    overflow: 'hidden',
  } as React.CSSProperties,

  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 10,
    flexShrink: 0,
  } as React.CSSProperties,

  cardTitle: {
    fontSize: 11,
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.5)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.1em',
  } as React.CSSProperties,

  cardBadge: {
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(100, 180, 255, 0.8)',
    background: 'rgba(100, 180, 255, 0.1)',
    padding: '3px 8px',
    borderRadius: 4,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  momentumValue: {
    fontSize: 'clamp(28px, 4vh, 34px)',
    fontWeight: 800,
    marginBottom: 4,
    letterSpacing: '-0.02em',
  } as React.CSSProperties,

  momentumLabel: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.4)',
    marginBottom: 8,
    lineHeight: 1.3,
  } as React.CSSProperties,

  momentumBar: {
    height: 5,
    background: 'rgba(255, 255, 255, 0.06)',
    borderRadius: 3,
    overflow: 'hidden',
    marginTop: 'auto',
    flexShrink: 0,
  } as React.CSSProperties,

  momentumBarFill: {
    height: '100%',
    borderRadius: 3,
    transition: 'width 1.2s ease',
  } as React.CSSProperties,

  stabilityGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 8,
    flex: 1,
    minHeight: 0,
  } as React.CSSProperties,

  stabilityItem: {
    background: 'rgba(255, 255, 255, 0.02)',
    borderRadius: 6,
    padding: '8px 10px',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 2,
    minHeight: 0,
  } as React.CSSProperties,

  stabilityItemLabel: {
    fontSize: 8,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.35)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  stabilityItemValue: {
    fontSize: 'clamp(14px, 2vh, 16px)',
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.9)',
  } as React.CSSProperties,

  moversList: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 6,
    flex: 1,
    minHeight: 0,
    overflow: 'hidden',
  } as React.CSSProperties,

  moverRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '6px 10px',
    background: 'rgba(255, 255, 255, 0.02)',
    borderRadius: 6,
    transition: 'background 0.2s ease',
    flexShrink: 0,
  } as React.CSSProperties,

  moverLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  } as React.CSSProperties,

  moverEmoji: {
    fontSize: 14,
  } as React.CSSProperties,

  moverName: {
    fontSize: 11,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.85)',
  } as React.CSSProperties,

  moverValue: {
    fontSize: 11,
    fontWeight: 700,
  } as React.CSSProperties,

  emptyState: {
    padding: '32px 20px',
    textAlign: 'center' as const,
    color: 'rgba(255, 255, 255, 0.3)',
    fontSize: 13,
  } as React.CSSProperties,

  loadingState: {
    padding: '32px 20px',
    textAlign: 'center' as const,
    color: 'rgba(255, 255, 255, 0.3)',
    fontSize: 13,
  } as React.CSSProperties,

  errorState: {
    padding: '16px 20px',
    textAlign: 'center' as const,
    color: 'rgba(255, 100, 100, 0.8)',
    fontSize: 12,
    background: 'rgba(255, 100, 100, 0.08)',
    borderRadius: 10,
    marginBottom: 20,
    border: '1px solid rgba(255, 100, 100, 0.15)',
  } as React.CSSProperties,
};

// =============================================================================
// OBSERVER ROTATION CONFIG
// =============================================================================

// Monitored region count (for UI display - future: make dynamic)
const MONITORED_REGION_COUNT = 142;

const OBSERVER_REGIONS = [
  'Europe',
  'North America', 
  'Asia',
  'South America',
  'Africa',
  'Oceania',
  'Middle East',
];

const ROTATION_INTERVAL = 10000; // 10 seconds
const FADE_DURATION = 700; // ms

// =============================================================================
// REGION TIMEZONES (Anchor timezones - regions span multiple zones)
// =============================================================================

interface TimezoneConfig {
  timezone: string;
  label: string; // Short label like "CET" or "EST"
}

const REGION_TIMEZONES: Record<string, TimezoneConfig> = {
  'Europe': { timezone: 'Europe/Berlin', label: 'CET' },
  'North America': { timezone: 'America/New_York', label: 'EST' },
  'Asia': { timezone: 'Asia/Singapore', label: 'SGT' },
  'South America': { timezone: 'America/Sao_Paulo', label: 'BRT' },
  'Africa': { timezone: 'Africa/Nairobi', label: 'EAT' },
  'Oceania': { timezone: 'Australia/Sydney', label: 'AEDT' },
  'Middle East': { timezone: 'Asia/Dubai', label: 'GST' },
};

function getRegionReferenceTime(region: string): { time: string; label: string } {
  const config = REGION_TIMEZONES[region];
  if (!config) return { time: '--:--', label: '' };
  
  try {
    const now = new Date();
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: config.timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
    return { time: formatter.format(now), label: config.label };
  } catch {
    return { time: '--:--', label: '' };
  }
}

// =============================================================================
// FILTER OPTIONS
// =============================================================================

const TIME_RANGE_OPTIONS = [
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
];

// =============================================================================
// MOOD DISPLAY HELPERS
// =============================================================================

const MOOD_DISPLAY: Record<string, { label: string; emoji: string }> = {
  joy: { label: 'Joy', emoji: '😊' },
  love: { label: 'Love', emoji: '❤️' },
  calm: { label: 'Calm', emoji: '😌' },
  hope: { label: 'Hope', emoji: '✨' },
  gratitude: { label: 'Gratitude', emoji: '🙏' },
  confidence: { label: 'Confidence', emoji: '💪' },
  anxiety: { label: 'Anxiety', emoji: '😰' },
  sadness: { label: 'Sadness', emoji: '😢' },
  anger: { label: 'Anger', emoji: '😠' },
  loneliness: { label: 'Loneliness', emoji: '😔' },
  desire: { label: 'Desire', emoji: '🤤' },
  shame: { label: 'Shame', emoji: '😳' },
};

function getMoodDisplay(bucket: string): { label: string; emoji: string } {
  return MOOD_DISPLAY[bucket] || { label: bucket, emoji: '❓' };
}

// =============================================================================
// COLOR HELPERS
// =============================================================================

function getScoreColor(score: number): string {
  if (score > 0.05) return 'rgba(100, 200, 150, 1)';
  if (score < -0.05) return 'rgba(200, 120, 120, 1)';
  return 'rgba(255, 255, 255, 0.7)';
}

function getScoreGlow(score: number): string {
  if (score > 0.05) return 'radial-gradient(ellipse at center, rgba(100, 200, 150, 0.12) 0%, transparent 70%)';
  if (score < -0.05) return 'radial-gradient(ellipse at center, rgba(200, 120, 120, 0.1) 0%, transparent 70%)';
  return 'radial-gradient(ellipse at center, rgba(255, 255, 255, 0.04) 0%, transparent 70%)';
}

function getDeltaColor(delta: number): string {
  if (delta > 0) return 'rgba(100, 200, 150, 0.8)';
  if (delta < 0) return 'rgba(200, 120, 120, 0.8)';
  return 'rgba(255, 255, 255, 0.45)';
}

function getDeltaArrow(delta: number): string {
  if (delta > 0) return '↑';
  if (delta < 0) return '↓';
  return '→';
}

function getMomentumColor(score: number): string {
  if (score > 0.05) return 'linear-gradient(90deg, rgba(100, 200, 150, 0.8), rgba(100, 200, 150, 0.4))';
  if (score < -0.05) return 'linear-gradient(90deg, rgba(255, 100, 100, 0.8), rgba(255, 100, 100, 0.4))';
  return 'linear-gradient(90deg, rgba(100, 150, 255, 0.6), rgba(100, 150, 255, 0.3))';
}

// =============================================================================
// BALANCE RING COMPONENT
// =============================================================================

interface BalanceRingProps {
  positiveShare: number;
  negativeShare: number;
  score: number;
}

function BalanceRing({ positiveShare, score }: BalanceRingProps) {
  const size = 56;
  const strokeWidth = 3.5;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const positiveLength = (positiveShare / 100) * circumference;
  
  const glowColor = score > 0.05 
    ? 'radial-gradient(circle, rgba(100, 200, 150, 0.25) 0%, transparent 70%)'
    : score < -0.05
    ? 'radial-gradient(circle, rgba(200, 120, 120, 0.2) 0%, transparent 70%)'
    : 'radial-gradient(circle, rgba(255, 255, 255, 0.08) 0%, transparent 70%)';

  const positiveColor = score > 0.05 
    ? 'rgba(100, 200, 150, 0.7)'
    : score < -0.05
    ? 'rgba(200, 120, 120, 0.6)'
    : 'rgba(150, 180, 200, 0.5)';

  return (
    <div style={styles.balanceRingContainer}>
      <div style={{ ...styles.balanceRingGlow, background: glowColor }} />
      <svg
        width={size}
        height={size}
        style={{ transform: 'rotate(-90deg)', position: 'relative', zIndex: 1 }}
      >
        {/* Background ring */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="rgba(255, 255, 255, 0.08)"
          strokeWidth={strokeWidth}
        />
        {/* Positive share arc */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={positiveColor}
          strokeWidth={strokeWidth}
          strokeDasharray={`${positiveLength} ${circumference}`}
          strokeLinecap="round"
          style={{ transition: 'stroke-dasharray 1s ease, stroke 0.7s ease' }}
        />
      </svg>
    </div>
  );
}

// =============================================================================
// NARRATIVE GENERATOR - Rich Interpretation System with Time Window Awareness
// =============================================================================

interface RegionMetrics {
  balanceScore: number;
  deltaBalanceScore: number;
  totalConfessions: number;
  positiveShare: number;
  negativeShare: number;
}

interface GlobalMetrics {
  avgConfessions: number;
}

// Observer Memory - session-only state for continuity tracking
interface PreviousObservation {
  region: string;
  balance: number;
  delta: number;
  timestamp: number;
}

// Generate memory continuity sentence based on previous observation
function generateMemorySentence(
  currentRegion: string,
  currentBalance: number,
  previous: PreviousObservation | null
): string {
  // No memory sentence on first observation or if region changed
  if (!previous || previous.region !== currentRegion) {
    return '';
  }

  const balanceDiff = currentBalance - previous.balance;

  if (balanceDiff > 0.015) {
    return ' Momentum strengthening compared to earlier observation.';
  }
  if (balanceDiff < -0.015) {
    return ' Momentum softening since last observation.';
  }
  if (Math.abs(balanceDiff) <= 0.01) {
    return ' Conditions remain broadly unchanged since last observation.';
  }
  // Small positive change (0.01 < diff <= 0.015)
  if (balanceDiff > 0.01) {
    return ' Momentum holding slightly stronger than earlier observation.';
  }
  // Small negative change (-0.015 <= diff < -0.01) - no sentence to avoid noise
  return '';
}

type WindowMode = 'pulse' | 'baseline'; // 7d = pulse, 30d = baseline

function getWindowMode(timeRange: string): WindowMode {
  return timeRange === '7d' ? 'pulse' : 'baseline';
}

function getWindowPreface(mode: WindowMode): string {
  return mode === 'pulse'
    ? 'Short-term signal (7d): '
    : 'Monthly baseline (30d): ';
}

// Emotional State Interpretation (same for both modes)
function interpretEmotionalState(positiveShare: number): string {
  if (positiveShare > 65) return 'strongly positive';
  if (positiveShare > 55) return 'positive';
  if (positiveShare > 48) return 'cautiously optimistic';
  if (positiveShare > 42) return 'balanced';
  if (positiveShare > 35) return 'cautiously concerned';
  return 'showing strain';
}

// Momentum Interpretation - adapted for window mode
function interpretMomentum(delta: number, mode: WindowMode): string {
  if (mode === 'pulse') {
    // 7d "Live pulse" - more sensitive to momentum, emphasizes recent changes
    if (delta > 0.05) return 'Strong positive momentum building over the last week.';
    if (delta > 0.02) return 'Recent improvement in sentiment detected.';
    if (delta > 0.005) return 'Slight upward drift observed recently.';
    if (delta > -0.005) return 'Short-term stability maintained.';
    if (delta > -0.02) return 'Mild softening noted in recent days.';
    if (delta > -0.05) return 'Recent decline in positivity observed.';
    return 'Notable short-term downturn in emotional climate.';
  } else {
    // 30d "Emotional baseline" - de-emphasizes small deltas, strategic view
    if (delta > 0.05) return 'Sustained positive trend over the last month.';
    if (delta > 0.02) return 'Gradual baseline improvement observed.';
    if (delta > 0.01) return 'Slight positive drift in monthly baseline.';
    if (delta > -0.01) return 'Baseline holding steady over the last month.';
    if (delta > -0.02) return 'Minor baseline adjustment detected.';
    if (delta > -0.05) return 'Gradual baseline shift observed.';
    return 'Significant monthly baseline change detected.';
  }
}

// Activity Level Interpretation - adapted for window mode
function interpretActivityLevel(confessions: number, globalAvg: number, mode: WindowMode): string {
  if (globalAvg === 0) return 'Insufficient baseline data.';
  
  const ratio = confessions / globalAvg;
  
  if (mode === 'pulse') {
    // 7d - emphasizes "recent" activity
    if (ratio > 1.5) return 'Recent activity significantly elevated.';
    if (ratio > 1.2) return 'Recent activity above baseline.';
    if (ratio > 0.9) return 'Activity within expected range this week.';
    if (ratio > 0.6) return 'Quieter period detected recently.';
    return 'Limited recent signal.';
  } else {
    // 30d - emphasizes "sustained" engagement
    if (ratio > 1.5) return 'Sustained high engagement levels.';
    if (ratio > 1.2) return 'Consistent activity above baseline.';
    if (ratio > 0.9) return 'Engagement within expected monthly range.';
    if (ratio > 0.6) return 'Below-average sustained activity.';
    return 'Low sustained engagement.';
  }
}

// Regional Character Flavor - adapted for window mode
function getRegionalContext(region: string, positiveShare: number, delta: number, mode: WindowMode): string {
  if (mode === 'pulse') {
    // 7d - focus on recent dynamics
    const contexts: Record<string, (pos: number, del: number) => string> = {
      'Europe': (pos, del) => {
        if (pos > 55 && del > 0) return 'Recent urban pulse shows resilience.';
        if (pos < 45) return 'This week requires monitoring.';
        return 'Short-term patterns appear stable.';
      },
      'North America': (pos, del) => {
        if (pos > 55 && del > 0) return 'Recent sentiment trending constructively.';
        if (del < -0.02) return 'Short-term shifts detected.';
        return 'Weekly indicators holding steady.';
      },
      'Asia': (pos, del) => {
        if (pos > 55) return 'Recent equilibrium favorable.';
        if (del > 0.02) return 'Emerging signals this week.';
        return 'Measured weekly landscape.';
      },
      'South America': (pos, del) => {
        if (pos > 55) return 'Recent warmth in sentiment continues.';
        if (del < -0.02) return 'Short-term mood shifts noted.';
        return 'Weekly vibrancy within bounds.';
      },
      'Africa': (pos, del) => {
        if (pos > 50 && del > 0) return 'Hopeful undertones strengthening recently.';
        if (del > 0.02) return 'Recent positive momentum.';
        return 'Weekly resilience observed.';
      },
      'Oceania': (pos, del) => {
        if (pos > 55) return 'Calm disposition maintained this week.';
        if (del < -0.02) return 'Unusual recent shifts noted.';
        return 'Tranquil weekly environment.';
      },
      'Middle East': (pos, del) => {
        if (pos > 50 && del > 0) return 'Recent optimism emerging.';
        if (del < -0.02) return 'Complex short-term dynamics.';
        return 'Nuanced weekly landscape.';
      },
    };
    return contexts[region]?.(positiveShare, delta) || 'Recent patterns under observation.';
  } else {
    // 30d - focus on baseline and sustained patterns
    const contexts: Record<string, (pos: number, del: number) => string> = {
      'Europe': (pos, del) => {
        if (pos > 55 && del > 0) return 'Monthly baseline shows sustained resilience.';
        if (pos < 45) return 'Extended monitoring recommended.';
        return 'Baseline patterns remain consistent.';
      },
      'North America': (pos, del) => {
        if (pos > 55 && del > 0) return 'Monthly trend constructive.';
        if (del < -0.02) return 'Baseline adjustment in progress.';
        return 'Long-range indicators stable.';
      },
      'Asia': (pos, del) => {
        if (pos > 55) return 'Sustained equilibrium favorable.';
        if (del > 0.02) return 'Monthly positive trend established.';
        return 'Baseline landscape measured.';
      },
      'South America': (pos, del) => {
        if (pos > 55) return 'Sustained warmth in baseline sentiment.';
        if (del < -0.02) return 'Monthly mood adjustment detected.';
        return 'Baseline vibrancy consistent.';
      },
      'Africa': (pos, del) => {
        if (pos > 50 && del > 0) return 'Sustained hopeful undertones.';
        if (del > 0.02) return 'Monthly positive momentum established.';
        return 'Baseline resilience confirmed.';
      },
      'Oceania': (pos, del) => {
        if (pos > 55) return 'Sustained calm disposition.';
        if (del < -0.02) return 'Baseline shifts worth monitoring.';
        return 'Tranquil baseline maintained.';
      },
      'Middle East': (pos, del) => {
        if (pos > 50 && del > 0) return 'Sustained cautious optimism.';
        if (del < -0.02) return 'Complex baseline dynamics.';
        return 'Nuanced baseline landscape.';
      },
    };
    return contexts[region]?.(positiveShare, delta) || 'Baseline patterns under observation.';
  }
}

// Baseline closing clause (only for 30d mode when appropriate)
function getBaselineClosing(delta: number, mode: WindowMode): string {
  if (mode === 'baseline' && Math.abs(delta) < 0.01) {
    return ' Baseline remains consistent.';
  }
  return '';
}

// Main Narrative Generator
function generateObserverNarrative(
  region: string,
  metrics: RegionMetrics,
  globalMetrics: GlobalMetrics,
  mode: WindowMode
): string {
  const emotionalState = interpretEmotionalState(metrics.positiveShare);
  const momentum = interpretMomentum(metrics.deltaBalanceScore, mode);
  const activity = interpretActivityLevel(metrics.totalConfessions, globalMetrics.avgConfessions, mode);
  const regionalContext = getRegionalContext(region, metrics.positiveShare, metrics.deltaBalanceScore, mode);
  const closing = getBaselineClosing(metrics.deltaBalanceScore, mode);

  // Compose the narrative
  return `${region} emotional climate appears ${emotionalState}. ${momentum} ${activity} ${regionalContext}${closing}`;
}

// =============================================================================
// CONFIDENCE LAYER - Credibility based on data volume and signal strength
// =============================================================================

type ConfidenceTier = 'low' | 'medium' | 'high';

interface ConfidenceResult {
  score: number; // 0..1
  tier: ConfidenceTier;
  label: string;
}

function computeConfidence(
  confessions: number | undefined | null,
  delta: number | undefined | null,
  timeRange: string
): ConfidenceResult {
  // Handle missing data gracefully
  const safeConfessions = confessions ?? 0;
  const safeDelta = delta ?? 0;

  // Time-range aware thresholds
  const thresholds = timeRange === '7d'
    ? { low: 400, high: 2000 }
    : { low: 1500, high: 7000 };

  // Volume score (saturating)
  const volumeScore = Math.min(safeConfessions / thresholds.high, 1);

  // Signal strength modifier (how decisive is the change)
  const signalStrength = Math.min(Math.abs(safeDelta) / 0.05, 1);

  // Combined score: 80% volume, 20% signal
  const score = Math.min(Math.max(0.8 * volumeScore + 0.2 * signalStrength, 0), 1);

  // Determine tier
  let tier: ConfidenceTier;
  if (score < 0.4) {
    tier = 'low';
  } else if (score < 0.75) {
    tier = 'medium';
  } else {
    tier = 'high';
  }

  // Labels
  const labels: Record<ConfidenceTier, string> = {
    low: 'Low confidence',
    medium: 'Medium confidence',
    high: 'High confidence',
  };

  return { score, tier, label: labels[tier] };
}

// Tone adaptation based on confidence
function applyConfidenceTone(
  text: string,
  tier: ConfidenceTier,
  _timeRange: string // reserved for future use
): string {
  if (tier === 'low') {
    // Add hedging and caution for low confidence
    let result = text
      .replace(/\bstrongly positive\b/gi, 'tentatively positive')
      .replace(/\bstrongly\b/gi, 'possibly')
      .replace(/\bsignificantly\b/gi, 'potentially')
      .replace(/\bnotable\b/gi, 'early')
      .replace(/\bsustained\b/gi, 'apparent')
      .replace(/\bclear pattern\b/gi, 'emerging pattern')
      .replace(/\bshows\b/gi, 'may show')
      .replace(/\bindicates\b/gi, 'suggests');
    
    // Append caution note
    result += ' (Limited sample size for this window.)';
    return result;
  }

  if (tier === 'high') {
    // More decisive phrasing for high confidence
    let result = text
      .replace(/\bappears\b/gi, 'shows')
      .replace(/\bmay show\b/gi, 'shows')
      .replace(/\bsuggests\b/gi, 'indicates')
      .replace(/\bpossibly\b/gi, 'clearly')
      .replace(/\btentatively\b/gi, 'solidly')
      .replace(/\bemerging pattern\b/gi, 'established pattern');
    
    // Append confidence note
    result += ' (Robust sample for this window.)';
    return result;
  }

  // Medium confidence: neutral, no changes
  return text;
}

// Wrapper function with time range parameter and memory support
function generateNarrative(
  region: string,
  score: number,
  delta: number,
  confessions: number,
  positiveShare: number = 50,
  negativeShare: number = 30,
  globalAvgConfessions: number = confessions,
  timeRange: string = '7d',
  memorySentence: string = '',
  confidenceTier: ConfidenceTier = 'medium'
): string {
  const mode = getWindowMode(timeRange);
  const preface = getWindowPreface(mode);
  const baseNarrative = generateObserverNarrative(
    region,
    {
      balanceScore: score,
      deltaBalanceScore: delta,
      totalConfessions: confessions,
      positiveShare,
      negativeShare,
    },
    { avgConfessions: globalAvgConfessions },
    mode
  );
  
  // Apply confidence-based tone adjustments
  const tonedNarrative = applyConfidenceTone(preface + baseNarrative, confidenceTier, timeRange);
  
  return tonedNarrative + memorySentence;
}

// =============================================================================
// INSIGHT GENERATORS
// =============================================================================

interface InsightData {
  emotionalDirection: { arrow: string; text: string; sentiment: 'positive' | 'negative' | 'neutral' };
  activitySignal: { text: string; level: 'high' | 'normal' | 'low' };
  notableArea: { flag: string; name: string; insight: string } | null;
}

const REGION_NOTABLE_COUNTRIES: Record<string, { flag: string; name: string }[]> = {
  'Europe': [
    { flag: '🇩🇪', name: 'Germany' },
    { flag: '🇫🇷', name: 'France' },
    { flag: '🇬🇧', name: 'United Kingdom' },
    { flag: '🇪🇸', name: 'Spain' },
    { flag: '🇮🇹', name: 'Italy' },
    { flag: '🇳🇱', name: 'Netherlands' },
  ],
  'North America': [
    { flag: '🇺🇸', name: 'United States' },
    { flag: '🇨🇦', name: 'Canada' },
    { flag: '🇲🇽', name: 'Mexico' },
  ],
  'Asia': [
    { flag: '🇯🇵', name: 'Japan' },
    { flag: '🇰🇷', name: 'South Korea' },
    { flag: '🇮🇳', name: 'India' },
    { flag: '🇨🇳', name: 'China' },
    { flag: '🇸🇬', name: 'Singapore' },
  ],
  'South America': [
    { flag: '🇧🇷', name: 'Brazil' },
    { flag: '🇦🇷', name: 'Argentina' },
    { flag: '🇨🇴', name: 'Colombia' },
    { flag: '🇨🇱', name: 'Chile' },
  ],
  'Africa': [
    { flag: '🇿🇦', name: 'South Africa' },
    { flag: '🇳🇬', name: 'Nigeria' },
    { flag: '🇰🇪', name: 'Kenya' },
    { flag: '🇪🇬', name: 'Egypt' },
  ],
  'Oceania': [
    { flag: '🇦🇺', name: 'Australia' },
    { flag: '🇳🇿', name: 'New Zealand' },
  ],
  'Middle East': [
    { flag: '🇦🇪', name: 'UAE' },
    { flag: '🇸🇦', name: 'Saudi Arabia' },
    { flag: '🇮🇱', name: 'Israel' },
    { flag: '🇹🇷', name: 'Turkey' },
  ],
};

function generateInsights(
  region: string,
  score: number,
  delta: number,
  confessions: number,
  globalAvgConfessions: number
): InsightData {
  // 1) Emotional Direction
  let emotionalDirection: InsightData['emotionalDirection'];
  if (delta > 0.05) {
    emotionalDirection = { arrow: '↑', text: 'Positive momentum accelerating', sentiment: 'positive' };
  } else if (delta > 0.02) {
    emotionalDirection = { arrow: '↑', text: 'Gradual positive shift detected', sentiment: 'positive' };
  } else if (delta < -0.05) {
    emotionalDirection = { arrow: '↓', text: 'Negative sentiment increasing', sentiment: 'negative' };
  } else if (delta < -0.02) {
    emotionalDirection = { arrow: '↓', text: 'Slight downturn in sentiment', sentiment: 'negative' };
  } else {
    emotionalDirection = { arrow: '↔', text: 'Emotional balance stabilizing', sentiment: 'neutral' };
  }

  // 2) Activity Signal
  let activitySignal: InsightData['activitySignal'];
  const activityRatio = globalAvgConfessions > 0 ? confessions / globalAvgConfessions : 1;
  if (activityRatio > 1.3) {
    activitySignal = { text: 'Above global baseline', level: 'high' };
  } else if (activityRatio < 0.7) {
    activitySignal = { text: 'Quiet period detected', level: 'low' };
  } else {
    activitySignal = { text: 'Normal range', level: 'normal' };
  }

  // 3) Notable Area
  const countries = REGION_NOTABLE_COUNTRIES[region];
  let notableArea: InsightData['notableArea'] = null;
  
  if (countries && countries.length > 0) {
    const randomIndex = Math.floor(Math.abs(score * 100 + delta * 1000) % countries.length);
    const country = countries[randomIndex];
    
    let insight: string;
    if (score > 0.05 && delta > 0.02) {
      insight = 'showing strongest uplift';
    } else if (score > 0.05) {
      insight = 'maintaining positive trend';
    } else if (score < -0.05 && delta < -0.02) {
      insight = 'indicating emerging concern';
    } else if (score < -0.05) {
      insight = 'under observation';
    } else if (delta > 0.02) {
      insight = 'showing improvement';
    } else if (delta < -0.02) {
      insight = 'slight decline noted';
    } else {
      insight = 'stable conditions';
    }
    
    notableArea = { flag: country.flag, name: country.name, insight };
  }

  return { emotionalDirection, activitySignal, notableArea };
}

// =============================================================================
// COMPONENT
// =============================================================================

export function MoodPage() {
  const [timeRange, setTimeRange] = useState('7d');
  const [observerIndex, setObserverIndex] = useState(0);
  const [fadeIn, setFadeIn] = useState(true);
  const [secondsAgo, setSecondsAgo] = useState(0);
  const [referenceTime, setReferenceTime] = useState<{ time: string; label: string }>({ time: '--:--', label: '' });
  const [showTimeHint, setShowTimeHint] = useState(false);

  // Focus transition state
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [transitionTarget, setTransitionTarget] = useState<string | null>(null);
  const prefersReducedMotion = useRef(
    typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  );

  // Observer Memory - tracks previous observation for continuity sentences
  const previousObservationRef = useRef<PreviousObservation | null>(null);

  const { data: moodData, loading: moodLoading, error: moodError, refetch: refetchMood } = useMoodSummary(
    timeRange,
    null,
    null,
    null
  );

  const { data: regionData, loading: regionLoading, error: regionError, refetch: refetchRegion } = useMoodPulseByRegion(
    timeRange
  );

  const handleRefresh = useCallback(() => {
    refetchMood();
    refetchRegion();
  }, [refetchMood, refetchRegion]);

  // Current observed region
  const observedRegion = OBSERVER_REGIONS[observerIndex];

  // Get data for observed region
  const observedData = useMemo(() => {
    return regionData.find(r => r.region === observedRegion) || null;
  }, [regionData, observedRegion]);

  // Generate memory continuity sentence (comparing with previous observation)
  const memorySentence = useMemo(() => {
    if (!observedData) return '';
    return generateMemorySentence(
      observedRegion,
      observedData.balanceScore,
      previousObservationRef.current
    );
  }, [observedRegion, observedData]);

  // Update observer memory after each observation renders
  useEffect(() => {
    if (observedData && fadeIn) {
      // Small delay to ensure the current narrative uses the previous memory
      const timeout = setTimeout(() => {
        previousObservationRef.current = {
          region: observedRegion,
          balance: observedData.balanceScore,
          delta: observedData.deltaBalanceScore,
          timestamp: Date.now(),
        };
      }, 100);
      return () => clearTimeout(timeout);
    }
  }, [observedRegion, observedData, fadeIn]);

  // Reset memory when region changes
  useEffect(() => {
    // Clear memory on region change (new region = fresh start)
    previousObservationRef.current = null;
  }, [observerIndex]);

  // Region rotation effect with focus transition
  useEffect(() => {
    const interval = setInterval(() => {
      // Calculate next region for transition message
      const nextIndex = (observerIndex + 1) % OBSERVER_REGIONS.length;
      const nextRegion = OBSERVER_REGIONS[nextIndex];
      
      // Start transition - show "Switching focus..." message
      setIsTransitioning(true);
      setTransitionTarget(nextRegion);
      
      // Begin fade out
      setFadeIn(false);
      
      // After fade duration, switch content
      setTimeout(() => {
        setObserverIndex(nextIndex);
        setFadeIn(true);
        setSecondsAgo(0);
        
        // End transition after new content fades in
        setTimeout(() => {
          setIsTransitioning(false);
          setTransitionTarget(null);
        }, prefersReducedMotion.current ? 100 : 300);
      }, prefersReducedMotion.current ? 100 : FADE_DURATION);
    }, ROTATION_INTERVAL);

    return () => clearInterval(interval);
  }, [observerIndex]);

  // Seconds counter - increments every second
  useEffect(() => {
    const interval = setInterval(() => {
      setSecondsAgo(prev => prev + 1);
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  // Reference time updater - updates every minute and on region change
  useEffect(() => {
    setReferenceTime(getRegionReferenceTime(observedRegion));
    
    const interval = setInterval(() => {
      setReferenceTime(getRegionReferenceTime(observedRegion));
    }, 60000);

    return () => clearInterval(interval);
  }, [observedRegion]);

  // Filter region data (exclude Unknown)
  const filteredRegionData = useMemo(() => {
    return regionData.filter(r => r.region !== 'Unknown');
  }, [regionData]);

  // Calculate global average confessions for activity comparison
  const globalAvgConfessions = useMemo(() => {
    if (filteredRegionData.length === 0) return 0;
    const total = filteredRegionData.reduce((sum, r) => sum + r.totalConfessions, 0);
    return total / filteredRegionData.length;
  }, [filteredRegionData]);

  // Generate insights for observed region
  const insights = useMemo(() => {
    if (!observedData) return null;
    return generateInsights(
      observedRegion,
      observedData.balanceScore,
      observedData.deltaBalanceScore,
      observedData.totalConfessions,
      globalAvgConfessions
    );
  }, [observedRegion, observedData, globalAvgConfessions]);

  // Compute confidence for current observation
  const confidence = useMemo(() => {
    if (!observedData) {
      return { score: 0, tier: 'low' as ConfidenceTier, label: 'Low confidence' };
    }
    return computeConfidence(
      observedData.totalConfessions,
      observedData.deltaBalanceScore,
      timeRange
    );
  }, [observedData, timeRange]);

  // Debug logging (development only)
  useEffect(() => {
    if (process.env.NODE_ENV === 'development' && observedData) {
      console.log('[AI Observer Confidence]', {
        region: observedRegion,
        timeRange,
        confessions: observedData.totalConfessions,
        delta: observedData.deltaBalanceScore,
        confidenceScore: confidence.score.toFixed(3),
        tier: confidence.tier,
      });
    }
  }, [observedRegion, timeRange, observedData, confidence]);

  const totalConfessions = moodData.reduce((sum, item) => sum + item.total_count, 0);
  const error = moodError || regionError;

  const momentumPercent = observedData 
    ? Math.min(100, Math.max(0, (observedData.balanceScore + 1) * 50))
    : 50;

  return (
    <div style={styles.container}>
      {/* Filter Row */}
      <div style={styles.filterRow}>
        <div style={styles.filterGroup}>
          <span style={styles.filterLabel}>Time</span>
          <select
            style={styles.filterSelect}
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value)}
          >
            {TIME_RANGE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>

        <button style={styles.refreshBtn} onClick={handleRefresh}>
          Refresh
        </button>
      </div>

      {error && (
        <div style={styles.errorState}>{error}</div>
      )}

      {/* Hero Section: Narrative + Map */}
      <div style={styles.heroSection}>
        {/* LEFT: AI Observer Narrative */}
        <div style={styles.narrativePanel}>
          <div style={styles.narrativeDivider} />

          <div style={styles.narrativeHeader}>
            <div style={styles.narrativeTitle}>AI Observer</div>
            <InfoHint {...moodInfo.aiObserver} />
          </div>
          
          {/* Live Status */}
          <style>
            {`
              @keyframes observerPulse {
                0%, 100% { opacity: 0.4; }
                50% { opacity: 0.9; }
              }
              @keyframes focusPulse {
                0%, 100% { opacity: 0.5; transform: scale(1); }
                50% { opacity: 1; transform: scale(1.2); }
              }
            `}
          </style>
          <div style={styles.liveStatus}>
            <div style={styles.liveStatusLine}>
              <div style={styles.liveDot} />
              <span style={styles.liveLabel}>LIVE</span>
              <span style={styles.liveText}>— scanning global emotional signals</span>
              <span
                style={{
                  ...styles.confidenceBadge,
                  ...(confidence.tier === 'low' ? styles.confidenceLow :
                      confidence.tier === 'medium' ? styles.confidenceMedium :
                      styles.confidenceHigh),
                }}
                title="Based on sample size and signal strength for the selected time window."
              >
                {confidence.label}
              </span>
              <span style={styles.headerMetaRight}>
                Watching <span style={styles.headerMetaSeparator}>•</span> Updated {secondsAgo}s ago
              </span>
            </div>
            <div style={styles.observerStatusLine}>
              <div style={styles.observerPulseDot} />
              <span style={styles.observerStatusText}>
                Global sweep active • Monitoring {MONITORED_REGION_COUNT} regions • Updated continuously
              </span>
            </div>
          </div>

          {/* Focus Transition Message */}
          <div style={{
            ...styles.focusTransitionLine,
            ...(isTransitioning && transitionTarget ? styles.focusTransitionLineVisible : {}),
          }}>
            {isTransitioning && transitionTarget && (
              <>
                <div style={styles.focusTransitionDot} />
                <span>Switching focus to {transitionTarget}…</span>
              </>
            )}
          </div>

          {regionLoading ? (
            <div style={styles.loadingState}>Analyzing regions...</div>
          ) : (
            <div style={{
              ...styles.narrativeContent,
              opacity: fadeIn ? 1 : (prefersReducedMotion.current ? 0 : 0.5),
              transition: prefersReducedMotion.current ? 'none' : 'opacity 0.7s ease-in-out',
            }}>
              {observedData ? (
                <>
                  <div style={styles.narrativeScoreSection}>
                    {/* Balance Ring */}
                    <BalanceRing
                      positiveShare={observedData.positiveShare}
                      negativeShare={observedData.negativeShare}
                      score={observedData.balanceScore}
                    />
                    
                    {/* Score Content */}
                    <div style={styles.narrativeScoreContent}>
                      <div style={{
                        ...styles.narrativeScoreGlow,
                        background: getScoreGlow(observedData.balanceScore),
                      }} />
                      
                      {/* Hero Region Label */}
                      <div style={styles.regionHeroLabel}>{observedRegion}</div>
                      
                      {/* Reference Time with Hint */}
                      <div style={styles.referenceTimeContainer}>
                        <span style={styles.referenceTimeText}>
                          Reference time: {referenceTime.time}
                        </span>
                        {referenceTime.label && (
                          <span style={styles.referenceTimeZone}>{referenceTime.label}</span>
                        )}
                        <span 
                          style={styles.referenceTimeHint}
                          onMouseEnter={() => setShowTimeHint(true)}
                          onMouseLeave={() => setShowTimeHint(false)}
                        >
                          ?
                        </span>
                        {showTimeHint && (
                          <div style={styles.referenceTimeTooltip}>
                            Anchor timezone for the region (spans multiple time zones)
                          </div>
                        )}
                      </div>
                      
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <div style={{
                          ...styles.narrativeScore,
                          color: getScoreColor(observedData.balanceScore),
                          textShadow: observedData.balanceScore > 0.05 
                            ? '0 0 40px rgba(100, 200, 150, 0.3)' 
                            : observedData.balanceScore < -0.05 
                            ? '0 0 40px rgba(200, 120, 120, 0.25)' 
                            : 'none',
                        }}>
                          {observedData.balanceScore >= 0 ? '+' : ''}{observedData.balanceScore.toFixed(2)}
                        </div>
                        <InfoHint {...moodInfo.temperatureIndex} />
                      </div>
                    </div>
                  </div>

                  <div style={{
                    ...styles.narrativeDelta,
                    color: getDeltaColor(observedData.deltaBalanceScore),
                  }}>
                    <span style={styles.narrativeDeltaArrow}>{getDeltaArrow(observedData.deltaBalanceScore)}</span>
                    {Math.abs(observedData.deltaBalanceScore).toFixed(2)} vs previous
                  </div>

                  <div style={styles.narrativeAiLabel}>
                    <div style={styles.narrativeAiDot} />
                    AI Observation
                  </div>
                  <div style={styles.narrativeDescription}>
                    {generateNarrative(
                      observedRegion,
                      observedData.balanceScore,
                      observedData.deltaBalanceScore,
                      observedData.totalConfessions,
                      observedData.positiveShare,
                      observedData.negativeShare,
                      globalAvgConfessions,
                      timeRange,
                      memorySentence,
                      confidence.tier
                    )}
                  </div>

                  {/* Observer Insights */}
                  {insights && (
                    <div style={styles.insightsSection}>
                      {/* Emotional Direction */}
                      <div style={styles.insightLine}>
                        <span style={{
                          ...styles.insightArrow,
                          ...(insights.emotionalDirection.sentiment === 'positive' ? styles.insightPositive :
                              insights.emotionalDirection.sentiment === 'negative' ? styles.insightNegative :
                              styles.insightNeutral),
                        }}>
                          {insights.emotionalDirection.arrow}
                        </span>
                        <span style={insights.emotionalDirection.sentiment === 'positive' ? styles.insightPositive :
                                     insights.emotionalDirection.sentiment === 'negative' ? styles.insightNegative :
                                     styles.insightValue}>
                          {insights.emotionalDirection.text}
                        </span>
                      </div>

                      {/* Activity Signal */}
                      <div style={styles.insightLine}>
                        <span style={styles.insightLabel}>Activity:</span>
                        <span style={insights.activitySignal.level === 'high' ? styles.insightPositive :
                                     insights.activitySignal.level === 'low' ? styles.insightNeutral :
                                     styles.insightValue}>
                          {insights.activitySignal.text}
                        </span>
                      </div>

                      {/* Notable Area */}
                      {insights.notableArea && (
                        <div style={styles.insightLine}>
                          <span style={styles.insightLabel}>Notable:</span>
                          <span style={styles.insightValue}>
                            {insights.notableArea.flag} {insights.notableArea.name} {insights.notableArea.insight}
                          </span>
                        </div>
                      )}
                    </div>
                  )}

                  <div style={styles.narrativeStats}>
                    <div style={styles.narrativeStat}>
                      <span style={styles.narrativeStatLabel}>Positive</span>
                      <span style={{ ...styles.narrativeStatValue, color: 'rgba(100, 200, 150, 0.85)' }}>
                        {observedData.positiveShare.toFixed(0)}%
                      </span>
                    </div>
                    <div style={styles.narrativeStat}>
                      <span style={styles.narrativeStatLabel}>Negative</span>
                      <span style={{ ...styles.narrativeStatValue, color: 'rgba(200, 120, 120, 0.85)' }}>
                        {observedData.negativeShare.toFixed(0)}%
                      </span>
                    </div>
                  </div>
                </>
              ) : (
                <div style={styles.emptyState}>No data for {observedRegion}</div>
              )}
            </div>
          )}
        </div>

        {/* RIGHT: Hero Map */}
        <div style={styles.mapPanel}>
          <div style={{ ...styles.mapLabel, right: 16, justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'inherit' }}>
              <div style={styles.mapLabelDot} />
              Live Emotional Map
            </div>
            <InfoHint {...moodInfo.liveMap} />
          </div>
          <MoodWorldMap
            regions={filteredRegionData}
            observedRegion={observedRegion}
            onSelectRegion={() => {}}
            loading={regionLoading}
          />
        </div>
      </div>

      {/* Bottom Section: Three Cards */}
      <div style={styles.bottomSection}>
        {/* Card 1: Emotional Momentum */}
        <div style={styles.card}>
          <div style={styles.cardHeader}>
            <span style={styles.cardTitle}>Emotional Momentum</span>
            <span style={styles.cardBadge}>{observedRegion}</span>
          </div>
          {regionLoading ? (
            <div style={styles.loadingState}>Loading...</div>
          ) : observedData ? (
            <>
              <div style={{
                ...styles.momentumValue,
                color: getScoreColor(observedData.balanceScore),
              }}>
                {observedData.balanceScore >= 0 ? '+' : ''}{observedData.balanceScore.toFixed(2)}
              </div>
              <div style={styles.momentumLabel}>
                Regional sentiment balance
              </div>
              <div style={styles.momentumBar}>
                <div style={{
                  ...styles.momentumBarFill,
                  width: `${momentumPercent}%`,
                  background: getMomentumColor(observedData.balanceScore),
                }} />
              </div>
            </>
          ) : (
            <div style={styles.emptyState}>No data</div>
          )}
        </div>

        {/* Card 2: Stability Index */}
        <div style={styles.card}>
          <div style={styles.cardHeader}>
            <span style={styles.cardTitle}>Stability Index</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <InfoHint {...moodInfo.stabilityIndex} />
              <span style={styles.cardBadge}>{timeRange === '7d' ? '7 Days' : '30 Days'}</span>
            </div>
          </div>
          {regionLoading ? (
            <div style={styles.loadingState}>Loading...</div>
          ) : observedData ? (
            <div style={styles.stabilityGrid}>
              <div style={styles.stabilityItem}>
                <span style={styles.stabilityItemLabel}>Positive Share</span>
                <span style={{ ...styles.stabilityItemValue, color: 'rgba(100, 200, 150, 0.9)' }}>
                  {observedData.positiveShare.toFixed(0)}%
                </span>
              </div>
              <div style={styles.stabilityItem}>
                <span style={styles.stabilityItemLabel}>Negative Share</span>
                <span style={{ ...styles.stabilityItemValue, color: 'rgba(255, 100, 100, 0.9)' }}>
                  {observedData.negativeShare.toFixed(0)}%
                </span>
              </div>
              <div style={styles.stabilityItem}>
                <span style={styles.stabilityItemLabel}>Confessions</span>
                <span style={styles.stabilityItemValue}>
                  {observedData.totalConfessions.toLocaleString()}
                </span>
              </div>
              <div style={styles.stabilityItem}>
                <span style={styles.stabilityItemLabel}>Change</span>
                <span style={{
                  ...styles.stabilityItemValue,
                  color: getDeltaColor(observedData.deltaBalanceScore),
                }}>
                  {getDeltaArrow(observedData.deltaBalanceScore)} {Math.abs(observedData.deltaBalanceScore).toFixed(2)}
                </span>
              </div>
            </div>
          ) : (
            <div style={styles.emptyState}>No data</div>
          )}
        </div>

        {/* Card 3: Top Movers */}
        <div style={styles.card}>
          <div style={styles.cardHeader}>
            <span style={styles.cardTitle}>Top Movers</span>
            <span style={styles.cardBadge}>{totalConfessions.toLocaleString()} total</span>
          </div>
          {moodLoading ? (
            <div style={styles.loadingState}>Loading...</div>
          ) : moodData.length === 0 ? (
            <div style={styles.emptyState}>No mood data</div>
          ) : (
            <div style={styles.moversList}>
              {moodData.slice(0, 4).map((item) => {
                const display = getMoodDisplay(item.mood_bucket);
                const isPositive = ['joy', 'love', 'calm', 'hope', 'gratitude', 'confidence'].includes(item.mood_bucket);
                return (
                  <div key={item.mood_bucket} style={styles.moverRow}>
                    <div style={styles.moverLeft}>
                      <span style={styles.moverEmoji}>{display.emoji}</span>
                      <span style={styles.moverName}>{display.label}</span>
                    </div>
                    <span style={{
                      ...styles.moverValue,
                      color: isPositive ? 'rgba(100, 200, 150, 0.9)' : 'rgba(255, 100, 100, 0.9)',
                    }}>
                      {item.total_count.toLocaleString()}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
