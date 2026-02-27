/**
 * Revenue Insight Language Engine (v3)
 * 
 * Generates human-readable insights about geo revenue patterns
 * using deterministic rules. No AI calls.
 * 
 * Phase 3 adds:
 * - Momentum: current vs previous period comparison
 * - Confidence: data sufficiency scoring (0-100)
 * - Stability: footprint volatility assessment
 * 
 * Outputs investor-grade language: calm, concise, actionable.
 */

import type { RevenueGeoMapItem, RevenueGeoTotals, RevenueGeoRow, RevenueGeoPreviousPeriod } from '../../hooks/useRevenueGeo';

// =============================================================================
// TYPES
// =============================================================================

export type RevenueInsightTone = 'neutral' | 'good' | 'warn';

export interface RevenueInsightBullet {
  label: string;
  value: string;
  tone?: RevenueInsightTone;
}

// Phase 3: Momentum
export interface RevenueDelta {
  sessionsDeltaPct: number | null;
  impressionsDeltaPct: number | null;
  activeCountriesDelta: number | null;
  concentrationTop1DeltaPctPoints: number | null;
  impressionsPerSessionDelta: number | null;
}

export interface RevenueMomentum {
  headline: string;
  deltas: RevenueDelta;
  tone: RevenueInsightTone;
}

// Phase 3: Confidence
export type ConfidenceLabel = 'low' | 'medium' | 'high';

export interface RevenueConfidence {
  score: number; // 0..100
  label: ConfidenceLabel;
  reasons: string[];
}

// Phase 3: Stability
export type StabilityLabel = 'stable' | 'volatile' | 'emerging';

export interface RevenueStability {
  label: StabilityLabel;
  reasons: string[];
}

export interface RevenueInsightLanguage {
  headline: string;
  bullets: RevenueInsightBullet[];
  warnings: string[];
  recommendation: string | null;
  momentum: RevenueMomentum | null;
  confidence: RevenueConfidence;
  stability: RevenueStability;
  debug?: Record<string, unknown>;
}

export interface RevenueInsightContext {
  regionLabel: string;
  timeRangeLabel: string;
}

export interface BuildRevenueInsightArgs {
  mapData: RevenueGeoMapItem[];
  totals: RevenueGeoTotals;
  topCountries: RevenueGeoRow[];
  context: RevenueInsightContext;
  /** Previous period data for momentum comparison */
  previous?: RevenueGeoPreviousPeriod | null;
}

// =============================================================================
// HELPERS
// =============================================================================

function formatPercent(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function getCountryName(code: string): string {
  try {
    const displayNames = new Intl.DisplayNames(['en'], { type: 'region' });
    return displayNames.of(code) || code;
  } catch {
    return code;
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function safeDeltaPct(current: number, previous: number): number | null {
  if (previous === 0 && current === 0) return 0;
  if (previous === 0) return null; // Can't compute % change from 0
  return (current - previous) / previous;
}

// =============================================================================
// MOMENTUM COMPUTATION
// =============================================================================

function computeMomentum(
  currentTotals: RevenueGeoTotals,
  currentMapData: RevenueGeoMapItem[],
  currentTopCountries: RevenueGeoRow[],
  previous: RevenueGeoPreviousPeriod | null
): RevenueMomentum | null {
  if (!previous) return null;

  const prevTotals = previous.totals;
  const prevMapData = previous.mapData;
  const prevTopCountries = previous.topCountries;

  // Compute deltas
  const sessionsDeltaPct = safeDeltaPct(currentTotals.sessions, prevTotals.sessions);
  const impressionsDeltaPct = safeDeltaPct(currentTotals.adImpressions, prevTotals.adImpressions);
  
  const curActive = currentMapData.length;
  const prevActive = prevMapData.length;
  const activeCountriesDelta = curActive - prevActive;

  // Top 1 concentration change (in percentage points)
  const curTop1Share = currentTotals.sessions > 0 && currentTopCountries[0]
    ? currentTopCountries[0].sessions / currentTotals.sessions
    : 0;
  const prevTop1Share = prevTotals.sessions > 0 && prevTopCountries[0]
    ? prevTopCountries[0].sessions / prevTotals.sessions
    : 0;
  const concentrationTop1DeltaPctPoints = curTop1Share - prevTop1Share;

  // Impressions per session change
  const curImpPerSession = currentTotals.sessions > 0
    ? currentTotals.adImpressions / currentTotals.sessions
    : 0;
  const prevImpPerSession = prevTotals.sessions > 0
    ? prevTotals.adImpressions / prevTotals.sessions
    : 0;
  const impressionsPerSessionDelta = curImpPerSession - prevImpPerSession;

  const deltas: RevenueDelta = {
    sessionsDeltaPct,
    impressionsDeltaPct,
    activeCountriesDelta,
    concentrationTop1DeltaPctPoints,
    impressionsPerSessionDelta,
  };

  // Determine headline and tone based on sessions change
  let headline: string;
  let tone: RevenueInsightTone = 'neutral';

  const curSessions = currentTotals.sessions;
  const prevSessions = prevTotals.sessions;

  if (curSessions >= prevSessions * 1.25) {
    headline = 'Momentum is accelerating vs the previous period.';
    tone = 'good';
  } else if (curSessions <= prevSessions * 0.8 && prevSessions > 0) {
    headline = 'Momentum is slowing vs the previous period.';
    tone = 'warn';
  } else {
    headline = 'Momentum is steady vs the previous period.';
    tone = 'neutral';
  }

  return { headline, deltas, tone };
}

// =============================================================================
// CONFIDENCE COMPUTATION
// =============================================================================

function computeConfidence(
  currentTotals: RevenueGeoTotals,
  currentMapData: RevenueGeoMapItem[],
  currentTopCountries: RevenueGeoRow[],
  previous: RevenueGeoPreviousPeriod | null
): RevenueConfidence {
  let score = 0;
  const reasons: string[] = [];

  const curSessions = currentTotals.sessions;
  const activeCountries = currentMapData.length;
  const prevSessions = previous?.totals.sessions ?? 0;

  // Sessions scoring
  if (curSessions >= 30) {
    score += 30;
    reasons.push('Enough sessions for a stable signal.');
  } else if (curSessions >= 15) {
    score += 20;
    reasons.push('Moderate session volume.');
  } else if (curSessions >= 5) {
    score += 10;
    reasons.push('Some session data available.');
  }

  // Penalize very low sessions
  if (curSessions < 5) {
    score -= 20;
    reasons.push('Very few sessions recorded.');
  }

  // Country coverage scoring
  if (activeCountries >= 5) {
    score += 20;
    reasons.push('Footprint spans multiple countries.');
  } else if (activeCountries >= 2) {
    score += 10;
    reasons.push('Activity in a few countries.');
  }

  // Penalize single country
  if (activeCountries === 1) {
    score -= 10;
    reasons.push('Single-country data only.');
  }

  // Previous period baseline scoring
  if (previous && prevSessions >= 10) {
    score += 20;
    reasons.push('Previous period baseline available.');
  } else if (previous && prevSessions > 0) {
    score += 10;
    reasons.push('Comparison baseline is small.');
  }

  // Concentration scoring
  const top1Share = curSessions > 0 && currentTopCountries[0]
    ? currentTopCountries[0].sessions / curSessions
    : 0;
  if (top1Share < 0.85 || activeCountries >= 5) {
    score += 10;
    reasons.push('Diversified footprint reduces concentration risk.');
  }

  // Clamp and label
  score = clamp(score, 0, 100);
  
  let label: ConfidenceLabel;
  if (score >= 70) {
    label = 'high';
  } else if (score >= 40) {
    label = 'medium';
  } else {
    label = 'low';
  }

  return { score, label, reasons };
}

// =============================================================================
// STABILITY COMPUTATION
// =============================================================================

function computeStability(
  currentTotals: RevenueGeoTotals,
  currentMapData: RevenueGeoMapItem[],
  currentTopCountries: RevenueGeoRow[]
): RevenueStability {
  const activeCountries = currentMapData.length;
  const curSessions = currentTotals.sessions;
  const reasons: string[] = [];

  // Long tail: countries with very few sessions
  const longTailCount = currentMapData.filter(c => c.sessions <= 2).length;
  const longTailRatio = activeCountries > 0 ? longTailCount / activeCountries : 0;

  // Top 1 concentration
  const top1Share = curSessions > 0 && currentTopCountries[0]
    ? currentTopCountries[0].sessions / curSessions
    : 0;

  // Determine stability label
  let label: StabilityLabel;

  if (activeCountries <= 2 && curSessions <= 10) {
    label = 'emerging';
    if (activeCountries === 1) {
      reasons.push('Single-country footprint.');
    } else {
      reasons.push('Limited footprint, still ramping up.');
    }
    if (curSessions <= 10) {
      reasons.push('Low session volume.');
    }
  } else if (top1Share >= 0.85) {
    label = 'volatile';
    reasons.push('Heavily dependent on one country.');
  } else if (longTailRatio >= 0.7) {
    label = 'volatile';
    reasons.push('Many countries with minimal activity.');
  } else {
    label = 'stable';
    reasons.push('Balanced distribution across markets.');
  }

  return { label, reasons };
}

// =============================================================================
// INSIGHT BUILDER
// =============================================================================

export function buildRevenueInsightLanguage(args: BuildRevenueInsightArgs): RevenueInsightLanguage {
  const { mapData, totals, topCountries, context, previous = null } = args;

  // ==========================================================================
  // COMPUTE CORE METRICS
  // ==========================================================================

  const activeCountries = mapData.length;
  const totalSessions = totals.sessions;
  const totalImpressions = totals.adImpressions;
  const impressionsPerSession = totalSessions > 0 
    ? totalImpressions / totalSessions 
    : 0;

  // Top country concentration
  const top1Country = topCountries[0];
  const top1Sessions = top1Country?.sessions ?? 0;
  const top1SessionsShare = totalSessions > 0 ? top1Sessions / totalSessions : 0;
  const top1Name = top1Country ? getCountryName(top1Country.countryCode) : 'Unknown';

  // Top 3 concentration
  const top3Sessions = topCountries.slice(0, 3).reduce((sum, c) => sum + c.sessions, 0);
  const top3SessionsShare = totalSessions > 0 ? top3Sessions / totalSessions : 0;

  // Revenue status (currently all 0)
  const hasRevenue = totals.revenueTotal > 0;

  // Long tail: countries with very low sessions
  const longTailCount = mapData.filter(c => c.sessions <= 2).length;
  const longTailRatio = activeCountries > 0 ? longTailCount / activeCountries : 0;

  // ==========================================================================
  // PHASE 3: COMPUTE MOMENTUM, CONFIDENCE, STABILITY
  // ==========================================================================

  const momentum = computeMomentum(totals, mapData, topCountries, previous);
  const confidence = computeConfidence(totals, mapData, topCountries, previous);
  const stability = computeStability(totals, mapData, topCountries);

  // ==========================================================================
  // BUILD HEADLINE
  // ==========================================================================

  let headline: string;

  if (activeCountries === 0) {
    headline = `No activity detected in ${context.timeRangeLabel.toLowerCase()}.`;
  } else if (top1SessionsShare >= 0.75) {
    headline = `Activity is highly concentrated — most sessions come from ${top1Name}.`;
  } else if (activeCountries >= 8) {
    headline = `Footprint is expanding — activity spread across ${activeCountries} countries.`;
  } else {
    headline = `Activity is steady across ${activeCountries} countries.`;
  }

  // ==========================================================================
  // BUILD BULLETS
  // ==========================================================================

  const bullets: RevenueInsightBullet[] = [];

  // Active footprint
  if (activeCountries > 0) {
    bullets.push({
      label: 'Active footprint',
      value: `${activeCountries} ${activeCountries === 1 ? 'country' : 'countries'}`,
      tone: activeCountries >= 5 ? 'good' : 'neutral',
    });
  }

  // Top 1 concentration
  if (top1Country && totalSessions > 0) {
    const concTone: RevenueInsightTone = 
      top1SessionsShare >= 0.85 ? 'warn' : 
      top1SessionsShare <= 0.4 ? 'good' : 
      'neutral';
    
    bullets.push({
      label: `Concentration (${top1Country.countryCode})`,
      value: formatPercent(top1SessionsShare),
      tone: concTone,
    });
  }

  // Top 3 concentration
  if (topCountries.length >= 3 && totalSessions > 0) {
    bullets.push({
      label: 'Top 3 share',
      value: formatPercent(top3SessionsShare),
      tone: 'neutral',
    });
  }

  // Ad pressure (impressions per session)
  if (totalSessions > 0) {
    let pressureTone: RevenueInsightTone = 'neutral';
    if (impressionsPerSession > 1.2) pressureTone = 'warn';
    else if (impressionsPerSession < 0.4 && impressionsPerSession > 0) pressureTone = 'good';

    bullets.push({
      label: 'Ad pressure',
      value: `${impressionsPerSession.toFixed(2)} impr/session`,
      tone: pressureTone,
    });
  }

  // Monetization status
  if (!hasRevenue && activeCountries > 0) {
    bullets.push({
      label: 'Monetization',
      value: 'Using impressions density (revenue tracking pending)',
      tone: 'neutral',
    });
  }

  // ==========================================================================
  // BUILD WARNINGS
  // ==========================================================================

  const warnings: string[] = [];

  // Single-country dependence
  if (top1SessionsShare >= 0.85) {
    warnings.push('Single-country dependence risk: one country drives most activity.');
  }

  // High ad pressure
  if (impressionsPerSession > 1.5) {
    warnings.push('High ad pressure risk: users may experience fatigue.');
  }

  // Traffic without impressions
  if (totalSessions > 20 && totalImpressions === 0) {
    warnings.push('Traffic without impressions: ad triggers may be misconfigured.');
  }

  // ==========================================================================
  // BUILD RECOMMENDATION
  // ==========================================================================

  let recommendation: string | null = null;

  if (activeCountries <= 2 && activeCountries > 0) {
    recommendation = 'Increase distribution: test share cards or prompts to widen country coverage.';
  } else if (top1SessionsShare >= 0.85) {
    recommendation = 'Reduce concentration: run lightweight campaigns in 2-3 adjacent regions.';
  } else if (impressionsPerSession > 1.5) {
    recommendation = 'Lower ad pressure: adjust trigger/share assumptions by region.';
  } else if (activeCountries > 0) {
    recommendation = 'Focus on traffic growth: monetization is not the current bottleneck.';
  }

  // ==========================================================================
  // RETURN
  // ==========================================================================

  return {
    headline,
    bullets,
    warnings,
    recommendation,
    momentum,
    confidence,
    stability,
    debug: {
      activeCountries,
      totalSessions,
      totalImpressions,
      impressionsPerSession,
      top1SessionsShare,
      top3SessionsShare,
      longTailRatio,
      hasPrevious: !!previous,
    },
  };
}
