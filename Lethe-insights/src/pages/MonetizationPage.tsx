import { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import { useEngagementFlow } from '../hooks/useEngagementFlow';
import { useTopEarningCountries, type CountryRevenueData } from '../hooks/useTopEarningCountries';
import { useRevenueGeo } from '../hooks/useRevenueGeo';
import { useMoodPulse } from '../hooks/useMoodPulse';
import { RevenueMapPhase1 } from '../components/monetization/RevenueMapPhase1';
import { useFiltersCore, FilterBarCore, toLegacyFilters } from '../engine/filters_core';
import { analyzeRevenueDrivers } from '../utils/revenueDrivers';
import { buildRevenueInsightLanguage } from '../engine/insights/revenueInsightLanguage';
import { buildRevenueMoodCorrelation } from '../engine/insights/revenueMoodCorrelation';
import { buildRevenueNarrative } from '../engine/insights/revenueNarrative';
import { DeltaBadge, percentDelta } from '../components/analytics/DeltaBadge';

// =============================================================================
// LAYOUT CONSTANTS
// =============================================================================

const HEADER_OFFSET = 56; // Accounts for app navigation bar

// =============================================================================
// SECTION HEADER - Visual analysis chapter markers
// =============================================================================

interface SectionHeaderProps {
  title: string;
  subtitle?: string;
}

function SectionHeader({ title, subtitle }: SectionHeaderProps) {
  return (
    <div style={sectionHeaderStyles.container}>
      <div style={sectionHeaderStyles.labelRow}>
        <span style={sectionHeaderStyles.label}>{title}</span>
        <div style={sectionHeaderStyles.divider} />
      </div>
      {subtitle && <p style={sectionHeaderStyles.subtitle}>{subtitle}</p>}
    </div>
  );
}

const sectionHeaderStyles = {
  container: {
    marginTop: '32px',
    marginBottom: '16px',
  } as React.CSSProperties,
  labelRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  } as React.CSSProperties,
  label: {
    fontSize: '12px',
    fontWeight: 500,
    letterSpacing: '0.12em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.7)',
    whiteSpace: 'nowrap' as const,
  } as React.CSSProperties,
  divider: {
    flex: 1,
    height: '1px',
    background: 'linear-gradient(90deg, rgba(255, 255, 255, 0.15) 0%, rgba(255, 255, 255, 0) 100%)',
  } as React.CSSProperties,
  subtitle: {
    margin: '4px 0 0 0',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,
};

// =============================================================================
// RESPONSIVE HOOK - Detect desktop mode (for 2-column layout)
// =============================================================================

function useIsDesktop(): boolean {
  const [isDesktop, setIsDesktop] = useState(() => 
    typeof window !== 'undefined' && window.innerWidth >= 1100
  );

  useEffect(() => {
    const check = () => {
      setIsDesktop(window.innerWidth >= 1100);
    };
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  return isDesktop;
}

// =============================================================================
// STYLES - Revenue Command Center (Natural Scroll Layout)
// =============================================================================

const styles = {
  // ==========================================================================
  // PAGE CONTAINER - Natural scroll (not viewport-locked)
  // ==========================================================================
  page: {
    padding: '16px 28px 40px',
    minHeight: '100vh',
    background: 'linear-gradient(180deg, rgba(12, 12, 18, 0.95) 0%, rgba(8, 8, 12, 1) 100%)',
  } as React.CSSProperties,

  // Filter row (sticky version for Phase 8)
  filterRowSticky: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    marginBottom: 16,
    flexWrap: 'wrap' as const,
    position: 'sticky' as const,
    top: 0,
    zIndex: 100,
    background: 'linear-gradient(180deg, rgba(12, 12, 18, 0.98) 0%, rgba(12, 12, 18, 0.95) 100%)',
    backdropFilter: 'blur(12px)',
    padding: '16px 0',
    marginLeft: -24,
    marginRight: -24,
    paddingLeft: 24,
    paddingRight: 24,
    borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
  } as React.CSSProperties,

  // Legacy filter row (non-sticky)
  filterRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    marginBottom: 16,
    flexWrap: 'wrap' as const,
  } as React.CSSProperties,

  titleSection: {
    display: 'flex',
    alignItems: 'baseline',
    gap: '12px',
    marginRight: 'auto',
  } as React.CSSProperties,

  title: {
    margin: 0,
    fontSize: '14px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.7)',
    letterSpacing: '-0.01em',
  } as React.CSSProperties,

  subtitle: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  compareContext: {
    fontSize: '11px',
    color: 'rgba(100, 200, 150, 0.7)',
    marginTop: '3px',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  } as React.CSSProperties,

  // ==========================================================================
  // TOP ROW - KPI Card + Top Countries (2-column grid)
  // ==========================================================================
  topRow: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '16px',
    marginBottom: '16px',
  } as React.CSSProperties,

  topRowStacked: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '16px',
    marginBottom: '16px',
  } as React.CSSProperties,

  // ==========================================================================
  // MAIN ROW - Insights stack (left) + Sticky Map (right)
  // ==========================================================================
  mainRow: {
    display: 'grid',
    gridTemplateColumns: '1fr 1.2fr',
    gap: '16px',
    alignItems: 'start',
  } as React.CSSProperties,

  mainRowStacked: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '16px',
  } as React.CSSProperties,

  // Left column - natural stack of cards
  // Spacing scale: section gap 32px, card gap 16px
  insightsColumn: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '16px',
  } as React.CSSProperties,

  // Right column - sticky map
  // ROOT CAUSE: Sticky works relative to contentPlain (scroll container in InsightsLayout).
  // Key requirements: alignSelf: 'start' prevents grid stretch, zIndex ensures visibility.
  mapColumn: {
    position: 'sticky' as const,
    top: '16px',
    alignSelf: 'start',
    zIndex: 10,
    height: `calc(100vh - ${HEADER_OFFSET + 100}px)`,
    minHeight: '400px',
    maxHeight: '800px',
  } as React.CSSProperties,

  mapColumnStacked: {
    height: '450px',
    minHeight: '400px',
  } as React.CSSProperties,

  // ==========================================================================
  // HERO CARD - Primary Revenue Display (Mood-like panel)
  // ==========================================================================
  heroCard: {
    padding: '18px 20px',
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    border: '1px solid rgba(100, 200, 150, 0.15)',
    borderRadius: '12px',
    flexShrink: 0,
    position: 'relative' as const,
    overflow: 'hidden',
    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(100, 200, 150, 0.05)',
  } as React.CSSProperties,

  heroGlow: {
    position: 'absolute' as const,
    top: '-30%',
    right: '-10%',
    width: '180px',
    height: '180px',
    background: 'radial-gradient(circle, rgba(100, 200, 150, 0.12) 0%, transparent 70%)',
    pointerEvents: 'none' as const,
  } as React.CSSProperties,

  heroLabel: {
    margin: '0 0 4px 0',
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.12em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  heroValue: {
    margin: 0,
    fontSize: '36px',
    fontWeight: 700,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(100, 220, 160, 1)',
    letterSpacing: '-0.02em',
    textShadow: '0 0 40px rgba(100, 200, 150, 0.3)',
  } as React.CSSProperties,

  heroValueRow: {
    display: 'flex',
    alignItems: 'baseline',
    gap: '10px',
    marginBottom: '16px',
  } as React.CSSProperties,

  heroSecondary: {
    display: 'flex',
    gap: '24px',
    marginBottom: '12px',
  } as React.CSSProperties,

  heroKpi: {
    display: 'flex',
    flexDirection: 'column' as const,
  } as React.CSSProperties,

  heroKpiLabel: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.4)',
    marginBottom: '2px',
  } as React.CSSProperties,

  heroKpiValue: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
    fontVariantNumeric: 'tabular-nums',
  } as React.CSSProperties,

  heroKpiValueRow: {
    display: 'flex',
    alignItems: 'baseline',
    gap: '6px',
  } as React.CSSProperties,

  heroInsight: {
    padding: '10px 12px',
    background: 'rgba(0, 0, 0, 0.2)',
    borderRadius: '8px',
    fontSize: '12px',
    color: 'rgba(255, 255, 255, 0.7)',
    lineHeight: 1.4,
  } as React.CSSProperties,

  heroInsightLabel: {
    color: 'rgba(255, 200, 100, 0.9)',
    fontWeight: 500,
  } as React.CSSProperties,

  // ==========================================================================
  // COLLAPSIBLE ASSUMPTIONS PANEL
  // ==========================================================================
  assumptionsPanel: {
    padding: '14px 16px',
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
    flexShrink: 0,
    boxShadow: '0 4px 16px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(255, 255, 255, 0.03)',
  } as React.CSSProperties,

  assumptionsHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    cursor: 'pointer',
    userSelect: 'none' as const,
  } as React.CSSProperties,

  assumptionsTitle: {
    margin: 0,
    fontSize: '10px',
    fontWeight: 550,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.6)',
  } as React.CSSProperties,

  assumptionsSummary: {
    display: 'flex',
    gap: '16px',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  assumptionsBadge: {
    padding: '2px 8px',
    background: 'rgba(255, 255, 255, 0.06)',
    borderRadius: '4px',
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.7)',
  } as React.CSSProperties,

  assumptionsToggle: {
    padding: '4px 8px',
    background: 'transparent',
    border: 'none',
    color: 'rgba(255, 255, 255, 0.4)',
    fontSize: '10px',
    cursor: 'pointer',
  } as React.CSSProperties,

  assumptionsBody: {
    marginTop: '12px',
    paddingTop: '12px',
    borderTop: '1px solid rgba(255, 255, 255, 0.06)',
  } as React.CSSProperties,

  inputGroup: {
    marginBottom: '8px',
  } as React.CSSProperties,

  inputLabel: {
    display: 'block',
    marginBottom: '4px',
    fontSize: '11px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.45)',
  } as React.CSSProperties,

  inputRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
  } as React.CSSProperties,

  slider: {
    flex: 1,
    height: '3px',
    WebkitAppearance: 'none' as const,
    appearance: 'none' as const,
    background: 'rgba(255, 255, 255, 0.12)',
    borderRadius: '2px',
    outline: 'none',
    cursor: 'pointer',
  } as React.CSSProperties,

  numberInput: {
    width: '60px',
    padding: '4px 8px',
    fontSize: '11px',
    background: 'rgba(255, 255, 255, 0.05)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '4px',
    color: 'rgba(255, 255, 255, 0.85)',
    outline: 'none',
    textAlign: 'right' as const,
  } as React.CSSProperties,

  select: {
    padding: '4px 8px',
    fontSize: '11px',
    background: 'rgba(255, 255, 255, 0.05)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '4px',
    color: 'rgba(255, 255, 255, 0.85)',
    outline: 'none',
    cursor: 'pointer',
  } as React.CSSProperties,

  // ==========================================================================
  // COUNTRIES TABLE - Enhanced
  // ==========================================================================
  countriesCard: {
    padding: '16px 18px',
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
    display: 'flex',
    flexDirection: 'column' as const,
    maxHeight: '320px',
    overflow: 'hidden',
    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.03)',
  } as React.CSSProperties,

  cardTitle: {
    margin: '0 0 10px 0',
    fontSize: '10px',
    fontWeight: 550,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.6)',
  } as React.CSSProperties,

  tableWrapper: {
    flex: 1,
    minHeight: 0,
    overflowY: 'auto' as const,
  } as React.CSSProperties,

  countryRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    padding: '8px 0',
    borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
  } as React.CSSProperties,

  countryRank: {
    width: '18px',
    height: '18px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '10px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.4)',
    background: 'rgba(255, 255, 255, 0.05)',
    borderRadius: '4px',
    flexShrink: 0,
  } as React.CSSProperties,

  countryRankTop: {
    width: '18px',
    height: '18px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '10px',
    fontWeight: 600,
    color: 'rgba(100, 200, 150, 1)',
    background: 'rgba(100, 200, 150, 0.15)',
    borderRadius: '4px',
    flexShrink: 0,
  } as React.CSSProperties,

  countryInfo: {
    flex: 1,
    minWidth: 0,
  } as React.CSSProperties,

  countryName: {
    fontSize: '12px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.85)',
    whiteSpace: 'nowrap' as const,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  } as React.CSSProperties,

  countryCode: {
    fontSize: '9px',
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,

  countryShare: {
    width: '60px',
    flexShrink: 0,
  } as React.CSSProperties,

  shareBar: {
    height: '4px',
    background: 'rgba(255, 255, 255, 0.08)',
    borderRadius: '2px',
    overflow: 'hidden',
    marginBottom: '2px',
  } as React.CSSProperties,

  shareBarFill: {
    height: '100%',
    background: 'linear-gradient(90deg, rgba(100, 200, 150, 0.8), rgba(100, 140, 255, 0.6))',
    borderRadius: '2px',
  } as React.CSSProperties,

  shareText: {
    fontSize: '9px',
    color: 'rgba(255, 255, 255, 0.4)',
    textAlign: 'right' as const,
  } as React.CSSProperties,

  countryRevenue: {
    fontSize: '12px',
    fontWeight: 600,
    color: 'rgba(100, 200, 150, 0.9)',
    fontVariantNumeric: 'tabular-nums',
    textAlign: 'right' as const,
    width: '70px',
    flexShrink: 0,
  } as React.CSSProperties,

  emptyState: {
    padding: '20px',
    textAlign: 'center' as const,
    color: 'rgba(255, 255, 255, 0.35)',
    fontSize: '11px',
  } as React.CSSProperties,

  // ==========================================================================
  // MAP PANEL - Mood-like styling
  // ==========================================================================
  mapPanel: {
    height: '100%',
    minHeight: '400px',
    padding: '18px 20px',
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    justifyContent: 'center',
    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.03)',
    position: 'relative' as const,
    overflow: 'hidden',
  } as React.CSSProperties,

  // ==========================================================================
  // INSIGHTS CARDS
  // ==========================================================================
  insightCard: {
    padding: '14px 16px',
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
    flexShrink: 0,
    boxShadow: '0 4px 16px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(255, 255, 255, 0.03)',
  } as React.CSSProperties,

  insightTitle: {
    margin: '0 0 6px 0',
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.08em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.45)',
  } as React.CSSProperties,

  sensitivityList: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
    display: 'flex',
    gap: '12px',
  } as React.CSSProperties,

  sensitivityItem: {
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.6)',
  } as React.CSSProperties,

  sensitivityImpact: {
    fontWeight: 600,
    color: 'rgba(100, 200, 150, 0.9)',
  } as React.CSSProperties,

  recommendationList: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
  } as React.CSSProperties,

  recommendationItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: '8px',
    padding: '4px 0',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.6)',
    lineHeight: 1.4,
  } as React.CSSProperties,

  recommendationIcon: {
    color: 'rgba(255, 200, 100, 0.7)',
    fontSize: '10px',
    marginTop: '2px',
  } as React.CSSProperties,

  // ==========================================================================
  // GEO INSIGHT LANGUAGE BLOCK - Concluding analysis block
  // ==========================================================================
  geoInsightCard: {
    padding: '18px 20px',
    background: `
      linear-gradient(180deg, rgba(255, 255, 255, 0.02) 0%, rgba(255, 255, 255, 0.01) 100%),
      linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)
    `,
    borderTop: '1px solid rgba(100, 180, 200, 0.2)',
    borderLeft: '1px solid rgba(100, 140, 200, 0.1)',
    borderRight: '1px solid rgba(100, 140, 200, 0.1)',
    borderBottom: '1px solid rgba(100, 140, 200, 0.08)',
    borderRadius: '12px',
    boxShadow: '0 -2px 12px rgba(100, 180, 200, 0.06), 0 4px 16px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(100, 180, 200, 0.08)',
  } as React.CSSProperties,

  geoInsightLabel: {
    display: 'block',
    marginBottom: '8px',
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.45)',
  } as React.CSSProperties,

  geoInsightHeadline: {
    margin: '0 0 10px 0',
    fontSize: '13px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
    lineHeight: 1.4,
  } as React.CSSProperties,

  geoInsightBullets: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '4px',
  } as React.CSSProperties,

  geoInsightBullet: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.5)',
    display: 'flex',
    justifyContent: 'space-between',
    gap: '8px',
  } as React.CSSProperties,

  geoInsightBulletValue: {
    fontWeight: 600,
  } as React.CSSProperties,

  geoInsightWarnings: {
    marginTop: '10px',
    padding: '8px 10px',
    background: 'rgba(255, 150, 100, 0.08)',
    borderRadius: '6px',
    border: '1px solid rgba(255, 150, 100, 0.15)',
  } as React.CSSProperties,

  geoInsightWarning: {
    fontSize: '9px',
    color: 'rgba(255, 180, 120, 0.9)',
    margin: '0 0 4px 0',
    lineHeight: 1.4,
  } as React.CSSProperties,

  geoInsightRecommendation: {
    marginTop: '10px',
    fontSize: '10px',
    color: 'rgba(100, 180, 255, 0.8)',
    fontStyle: 'italic' as const,
    lineHeight: 1.4,
  } as React.CSSProperties,

  // ==========================================================================
  // PHASE 3: MOMENTUM, CONFIDENCE, STABILITY
  // ==========================================================================
  geoInsightMeta: {
    marginTop: '12px',
    paddingTop: '12px',
    borderTop: '1px solid rgba(255, 255, 255, 0.06)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '8px',
  } as React.CSSProperties,

  geoInsightMomentum: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.7)',
    lineHeight: 1.4,
  } as React.CSSProperties,

  geoInsightMetaRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    fontSize: '10px',
  } as React.CSSProperties,

  geoInsightBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '4px',
    padding: '2px 8px',
    borderRadius: '4px',
    fontSize: '9px',
    fontWeight: 600,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  geoInsightBadgeHigh: {
    background: 'rgba(100, 200, 150, 0.15)',
    color: 'rgba(100, 200, 150, 0.95)',
    border: '1px solid rgba(100, 200, 150, 0.2)',
  } as React.CSSProperties,

  geoInsightBadgeMedium: {
    background: 'rgba(255, 200, 100, 0.12)',
    color: 'rgba(255, 200, 100, 0.95)',
    border: '1px solid rgba(255, 200, 100, 0.2)',
  } as React.CSSProperties,

  geoInsightBadgeLow: {
    background: 'rgba(255, 130, 100, 0.12)',
    color: 'rgba(255, 150, 120, 0.95)',
    border: '1px solid rgba(255, 130, 100, 0.2)',
  } as React.CSSProperties,

  geoInsightBadgeStable: {
    background: 'rgba(100, 140, 200, 0.12)',
    color: 'rgba(130, 170, 230, 0.95)',
    border: '1px solid rgba(100, 140, 200, 0.2)',
  } as React.CSSProperties,

  geoInsightBadgeVolatile: {
    background: 'rgba(255, 150, 100, 0.12)',
    color: 'rgba(255, 170, 130, 0.95)',
    border: '1px solid rgba(255, 150, 100, 0.2)',
  } as React.CSSProperties,

  geoInsightBadgeEmerging: {
    background: 'rgba(180, 130, 255, 0.12)',
    color: 'rgba(190, 160, 255, 0.95)',
    border: '1px solid rgba(180, 130, 255, 0.2)',
  } as React.CSSProperties,

  geoInsightMetaReason: {
    color: 'rgba(255, 255, 255, 0.45)',
    fontSize: '9px',
    lineHeight: 1.3,
  } as React.CSSProperties,

  // ==========================================================================
  // PHASE 4: REVENUE × MOOD CORRELATION (Collapsible)
  // ==========================================================================
  corrSection: {
    marginTop: '14px',
    paddingTop: '14px',
    borderTop: '1px solid rgba(255, 255, 255, 0.06)',
  } as React.CSSProperties,

  corrHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    cursor: 'pointer',
    userSelect: 'none' as const,
    padding: '4px 6px',
    margin: '-4px -6px',
    borderRadius: '6px',
    transition: 'background 0.15s ease',
  } as React.CSSProperties,

  corrHeaderHover: {
    background: 'rgba(255, 255, 255, 0.04)',
  } as React.CSSProperties,

  corrHeaderLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  } as React.CSSProperties,

  corrHeaderRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  } as React.CSSProperties,

  corrToggleLabel: {
    fontSize: '8px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.35)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  corrChevron: {
    fontSize: '8px',
    color: 'rgba(255, 255, 255, 0.4)',
    transition: 'transform 0.15s ease',
  } as React.CSSProperties,

  corrTitle: {
    margin: 0,
    fontSize: '9px',
    fontWeight: 600,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  corrPreview: {
    fontSize: '9px',
    color: 'rgba(255, 255, 255, 0.35)',
    maxWidth: '140px',
    whiteSpace: 'nowrap' as const,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  } as React.CSSProperties,

  corrBody: {
    marginTop: '10px',
  } as React.CSSProperties,

  corrHeadline: {
    margin: '0 0 8px 0',
    fontSize: '11px',
    fontWeight: 500,
    lineHeight: 1.4,
  } as React.CSSProperties,

  corrBullets: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '3px',
    marginBottom: '8px',
  } as React.CSSProperties,

  corrBullet: {
    fontSize: '9px',
    color: 'rgba(255, 255, 255, 0.5)',
    display: 'flex',
    justifyContent: 'space-between',
    gap: '8px',
  } as React.CSSProperties,

  corrBulletValue: {
    fontWeight: 600,
  } as React.CSSProperties,

  corrConfidence: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontSize: '9px',
  } as React.CSSProperties,

  // ==========================================================================
  // PHASE 5B: REVENUE NARRATIVE
  // ==========================================================================
  narrativeCard: {
    padding: '24px',
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.9) 0%, rgba(15, 15, 22, 0.95) 100%)',
    border: '1px solid rgba(100, 180, 255, 0.12)',
    borderRadius: '12px',
    flexShrink: 0,
    boxShadow: '0 4px 20px rgba(100, 180, 255, 0.08), 0 8px 32px rgba(0, 0, 0, 0.25), inset 0 1px 0 rgba(100, 180, 255, 0.08)',
  } as React.CSSProperties,

  narrativeCardPositive: {
    border: '1px solid rgba(100, 200, 150, 0.15)',
    boxShadow: '0 4px 20px rgba(100, 200, 150, 0.1), 0 8px 32px rgba(0, 0, 0, 0.25), inset 0 1px 0 rgba(100, 200, 150, 0.08)',
  } as React.CSSProperties,

  narrativeCardRisk: {
    border: '1px solid rgba(255, 150, 100, 0.15)',
    boxShadow: '0 4px 20px rgba(255, 150, 100, 0.1), 0 8px 32px rgba(0, 0, 0, 0.25), inset 0 1px 0 rgba(255, 150, 100, 0.08)',
  } as React.CSSProperties,

  narrativeLabel: {
    display: 'block',
    marginBottom: '8px',
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.6)',
  } as React.CSSProperties,

  narrativeHeadline: {
    margin: '0 0 10px 0',
    fontSize: '15px',
    fontWeight: 600,
    lineHeight: 1.4,
    letterSpacing: '-0.01em',
  } as React.CSSProperties,

  narrativeHeadlinePositive: {
    color: 'rgba(100, 200, 150, 0.95)',
  } as React.CSSProperties,

  narrativeHeadlineNeutral: {
    color: 'rgba(255, 255, 255, 0.85)',
  } as React.CSSProperties,

  narrativeHeadlineRisk: {
    color: 'rgba(255, 180, 120, 0.95)',
  } as React.CSSProperties,

  narrativeSummary: {
    margin: '0 0 12px 0',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.6)',
    lineHeight: 1.5,
  } as React.CSSProperties,

  narrativeSection: {
    marginBottom: '8px',
  } as React.CSSProperties,

  narrativeSectionLabel: {
    fontSize: '8px',
    fontWeight: 600,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    marginBottom: '4px',
  } as React.CSSProperties,

  narrativeDriversLabel: {
    color: 'rgba(100, 200, 150, 0.6)',
  } as React.CSSProperties,

  narrativeRisksLabel: {
    color: 'rgba(255, 150, 100, 0.6)',
  } as React.CSSProperties,

  narrativeList: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '3px',
  } as React.CSSProperties,

  narrativeListItem: {
    fontSize: '10px',
    display: 'flex',
    alignItems: 'flex-start',
    gap: '6px',
    lineHeight: 1.4,
  } as React.CSSProperties,

  narrativeDriverItem: {
    color: 'rgba(255, 255, 255, 0.7)',
  } as React.CSSProperties,

  narrativeRiskItem: {
    color: 'rgba(255, 200, 150, 0.8)',
  } as React.CSSProperties,

  narrativeBullet: {
    fontSize: '8px',
    marginTop: '2px',
  } as React.CSSProperties,

  narrativeDriverBullet: {
    color: 'rgba(100, 200, 150, 0.7)',
  } as React.CSSProperties,

  narrativeRiskBullet: {
    color: 'rgba(255, 150, 100, 0.7)',
  } as React.CSSProperties,

  narrativeOpportunity: {
    marginTop: '10px',
    paddingTop: '10px',
    borderTop: '1px solid rgba(255, 255, 255, 0.06)',
    fontSize: '10px',
    fontStyle: 'italic' as const,
    color: 'rgba(100, 180, 255, 0.8)',
    lineHeight: 1.4,
  } as React.CSSProperties,
};

// =============================================================================
// HELPERS
// =============================================================================

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function formatNOK(value: number): string {
  const decimals = Math.abs(value) < 100 ? 2 : 0;
  return `${value.toLocaleString('nb-NO', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })} NOK`;
}

function formatNumber(value: number, decimals = 0): string {
  return value.toLocaleString('nb-NO', { 
    minimumFractionDigits: decimals, 
    maximumFractionDigits: decimals 
  });
}

const countryDisplayNames = (() => {
  try {
    return new Intl.DisplayNames(['en'], { type: 'region' });
  } catch {
    return null;
  }
})();

function getCountryName(code: string): string {
  if (!code) return '';
  try {
    return countryDisplayNames?.of(code.toUpperCase()) ?? code;
  } catch {
    return code;
  }
}

// =============================================================================
// TABLE SORTING
// =============================================================================

type SortKey = 'country_code' | 'sessions' | 'share_pct' | 'impressions' | 'estimated_ad_revenue' | 'revenue_per_session';
type SortDirection = 'asc' | 'desc';

interface SortConfig {
  key: SortKey;
  direction: SortDirection;
}

interface CountryRevenueDataWithShare extends CountryRevenueData {
  share_pct: number;
}

function addSharePct(data: CountryRevenueData[]): CountryRevenueDataWithShare[] {
  const totalSessions = data.reduce((sum, row) => sum + row.sessions, 0);
  return data.map(row => ({
    ...row,
    share_pct: totalSessions > 0 ? (row.sessions / totalSessions) * 100 : 0,
  }));
}

function sortCountryData(data: CountryRevenueData[], config: SortConfig): CountryRevenueDataWithShare[] {
  const dataWithShare = addSharePct(data);
  return dataWithShare.sort((a, b) => {
    const aVal = a[config.key];
    const bVal = b[config.key];
    
    if (typeof aVal === 'string' && typeof bVal === 'string') {
      return config.direction === 'asc' 
        ? aVal.localeCompare(bVal)
        : bVal.localeCompare(aVal);
    }
    
    const aNum = Number(aVal);
    const bNum = Number(bVal);
    return config.direction === 'asc' ? aNum - bNum : bNum - aNum;
  });
}

// =============================================================================
// COMPARE CONTEXT HELPER (Phase 8 UX)
// =============================================================================

function getCompareLabel(timeRange: string): string {
  if (timeRange === '7d') return 'previous 7 days';
  if (timeRange === '30d') return 'previous 30 days';
  return 'previous period';
}

// =============================================================================
// COMPONENT
// =============================================================================

export function MonetizationPage() {
  // Responsive layout detection
  const isDesktop = useIsDesktop();

  // Filter system with URL sync
  const { filters: coreFilters } = useFiltersCore();
  
  // Convert to legacy format for existing hooks
  const { filters, window, lensLabel, windowLabel } = useMemo(
    () => toLegacyFilters(coreFilters),
    [coreFilters]
  );
  
  const { data: engagementData, loading } = useEngagementFlow(filters, window);

  // Revenue geo data for map (uses the new RPC)
  // compareToPrevious is controlled by shared filter state
  const {
    mapData: revenueGeoData,
    topCountries: revenueGeoTop,
    totals: revenueGeoTotals,
    previous: revenueGeoPrevious,
    loading: revenueGeoLoading,
    error: revenueGeoError,
  } = useRevenueGeo({
    timeRangeDays: window.days,
    region: filters.region,
    enabled: true,
    compareToPrevious: coreFilters.compareToPrevious,
  });

  // Mood pulse data for correlation (Phase 4)
  // Uses same filter params; hook already provides current vs previous comparison
  const {
    data: moodPulseData,
    loading: moodPulseLoading,
  } = useMoodPulse(
    window.days === 1 ? '24h' : window.days === 7 ? '7d' : '30d',
    filters.region,
    null, // countryCode - not filtering by country on Monetization
    null  // cityCode
  );

  // Debug logging for revenue geo data (temporary, guarded)
  const prevGeoDataRef = useRef<string>('');
  useEffect(() => {
    if (revenueGeoLoading) return;
    const dataKey = JSON.stringify({ count: revenueGeoData.length, totals: revenueGeoTotals });
    if (dataKey !== prevGeoDataRef.current) {
      prevGeoDataRef.current = dataKey;
      if (import.meta.env.DEV) {
        console.log('[RevenueGeo]', { 
          mapData: revenueGeoData, 
          totals: revenueGeoTotals, 
          topCountries: revenueGeoTop 
        });
      }
    }
  }, [revenueGeoData, revenueGeoTotals, revenueGeoTop, revenueGeoLoading]);

  // Assumptions (inputs)
  const [ecpm, setEcpm] = useState(35);
  const [fillRate, setFillRate] = useState(0.85);
  const [adsPerSessionCap, setAdsPerSessionCap] = useState(1);
  const [triggerShare, setTriggerShare] = useState(0.60);
  const [dropRateAfterAd, setDropRateAfterAd] = useState(0.40);

  // UI state
  const [assumptionsExpanded, setAssumptionsExpanded] = useState(false);
  const [corrOpen, setCorrOpen] = useState(false);
  const [corrHovered, setCorrHovered] = useState(false);
  const [mapHoveredCountry, setMapHoveredCountry] = useState<string | null>(null);
  const [mapPinnedCountry, setMapPinnedCountry] = useState<string | null>(null);

  // Phase 7: Handle click-to-pin/unpin
  const handleMapClickCountry = useCallback((countryCode: string) => {
    setMapPinnedCountry(prev => prev === countryCode ? null : countryCode);
  }, []);

  // Phase 7: Auto-unpin if pinned country no longer exists in data
  useEffect(() => {
    if (mapPinnedCountry && revenueGeoData.length > 0) {
      const exists = revenueGeoData.some(
        item => item.countryCode.toUpperCase() === mapPinnedCountry
      );
      if (!exists) {
        setMapPinnedCountry(null);
      }
    }
  }, [revenueGeoData, mapPinnedCountry]);
  const [countrySort, setCountrySort] = useState<SortConfig>({ 
    key: 'estimated_ad_revenue', 
    direction: 'desc' 
  });

  // Revenue assumptions for country breakdown
  const revenueAssumptions = useMemo(() => ({
    ecpm,
    fillRate,
    adsPerSessionCap,
    triggerShare,
  }), [ecpm, fillRate, adsPerSessionCap, triggerShare]);

  // Fetch top earning countries
  const { 
    data: countryData, 
    loading: countryLoading 
  } = useTopEarningCountries(filters, window, revenueAssumptions);

  // Sorted country data
  const sortedCountryData = useMemo(() => 
    sortCountryData(countryData, countrySort),
    [countryData, countrySort]
  );

  // Derived data from engagement flow
  const sessionsTotal = engagementData?.sessions ?? 0;
  const pagesPerSession = engagementData?.pages_per_session ?? 0;
  const adsShownSessions = engagementData?.ads_shown_sessions ?? 0;
  const adDropSessions = engagementData?.ad_drop_sessions ?? 0;

  // Calculate drop rate from data if available
  const dataDropRate = adsShownSessions > 0 
    ? adDropSessions / adsShownSessions 
    : 0.40;

  const effectiveDropRate = engagementData && adsShownSessions > 0 
    ? dropRateAfterAd 
    : dropRateAfterAd;

  // Sessions per day based on window
  const sessionsPerDay = useMemo(() => {
    if (sessionsTotal === 0) return 0;
    switch (window.days) {
      case 1: return sessionsTotal;
      case 7: return sessionsTotal / 7;
      case 30: return sessionsTotal / 30;
      default: return sessionsTotal / 7;
    }
  }, [sessionsTotal, window.days]);

  // Revenue calculations
  const calculations = useMemo(() => {
    const impressionsPerDay = sessionsPerDay * adsPerSessionCap * triggerShare * fillRate;
    const revenuePerDay = (impressionsPerDay / 1000) * ecpm;
    const revenuePerMonth = revenuePerDay * 30;
    const revenuePerSession = sessionsPerDay > 0 ? revenuePerDay / sessionsPerDay : 0;

    return {
      impressionsPerDay,
      revenuePerDay,
      revenuePerMonth,
      revenuePerSession,
    };
  }, [sessionsPerDay, adsPerSessionCap, triggerShare, fillRate, ecpm]);

  // Phase 8: Previous period sessions per day (for global delta)
  const prevSessionsPerDay = useMemo(() => {
    if (!coreFilters.compareToPrevious || !revenueGeoPrevious?.totals) return 0;
    const prevSessions = revenueGeoPrevious.totals.sessions;
    if (prevSessions === 0) return 0;
    switch (window.days) {
      case 1: return prevSessions;
      case 7: return prevSessions / 7;
      case 30: return prevSessions / 30;
      default: return prevSessions / 7;
    }
  }, [coreFilters.compareToPrevious, revenueGeoPrevious?.totals, window.days]);

  // Phase 8: Previous period calculations (using same assumptions)
  const prevCalculations = useMemo(() => {
    if (!coreFilters.compareToPrevious || prevSessionsPerDay === 0) return null;
    
    const impressionsPerDay = prevSessionsPerDay * adsPerSessionCap * triggerShare * fillRate;
    const revenuePerDay = (impressionsPerDay / 1000) * ecpm;
    const revenuePerMonth = revenuePerDay * 30;
    const revenuePerSession = prevSessionsPerDay > 0 ? revenuePerDay / prevSessionsPerDay : 0;

    return {
      impressionsPerDay,
      revenuePerDay,
      revenuePerMonth,
      revenuePerSession,
    };
  }, [coreFilters.compareToPrevious, prevSessionsPerDay, adsPerSessionCap, triggerShare, fillRate, ecpm]);

  // Phase 8: Global compare deltas
  const globalDeltas = useMemo(() => {
    if (!coreFilters.compareToPrevious || !prevCalculations) return null;
    
    return {
      revenueMonthDeltaPct: percentDelta(calculations.revenuePerMonth, prevCalculations.revenuePerMonth),
      sessionsPerDayDeltaPct: percentDelta(sessionsPerDay, prevSessionsPerDay),
      impressionsPerDayDeltaPct: percentDelta(calculations.impressionsPerDay, prevCalculations.impressionsPerDay),
      revenuePerSessionDeltaPct: percentDelta(calculations.revenuePerSession, prevCalculations.revenuePerSession),
    };
  }, [coreFilters.compareToPrevious, calculations, prevCalculations, sessionsPerDay, prevSessionsPerDay]);

  // Sensitivity analysis
  const sensitivityAnalysis = useMemo(() => {
    const baseRevenue = calculations.revenuePerDay;
    if (baseRevenue === 0) return [];

    const factors = [
      { name: 'eCPM', newRevenue: ((sessionsPerDay * adsPerSessionCap * triggerShare * fillRate) / 1000) * (ecpm * 1.1) },
      { name: 'Fill', newRevenue: ((sessionsPerDay * adsPerSessionCap * triggerShare * clamp(fillRate * 1.1, 0, 1)) / 1000) * ecpm },
      { name: 'Trigger', newRevenue: ((sessionsPerDay * adsPerSessionCap * clamp(triggerShare * 1.1, 0, 1) * fillRate) / 1000) * ecpm },
      { name: 'Traffic', newRevenue: ((sessionsPerDay * 1.1 * adsPerSessionCap * triggerShare * fillRate) / 1000) * ecpm },
    ];

    return factors
      .map(f => ({ name: f.name, impact: ((f.newRevenue - baseRevenue) / baseRevenue) * 100 }))
      .sort((a, b) => b.impact - a.impact);
  }, [calculations.revenuePerDay, sessionsPerDay, adsPerSessionCap, triggerShare, fillRate, ecpm]);

  // Recommendations
  const recommendations = useMemo(() => {
    const recs: string[] = [];
    if (triggerShare < 0.4) recs.push('Increase trigger share to show ads to more sessions');
    if (fillRate < 0.7) recs.push('Low fill rate — check ad network setup');
    if (effectiveDropRate > 0.45) recs.push('High drop rate — consider less intrusive ad placement');
    if (pagesPerSession < 3) recs.push('Low engagement — focus on retention first');
    if (recs.length === 0) recs.push('Settings look balanced');
    return recs.slice(0, 2);
  }, [triggerShare, fillRate, effectiveDropRate, pagesPerSession]);

  // Revenue bottleneck
  const driverInsight = useMemo(() => 
    analyzeRevenueDrivers({
      sessions: sessionsPerDay,
      eCPM: ecpm,
      fillRate,
      adsPerSessionCap,
      triggerShare,
    }),
    [sessionsPerDay, ecpm, fillRate, adsPerSessionCap, triggerShare]
  );

  // Max share for scaling bars
  const maxShare = sortedCountryData.length > 0 
    ? Math.max(...sortedCountryData.map(d => d.share_pct))
    : 100;

  // Revenue geo insight language (Phase 3: includes momentum, confidence, stability)
  const revenueGeoInsight = useMemo(() => {
    if (revenueGeoLoading) return null;
    return buildRevenueInsightLanguage({
      mapData: revenueGeoData,
      totals: revenueGeoTotals,
      topCountries: revenueGeoTop,
      context: {
        regionLabel: lensLabel,
        timeRangeLabel: windowLabel,
      },
      previous: revenueGeoPrevious,
    });
  }, [revenueGeoData, revenueGeoTotals, revenueGeoTop, revenueGeoLoading, lensLabel, windowLabel, revenueGeoPrevious]);

  // Revenue × Mood Correlation (Phase 4)
  const revenueMoodCorrelation = useMemo(() => {
    if (revenueGeoLoading || moodPulseLoading) return null;
    if (!moodPulseData) return null;

    return buildRevenueMoodCorrelation({
      revenue: {
        currentSessions: revenueGeoTotals.sessions,
        previousSessions: revenueGeoPrevious?.totals.sessions,
        currentActiveCountries: revenueGeoData.length,
        previousActiveCountries: revenueGeoPrevious?.mapData.length,
      },
      mood: {
        currentBalance: moodPulseData.balanceScore,
        previousBalance: moodPulseData.prevBalanceScore,
        deltaBalance: moodPulseData.deltaBalanceScore,
        currentTotal: moodPulseData.totalConfessions,
        previousTotal: undefined, // Not separately available, but delta is
      },
      context: {
        regionLabel: lensLabel,
        timeRangeLabel: windowLabel,
      },
    });
  }, [
    revenueGeoLoading,
    moodPulseLoading,
    moodPulseData,
    revenueGeoTotals,
    revenueGeoPrevious,
    revenueGeoData.length,
    lensLabel,
    windowLabel,
  ]);

  // Revenue Narrative (Phase 5B)
  const revenueNarrative = useMemo(() => {
    return buildRevenueNarrative({
      geoInsight: revenueGeoInsight,
      correlation: revenueMoodCorrelation,
      totals: revenueGeoTotals,
    });
  }, [revenueGeoInsight, revenueMoodCorrelation, revenueGeoTotals]);

  return (
    <div style={styles.page}>
      {/* Sticky Filter Row */}
      <div style={styles.filterRowSticky}>
        <div style={styles.titleSection}>
          <h1 style={styles.title}>Revenue Lab</h1>
          <span style={styles.subtitle}>{lensLabel} · {windowLabel}</span>
          {coreFilters.compareToPrevious && (
            <div style={styles.compareContext}>
              <span>↳</span>
              <span>Compared to {getCompareLabel(coreFilters.timeRange)}</span>
            </div>
          )}
        </div>
        <FilterBarCore 
          enableCountry={false} 
          enableCity={false} 
          showReset={true}
          showCompare={true}
          sticky={true}
          compareActive={coreFilters.compareToPrevious}
        />
      </div>

      {/* SECTION: Revenue Overview */}
      <div style={{ marginTop: '8px', marginBottom: '16px' }}>
        <div style={sectionHeaderStyles.labelRow}>
          <span style={sectionHeaderStyles.label}>REVENUE OVERVIEW</span>
          <div style={sectionHeaderStyles.divider} />
        </div>
      </div>

      {/* TOP ROW: KPI Card + Top Countries */}
      <div style={isDesktop ? styles.topRow : styles.topRowStacked}>
        {/* Hero Revenue Card */}
        <div style={styles.heroCard}>
          <div style={styles.heroGlow} />
          <p style={styles.heroLabel}>Estimated Revenue / Month</p>
          <div style={styles.heroValueRow}>
            <p style={styles.heroValue}>
              {loading ? '—' : formatNOK(calculations.revenuePerMonth)}
            </p>
            {globalDeltas && <DeltaBadge value={globalDeltas.revenueMonthDeltaPct} />}
          </div>

          <div style={styles.heroSecondary}>
            <div style={styles.heroKpi}>
              <span style={styles.heroKpiLabel}>Per Session</span>
              <div style={styles.heroKpiValueRow}>
                <span style={styles.heroKpiValue}>
                  {loading ? '—' : formatNOK(calculations.revenuePerSession)}
                </span>
                {globalDeltas && <DeltaBadge value={globalDeltas.revenuePerSessionDeltaPct} />}
              </div>
            </div>
            <div style={styles.heroKpi}>
              <span style={styles.heroKpiLabel}>Impressions/Day</span>
              <div style={styles.heroKpiValueRow}>
                <span style={styles.heroKpiValue}>
                  {loading ? '—' : formatNumber(calculations.impressionsPerDay, 0)}
                </span>
                {globalDeltas && <DeltaBadge value={globalDeltas.impressionsPerDayDeltaPct} />}
              </div>
            </div>
            <div style={styles.heroKpi}>
              <span style={styles.heroKpiLabel}>Sessions/Day</span>
              <div style={styles.heroKpiValueRow}>
                <span style={styles.heroKpiValue}>
                  {loading ? '—' : formatNumber(sessionsPerDay, 0)}
                </span>
                {globalDeltas && <DeltaBadge value={globalDeltas.sessionsPerDayDeltaPct} />}
              </div>
            </div>
          </div>

          <div style={styles.heroInsight}>
            <span style={styles.heroInsightLabel}>Bottleneck: </span>
            {driverInsight.title}
          </div>
        </div>

        {/* Top Earning Countries */}
        <div style={styles.countriesCard}>
          <h2 style={styles.cardTitle}>Top Earning Countries</h2>

          {countryLoading ? (
            <div style={styles.emptyState}>Loading...</div>
          ) : sortedCountryData.length === 0 ? (
            <div style={styles.emptyState}>No country data yet</div>
          ) : (
            <div style={styles.tableWrapper}>
              {sortedCountryData.map((row, index) => (
                <div key={row.country_code} style={styles.countryRow}>
                  <div style={index < 3 ? styles.countryRankTop : styles.countryRank}>
                    {index + 1}
                  </div>
                  <div style={styles.countryInfo}>
                    <div style={styles.countryName}>{getCountryName(row.country_code)}</div>
                    <div style={styles.countryCode}>{row.country_code}</div>
                  </div>
                  <div style={styles.countryShare}>
                    <div style={styles.shareBar}>
                      <div style={{ 
                        ...styles.shareBarFill, 
                        width: `${(row.share_pct / maxShare) * 100}%` 
                      }} />
                    </div>
                    <div style={styles.shareText}>{row.share_pct.toFixed(1)}%</div>
                  </div>
                  <div style={styles.countryRevenue}>
                    {formatNOK(row.estimated_ad_revenue)}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* MAIN ROW: Insights (left) + Sticky Map (right) */}
      <div style={isDesktop ? styles.mainRow : styles.mainRowStacked}>
        {/* LEFT: Insights Column */}
        <div style={styles.insightsColumn}>
          {/* SECTION: Monetization Signals */}
          <div style={{ marginBottom: '16px' }}>
            <div style={sectionHeaderStyles.labelRow}>
              <span style={sectionHeaderStyles.label}>MONETIZATION SIGNALS</span>
              <div style={sectionHeaderStyles.divider} />
            </div>
            <p style={sectionHeaderStyles.subtitle}>Tune assumptions and explore sensitivity</p>
          </div>

          {/* Collapsible Assumptions Panel */}
          <div style={styles.assumptionsPanel}>
            <div 
              style={styles.assumptionsHeader}
              onClick={() => setAssumptionsExpanded(!assumptionsExpanded)}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <h2 style={styles.assumptionsTitle}>Assumptions</h2>
                <div style={styles.assumptionsSummary}>
                  <span style={styles.assumptionsBadge}>eCPM {ecpm}</span>
                  <span style={styles.assumptionsBadge}>Fill {(fillRate * 100).toFixed(0)}%</span>
                  <span style={styles.assumptionsBadge}>Trigger {(triggerShare * 100).toFixed(0)}%</span>
                </div>
              </div>
              <button style={styles.assumptionsToggle}>
                {assumptionsExpanded ? '▲ Collapse' : '▼ Expand'}
              </button>
            </div>

            {assumptionsExpanded && (
              <div style={styles.assumptionsBody}>
                <div style={styles.inputGroup}>
                  <label style={styles.inputLabel}>eCPM (NOK)</label>
                  <div style={styles.inputRow}>
                    <input type="range" min="5" max="100" step="1" value={ecpm}
                      onChange={(e) => setEcpm(Number(e.target.value))} style={styles.slider} />
                    <input type="number" min="1" max="200" value={ecpm}
                      onChange={(e) => setEcpm(clamp(Number(e.target.value), 1, 200))} style={styles.numberInput} />
                  </div>
                </div>
                <div style={styles.inputGroup}>
                  <label style={styles.inputLabel}>Fill rate</label>
                  <div style={styles.inputRow}>
                    <input type="range" min="0" max="1" step="0.01" value={fillRate}
                      onChange={(e) => setFillRate(Number(e.target.value))} style={styles.slider} />
                    <input type="number" min="0" max="1" step="0.01" value={fillRate}
                      onChange={(e) => setFillRate(clamp(Number(e.target.value), 0, 1))} style={styles.numberInput} />
                  </div>
                </div>
                <div style={styles.inputGroup}>
                  <label style={styles.inputLabel}>Ads per session cap</label>
                  <select value={adsPerSessionCap} onChange={(e) => setAdsPerSessionCap(Number(e.target.value))} style={styles.select}>
                    <option value={0}>0</option>
                    <option value={1}>1</option>
                    <option value={2}>2</option>
                    <option value={3}>3</option>
                  </select>
                </div>
                <div style={styles.inputGroup}>
                  <label style={styles.inputLabel}>Trigger share</label>
                  <div style={styles.inputRow}>
                    <input type="range" min="0" max="1" step="0.01" value={triggerShare}
                      onChange={(e) => setTriggerShare(Number(e.target.value))} style={styles.slider} />
                    <input type="number" min="0" max="1" step="0.01" value={triggerShare}
                      onChange={(e) => setTriggerShare(clamp(Number(e.target.value), 0, 1))} style={styles.numberInput} />
                  </div>
                </div>
                <div style={styles.inputGroup}>
                  <label style={styles.inputLabel}>
                    Drop rate after ad
                    <span style={{ opacity: 0.6, marginLeft: '6px', fontSize: '9px' }}>
                      {engagementData && adsShownSessions > 0 ? `Data: ${(dataDropRate * 100).toFixed(0)}%` : ''}
                    </span>
                  </label>
                  <div style={styles.inputRow}>
                    <input type="range" min="0" max="1" step="0.01" value={dropRateAfterAd}
                      onChange={(e) => setDropRateAfterAd(Number(e.target.value))} style={styles.slider} />
                    <input type="number" min="0" max="1" step="0.01" value={dropRateAfterAd}
                      onChange={(e) => setDropRateAfterAd(clamp(Number(e.target.value), 0, 1))} style={styles.numberInput} />
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Sensitivity + Tips in a row */}
          <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' as const }}>
            <div style={{ ...styles.insightCard, flex: 1, minWidth: '140px' }}>
              <h3 style={styles.insightTitle}>+10% Impact</h3>
              {sensitivityAnalysis.length === 0 ? (
                <p style={{ color: 'rgba(255, 255, 255, 0.4)', fontSize: '11px', margin: 0 }}>No data</p>
              ) : (
                <ul style={styles.sensitivityList}>
                  {sensitivityAnalysis.map((item, i) => (
                    <li key={i} style={styles.sensitivityItem}>
                      {item.name}: <span style={styles.sensitivityImpact}>+{item.impact.toFixed(1)}%</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <div style={{ ...styles.insightCard, flex: 1, minWidth: '140px' }}>
              <h3 style={styles.insightTitle}>Tips</h3>
              <ul style={styles.recommendationList}>
                {recommendations.map((rec, i) => (
                  <li key={i} style={styles.recommendationItem}>
                    <span style={styles.recommendationIcon}>→</span>
                    <span>{rec}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>

          {/* SECTION: Global Revenue Narrative */}
          <SectionHeader title="GLOBAL REVENUE NARRATIVE" subtitle="Synthesized view of drivers, risks, and opportunities" />

          {/* Revenue Narrative (Phase 5B) */}
          {revenueNarrative && (
            <div style={{
              ...styles.narrativeCard,
              ...(revenueNarrative.tone === 'positive' 
                ? styles.narrativeCardPositive 
                : revenueNarrative.tone === 'risk' 
                ? styles.narrativeCardRisk 
                : {}),
            }}>
              <span style={styles.narrativeLabel}>AI Interpretation</span>
              <h3 style={{
                ...styles.narrativeHeadline,
                ...(revenueNarrative.tone === 'positive' 
                  ? styles.narrativeHeadlinePositive
                  : revenueNarrative.tone === 'risk'
                  ? styles.narrativeHeadlineRisk
                  : styles.narrativeHeadlineNeutral),
              }}>
                {revenueNarrative.headline}
              </h3>

              <p style={styles.narrativeSummary}>
                {revenueNarrative.summary}
              </p>

              {revenueNarrative.drivers.length > 0 && (
                <div style={styles.narrativeSection}>
                  <div style={{ ...styles.narrativeSectionLabel, ...styles.narrativeDriversLabel }}>
                    Drivers
                  </div>
                  <ul style={styles.narrativeList}>
                    {revenueNarrative.drivers.map((driver, i) => (
                      <li key={i} style={{ ...styles.narrativeListItem, ...styles.narrativeDriverItem }}>
                        <span style={{ ...styles.narrativeBullet, ...styles.narrativeDriverBullet }}>+</span>
                        <span>{driver}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {revenueNarrative.risks.length > 0 && (
                <div style={styles.narrativeSection}>
                  <div style={{ ...styles.narrativeSectionLabel, ...styles.narrativeRisksLabel }}>
                    Risks
                  </div>
                  <ul style={styles.narrativeList}>
                    {revenueNarrative.risks.map((risk, i) => (
                      <li key={i} style={{ ...styles.narrativeListItem, ...styles.narrativeRiskItem }}>
                        <span style={{ ...styles.narrativeBullet, ...styles.narrativeRiskBullet }}>!</span>
                        <span>{risk}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {revenueNarrative.opportunity && (
                <p style={styles.narrativeOpportunity}>
                  {revenueNarrative.opportunity}
                </p>
              )}
            </div>
          )}

          {/* SECTION: Geographic Footprint */}
          <SectionHeader title="GEOGRAPHIC FOOTPRINT" subtitle="Regional patterns and concentration analysis" />

          {/* Geo Insight Language Block */}
          {revenueGeoInsight && (
            <div style={styles.geoInsightCard}>
              <span style={styles.geoInsightLabel}>Global Status</span>
              <p style={styles.geoInsightHeadline}>{revenueGeoInsight.headline}</p>
              
              {revenueGeoInsight.bullets.length > 0 && (
                <ul style={styles.geoInsightBullets}>
                  {revenueGeoInsight.bullets.map((bullet, i) => (
                    <li key={i} style={styles.geoInsightBullet}>
                      <span>{bullet.label}</span>
                      <span style={{
                        ...styles.geoInsightBulletValue,
                        color: bullet.tone === 'good' 
                          ? 'rgba(100, 200, 150, 0.9)'
                          : bullet.tone === 'warn'
                          ? 'rgba(255, 180, 120, 0.9)'
                          : 'rgba(255, 255, 255, 0.8)',
                      }}>
                        {bullet.value}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
              
              {revenueGeoInsight.warnings.length > 0 && (
                <div style={styles.geoInsightWarnings}>
                  {revenueGeoInsight.warnings.map((warning, i) => (
                    <p key={i} style={styles.geoInsightWarning}>{warning}</p>
                  ))}
                </div>
              )}
              
              {revenueGeoInsight.recommendation && (
                <p style={styles.geoInsightRecommendation}>
                  {revenueGeoInsight.recommendation}
                </p>
              )}

              {/* Phase 3: Momentum, Confidence, Stability */}
              <div style={styles.geoInsightMeta}>
                {revenueGeoInsight.momentum && (
                  <div style={{
                    ...styles.geoInsightMomentum,
                    color: revenueGeoInsight.momentum.tone === 'good'
                      ? 'rgba(100, 200, 150, 0.9)'
                      : revenueGeoInsight.momentum.tone === 'warn'
                      ? 'rgba(255, 180, 120, 0.9)'
                      : 'rgba(255, 255, 255, 0.7)',
                  }}>
                    {revenueGeoInsight.momentum.headline}
                  </div>
                )}

                <div style={styles.geoInsightMetaRow}>
                  <span style={{
                    ...styles.geoInsightBadge,
                    ...(revenueGeoInsight.confidence.label === 'high' 
                      ? styles.geoInsightBadgeHigh
                      : revenueGeoInsight.confidence.label === 'medium'
                      ? styles.geoInsightBadgeMedium
                      : styles.geoInsightBadgeLow),
                  }}>
                    Confidence: {revenueGeoInsight.confidence.label}
                  </span>

                  <span style={{
                    ...styles.geoInsightBadge,
                    ...(revenueGeoInsight.stability.label === 'stable'
                      ? styles.geoInsightBadgeStable
                      : revenueGeoInsight.stability.label === 'volatile'
                      ? styles.geoInsightBadgeVolatile
                      : styles.geoInsightBadgeEmerging),
                  }}>
                    {revenueGeoInsight.stability.label}
                  </span>
                </div>

                <div style={styles.geoInsightMetaReason}>
                  {revenueGeoInsight.confidence.reasons[0] && (
                    <span>{revenueGeoInsight.confidence.reasons[0]}</span>
                  )}
                  {revenueGeoInsight.stability.reasons[0] && revenueGeoInsight.confidence.reasons[0] && (
                    <span> · </span>
                  )}
                  {revenueGeoInsight.stability.reasons[0] && (
                    <span>{revenueGeoInsight.stability.reasons[0]}</span>
                  )}
                </div>
              </div>

              {/* Phase 4: Revenue × Mood Correlation (Collapsible) */}
              {revenueMoodCorrelation && (
                <div style={styles.corrSection}>
                  <div 
                    style={{
                      ...styles.corrHeader,
                      ...(corrHovered ? styles.corrHeaderHover : {}),
                    }}
                    onClick={() => setCorrOpen(v => !v)}
                    onMouseEnter={() => setCorrHovered(true)}
                    onMouseLeave={() => setCorrHovered(false)}
                  >
                    <div style={styles.corrHeaderLeft}>
                      <span style={{
                        ...styles.corrChevron,
                        transform: corrOpen ? 'rotate(90deg)' : 'rotate(0deg)',
                      }}>
                        ▶
                      </span>
                      <h4 style={styles.corrTitle}>Emotional Context</h4>
                      {!corrOpen && (
                        <span style={styles.corrPreview}>
                          {revenueMoodCorrelation.headline}
                        </span>
                      )}
                    </div>
                    <div style={styles.corrHeaderRight}>
                      <span style={styles.corrToggleLabel}>
                        {corrOpen ? 'Hide' : 'Show'}
                      </span>
                    </div>
                  </div>
                  
                  {corrOpen && (
                    <div style={styles.corrBody}>
                      <p style={{
                        ...styles.corrHeadline,
                        color: revenueMoodCorrelation.signal === 'tailwind'
                          ? 'rgba(100, 200, 150, 0.9)'
                          : revenueMoodCorrelation.signal === 'headwind' || revenueMoodCorrelation.signal === 'controversy'
                          ? 'rgba(255, 180, 120, 0.9)'
                          : revenueMoodCorrelation.signal === 'opportunity'
                          ? 'rgba(100, 180, 255, 0.85)'
                          : 'rgba(255, 255, 255, 0.65)',
                      }}>
                        {revenueMoodCorrelation.headline}
                      </p>

                      {revenueMoodCorrelation.bullets.length > 0 && (
                        <ul style={styles.corrBullets}>
                          {revenueMoodCorrelation.bullets.map((bullet, i) => (
                            <li key={i} style={styles.corrBullet}>
                              <span>{bullet.label}</span>
                              <span style={{
                                ...styles.corrBulletValue,
                                color: bullet.tone === 'good'
                                  ? 'rgba(100, 200, 150, 0.9)'
                                  : bullet.tone === 'warn'
                                  ? 'rgba(255, 180, 120, 0.9)'
                                  : 'rgba(255, 255, 255, 0.75)',
                              }}>
                                {bullet.value}
                              </span>
                            </li>
                          ))}
                        </ul>
                      )}

                      <div style={styles.corrConfidence}>
                        <span style={{
                          ...styles.geoInsightBadge,
                          ...(revenueMoodCorrelation.confidence.label === 'high'
                            ? styles.geoInsightBadgeHigh
                            : revenueMoodCorrelation.confidence.label === 'medium'
                            ? styles.geoInsightBadgeMedium
                            : styles.geoInsightBadgeLow),
                        }}>
                          {revenueMoodCorrelation.confidence.label}
                        </span>
                        {revenueMoodCorrelation.confidence.reasons[0] && (
                          <span style={{ color: 'rgba(255, 255, 255, 0.4)' }}>
                            {revenueMoodCorrelation.confidence.reasons[0]}
                          </span>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>

        {/* RIGHT: Sticky Map Column */}
        <div style={isDesktop ? styles.mapColumn : styles.mapColumnStacked}>
          <div style={styles.mapPanel}>
            <RevenueMapPhase1
              data={revenueGeoData}
              loading={revenueGeoLoading}
              error={revenueGeoError}
              totals={{
                sessions: revenueGeoTotals.sessions,
                adImpressions: revenueGeoTotals.adImpressions,
              }}
              hoveredCountryCode={mapHoveredCountry}
              onHoverCountry={setMapHoveredCountry}
              onClickCountry={handleMapClickCountry}
              pinnedCountryCode={mapPinnedCountry}
              previousData={revenueGeoPrevious?.mapData}
              previousTotals={revenueGeoPrevious?.totals ? {
                sessions: revenueGeoPrevious.totals.sessions,
                adImpressions: revenueGeoPrevious.totals.adImpressions,
              } : undefined}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
