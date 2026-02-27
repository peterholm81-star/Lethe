/**
 * Revenue Narrative Engine (Phase 5B)
 * 
 * Generates investor-grade executive summaries by combining
 * Revenue, Mood, and Geo insights into deterministic narratives.
 * 
 * No AI, no external services. Pure rule-based logic.
 */

import type { RevenueInsightLanguage } from './revenueInsightLanguage';
import type { RevenueMoodCorrelation } from './revenueMoodCorrelation';
import type { RevenueGeoTotals } from '../../hooks/useRevenueGeo';

// =============================================================================
// TYPES
// =============================================================================

export type RevenueNarrativeTone = 'positive' | 'neutral' | 'risk';

export interface RevenueNarrative {
  headline: string;
  summary: string;
  drivers: string[];
  risks: string[];
  opportunity?: string;
  tone: RevenueNarrativeTone;
}

export interface BuildRevenueNarrativeArgs {
  geoInsight: RevenueInsightLanguage | null;
  correlation: RevenueMoodCorrelation | null;
  totals: RevenueGeoTotals | null;
}

// =============================================================================
// SIGNAL COMPUTATION
// =============================================================================

interface NarrativeSignals {
  growth: boolean;
  stable: boolean;
  risk: boolean;
  moodSupport: 'positive' | 'negative' | 'neutral';
  activeCountries: number;
  momentumLabel: string;
  lowConfidence: boolean;
  lowImpressionDensity: boolean;
  moodImproving: boolean;
  revenueFlat: boolean;
}

function computeSignals(args: BuildRevenueNarrativeArgs): NarrativeSignals | null {
  const { geoInsight, correlation, totals } = args;

  // Need at least geo insight to generate narrative
  if (!geoInsight) return null;

  // 1) Growth signal
  const growth = geoInsight.momentum?.tone === 'good';

  // 2) Stability
  const stable = geoInsight.stability.label === 'stable';

  // 3) Risk concentration
  const hasConcentrationWarning = geoInsight.bullets.some(
    b => b.label.toLowerCase().includes('concentration') && b.tone === 'warn'
  );
  const hasWarnings = geoInsight.warnings.length > 0;
  const risk = hasConcentrationWarning || hasWarnings;

  // 4) Mood support
  let moodSupport: 'positive' | 'negative' | 'neutral' = 'neutral';
  if (correlation) {
    if (correlation.signal === 'tailwind') {
      moodSupport = 'positive';
    } else if (correlation.signal === 'headwind' || correlation.signal === 'controversy') {
      moodSupport = 'negative';
    }
  }

  // Active countries from debug data
  const activeCountries = (geoInsight.debug?.activeCountries as number) || 0;

  // Momentum label
  let momentumLabel = 'steady';
  if (geoInsight.momentum) {
    if (geoInsight.momentum.tone === 'good') {
      momentumLabel = 'accelerating';
    } else if (geoInsight.momentum.tone === 'warn') {
      momentumLabel = 'slowing';
    }
  }

  // Low confidence
  const lowConfidence = geoInsight.confidence.label === 'low';

  // Low impression density (from debug data)
  const impressionsPerSession = (geoInsight.debug?.impressionsPerSession as number) || 0;
  const lowImpressionDensity = impressionsPerSession < 0.5 && totals ? totals.sessions > 10 : false;

  // Mood improving but revenue flat
  const moodImproving = correlation?.signal === 'opportunity';
  const revenueFlat = geoInsight.momentum?.tone === 'neutral' || !geoInsight.momentum;

  return {
    growth,
    stable,
    risk,
    moodSupport,
    activeCountries,
    momentumLabel,
    lowConfidence,
    lowImpressionDensity,
    moodImproving,
    revenueFlat,
  };
}

// =============================================================================
// HEADLINE GENERATION
// =============================================================================

function generateHeadline(signals: NarrativeSignals): string {
  const { growth, stable, risk, moodSupport } = signals;

  // Priority order
  if (growth && stable) {
    return 'Revenue expansion supported by stable global adoption.';
  }

  if (growth && risk) {
    return 'Growth accelerating but concentrated geographically.';
  }

  if (!growth && moodSupport === 'negative') {
    return 'Revenue slowdown aligns with declining sentiment.';
  }

  if (growth) {
    return 'Revenue activity expanding across markets.';
  }

  if (risk && !growth) {
    return 'Revenue steady but geographic concentration poses risk.';
  }

  return 'Revenue activity remains steady across markets.';
}

// =============================================================================
// SUMMARY GENERATION
// =============================================================================

function generateSummary(signals: NarrativeSignals): string {
  const { activeCountries, momentumLabel, moodSupport } = signals;

  const countryLabel = activeCountries === 1 
    ? '1 country' 
    : `${activeCountries} countries`;

  const moodLabel = moodSupport === 'positive'
    ? 'support'
    : moodSupport === 'negative'
    ? 'lag behind'
    : 'track alongside';

  if (activeCountries === 0) {
    return 'No activity detected in the current period. Awaiting data.';
  }

  return `Activity spans ${countryLabel} with ${momentumLabel} momentum. Emotional signals currently ${moodLabel} monetization trends.`;
}

// =============================================================================
// DRIVERS GENERATION
// =============================================================================

function generateDrivers(signals: NarrativeSignals): string[] {
  const drivers: string[] = [];

  if (signals.growth) {
    drivers.push('Expansion across multiple regions');
  }

  if (signals.moodSupport === 'positive') {
    drivers.push('Positive emotional momentum');
  }

  if (signals.stable) {
    drivers.push('Balanced geographic distribution');
  }

  if (signals.activeCountries >= 5 && !signals.risk) {
    drivers.push('Diversified market presence');
  }

  if (!signals.lowConfidence && signals.activeCountries > 0) {
    drivers.push('Sufficient data for reliable signals');
  }

  return drivers.slice(0, 3);
}

// =============================================================================
// RISKS GENERATION
// =============================================================================

function generateRisks(signals: NarrativeSignals): string[] {
  const risks: string[] = [];

  if (signals.risk) {
    risks.push('Revenue concentrated in few markets');
  }

  if (signals.moodSupport === 'negative') {
    risks.push('Weak emotional alignment');
  }

  if (signals.lowConfidence) {
    risks.push('Low data confidence — signals may shift');
  }

  if (signals.activeCountries <= 2 && signals.activeCountries > 0) {
    risks.push('Limited geographic reach');
  }

  return risks.slice(0, 3);
}

// =============================================================================
// OPPORTUNITY GENERATION
// =============================================================================

function generateOpportunity(signals: NarrativeSignals): string | undefined {
  const { growth, lowImpressionDensity, moodImproving, revenueFlat } = signals;

  if (growth && lowImpressionDensity) {
    return 'Improve monetization efficiency before scaling traffic.';
  }

  if (moodImproving && revenueFlat) {
    return 'Sentiment improving — monetization upside forming.';
  }

  if (signals.stable && !signals.risk && signals.activeCountries >= 3) {
    return 'Healthy foundation for scaling ad frequency or premium features.';
  }

  return undefined;
}

// =============================================================================
// TONE CLASSIFICATION
// =============================================================================

function classifyTone(signals: NarrativeSignals): RevenueNarrativeTone {
  const { growth, risk, moodSupport } = signals;

  // Positive: growth without significant risk
  if (growth && !risk && moodSupport !== 'negative') {
    return 'positive';
  }

  // Risk: has risk factors or negative mood alignment
  if (risk || moodSupport === 'negative') {
    return 'risk';
  }

  return 'neutral';
}

// =============================================================================
// MAIN BUILDER
// =============================================================================

export function buildRevenueNarrative(args: BuildRevenueNarrativeArgs): RevenueNarrative | null {
  const signals = computeSignals(args);

  // Insufficient data
  if (!signals) return null;
  if (signals.activeCountries === 0 && !args.totals) return null;

  const headline = generateHeadline(signals);
  const summary = generateSummary(signals);
  const drivers = generateDrivers(signals);
  const risks = generateRisks(signals);
  const opportunity = generateOpportunity(signals);
  const tone = classifyTone(signals);

  return {
    headline,
    summary,
    drivers,
    risks,
    opportunity,
    tone,
  };
}
