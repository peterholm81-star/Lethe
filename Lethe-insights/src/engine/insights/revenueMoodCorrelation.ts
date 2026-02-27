/**
 * Revenue × Mood Correlation Engine (Phase 4)
 * 
 * Correlates Revenue momentum with Mood momentum to generate
 * investor-grade insights about emotional context of monetization.
 * 
 * Deterministic: no AI calls, no external services.
 */

// =============================================================================
// TYPES
// =============================================================================

export type CorrelationTone = 'good' | 'neutral' | 'warn';

export type CorrelationSignal = 
  | 'tailwind'      // Revenue up + mood improving
  | 'headwind'      // Revenue down + mood worsening
  | 'controversy'   // Revenue up + mood worsening
  | 'opportunity'   // Mood improving + revenue flat
  | 'unclear';      // Not enough data

export interface CorrelationBullet {
  label: string;
  value: string;
  tone?: CorrelationTone;
}

export interface CorrelationConfidence {
  score: number;        // 0..100
  label: 'low' | 'medium' | 'high';
  reasons: string[];
}

export interface RevenueMoodCorrelation {
  headline: string;
  bullets: CorrelationBullet[];
  signal: CorrelationSignal;
  confidence: CorrelationConfidence;
  debug?: Record<string, unknown>;
}

// =============================================================================
// INPUT TYPES
// =============================================================================

export interface RevenueInput {
  currentSessions: number;
  previousSessions?: number;
  currentActiveCountries: number;
  previousActiveCountries?: number;
}

export interface MoodInput {
  currentBalance: number;      // -1 to +1 scale
  previousBalance?: number;    // -1 to +1 scale
  currentTotal: number;        // total confessions
  previousTotal?: number;
  deltaBalance?: number;       // pre-computed delta if available
}

export interface CorrelationContext {
  regionLabel: string;
  timeRangeLabel: string;
}

export interface BuildCorrelationArgs {
  revenue: RevenueInput;
  mood: MoodInput;
  context: CorrelationContext;
}

// =============================================================================
// HELPERS
// =============================================================================

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function formatPct(value: number, showPlus = true): string {
  const pct = (value * 100).toFixed(0);
  return showPlus && value > 0 ? `+${pct}%` : `${pct}%`;
}

function formatBalance(value: number): string {
  return value >= 0 ? `+${value.toFixed(2)}` : value.toFixed(2);
}

// =============================================================================
// MOMENTUM COMPUTATION
// =============================================================================

function computeRevenueMomentum(
  current: number,
  previous: number | undefined
): { deltaPct: number | null; direction: 'up' | 'down' | 'flat' } {
  if (previous === undefined || previous === 0) {
    return { deltaPct: null, direction: 'flat' };
  }
  
  const deltaPct = (current - previous) / previous;
  
  let direction: 'up' | 'down' | 'flat' = 'flat';
  if (deltaPct >= 0.10) direction = 'up';
  else if (deltaPct <= -0.10) direction = 'down';
  
  return { deltaPct, direction };
}

function computeMoodMomentum(
  currentBalance: number,
  previousBalance: number | undefined,
  precomputedDelta?: number
): { delta: number | null; direction: 'improving' | 'worsening' | 'steady' } {
  // Use pre-computed delta if available
  if (precomputedDelta !== undefined) {
    let direction: 'improving' | 'worsening' | 'steady' = 'steady';
    if (precomputedDelta > 0.05) direction = 'improving';
    else if (precomputedDelta < -0.05) direction = 'worsening';
    return { delta: precomputedDelta, direction };
  }
  
  if (previousBalance === undefined) {
    return { delta: null, direction: 'steady' };
  }
  
  const delta = currentBalance - previousBalance;
  
  let direction: 'improving' | 'worsening' | 'steady' = 'steady';
  if (delta > 0.05) direction = 'improving';
  else if (delta < -0.05) direction = 'worsening';
  
  return { delta, direction };
}

// =============================================================================
// SIGNAL DETECTION
// =============================================================================

function detectSignal(
  revenueDeltaPct: number | null,
  moodDirection: 'improving' | 'worsening' | 'steady',
  hasEnoughData: boolean
): CorrelationSignal {
  if (!hasEnoughData || revenueDeltaPct === null) {
    return 'unclear';
  }
  
  // TAILWIND: Revenue up + mood improving
  if (revenueDeltaPct >= 0.20 && moodDirection === 'improving') {
    return 'tailwind';
  }
  
  // HEADWIND: Revenue down + mood worsening
  if (revenueDeltaPct <= -0.20 && moodDirection === 'worsening') {
    return 'headwind';
  }
  
  // CONTROVERSY: Revenue up + mood worsening
  if (revenueDeltaPct >= 0.20 && moodDirection === 'worsening') {
    return 'controversy';
  }
  
  // OPPORTUNITY: Mood improving + revenue flat
  if (moodDirection === 'improving' && revenueDeltaPct > -0.10 && revenueDeltaPct < 0.10) {
    return 'opportunity';
  }
  
  return 'unclear';
}

// =============================================================================
// HEADLINE GENERATION
// =============================================================================

function generateHeadline(signal: CorrelationSignal): string {
  switch (signal) {
    case 'tailwind':
      return 'Positive emotional tailwind — activity is rising as mood improves.';
    case 'headwind':
      return 'Emotional headwind — activity is falling as mood worsens.';
    case 'controversy':
      return 'Engagement is rising while mood worsens — activity may be controversy-driven.';
    case 'opportunity':
      return 'Mood is improving, but activity is flat — potential growth opportunity.';
    case 'unclear':
    default:
      return 'Not enough data to connect mood and monetization signals yet.';
  }
}

// =============================================================================
// CONFIDENCE COMPUTATION
// =============================================================================

function computeConfidence(
  revenue: RevenueInput,
  mood: MoodInput
): CorrelationConfidence {
  let score = 0;
  const reasons: string[] = [];
  
  const hasPrevRevenue = revenue.previousSessions !== undefined && revenue.previousSessions > 0;
  const hasPrevMood = mood.previousBalance !== undefined || mood.deltaBalance !== undefined;
  
  // Revenue data sufficiency
  if (hasPrevRevenue && revenue.previousSessions! >= 15 && revenue.currentSessions >= 15) {
    score += 30;
    reasons.push('Enough sessions for comparison.');
  } else if (revenue.currentSessions >= 10) {
    score += 15;
    reasons.push('Moderate session volume.');
  }
  
  // Mood data sufficiency
  if (mood.currentTotal >= 50 && (mood.previousTotal ?? 0) >= 50) {
    score += 30;
    reasons.push('Sufficient mood sample size.');
  } else if (mood.currentTotal >= 20) {
    score += 15;
    reasons.push('Some mood data available.');
  } else {
    reasons.push('Mood sample size is small.');
  }
  
  // Both comparison periods exist
  if (hasPrevRevenue && hasPrevMood) {
    score += 20;
  }
  
  // Penalties for tiny data
  if (revenue.currentSessions < 5) {
    score -= 20;
    reasons.push('Very few sessions recorded.');
  }
  if (mood.currentTotal < 20) {
    score -= 20;
  }
  
  // Clamp score
  score = clamp(score, 0, 100);
  
  // Determine label
  let label: 'low' | 'medium' | 'high';
  if (score >= 70) {
    label = 'high';
  } else if (score >= 40) {
    label = 'medium';
  } else {
    label = 'low';
  }
  
  return { score, label, reasons: reasons.slice(0, 3) };
}

// =============================================================================
// BULLET GENERATION
// =============================================================================

function generateBullets(
  revenue: RevenueInput,
  mood: MoodInput,
  revenueMomentum: { deltaPct: number | null; direction: 'up' | 'down' | 'flat' },
  moodMomentum: { delta: number | null; direction: 'improving' | 'worsening' | 'steady' }
): CorrelationBullet[] {
  const bullets: CorrelationBullet[] = [];
  
  // Revenue momentum bullet
  if (revenueMomentum.deltaPct !== null) {
    let tone: CorrelationTone = 'neutral';
    if (revenueMomentum.deltaPct >= 0.10) tone = 'good';
    else if (revenueMomentum.deltaPct <= -0.10) tone = 'warn';
    
    bullets.push({
      label: 'Revenue momentum',
      value: `${formatPct(revenueMomentum.deltaPct)} sessions vs prior`,
      tone,
    });
  }
  
  // Mood momentum bullet
  if (moodMomentum.delta !== null) {
    let tone: CorrelationTone = 'neutral';
    if (moodMomentum.direction === 'improving') tone = 'good';
    else if (moodMomentum.direction === 'worsening') tone = 'warn';
    
    const dirLabel = moodMomentum.direction === 'improving' ? 'improving'
      : moodMomentum.direction === 'worsening' ? 'worsening' 
      : 'steady';
    
    bullets.push({
      label: 'Mood momentum',
      value: `${formatBalance(moodMomentum.delta)} (${dirLabel})`,
      tone,
    });
  }
  
  // Current mood balance bullet
  bullets.push({
    label: 'Current mood balance',
    value: formatBalance(mood.currentBalance),
    tone: mood.currentBalance >= 0.1 ? 'good' 
      : mood.currentBalance <= -0.1 ? 'warn' 
      : 'neutral',
  });
  
  // Sample size bullet
  if (mood.currentTotal > 0) {
    let tone: CorrelationTone = 'neutral';
    if (mood.currentTotal < 30) tone = 'warn';
    else if (mood.currentTotal >= 100) tone = 'good';
    
    bullets.push({
      label: 'Mood sample',
      value: `${mood.currentTotal} classified events`,
      tone,
    });
  }
  
  return bullets.slice(0, 4);
}

// =============================================================================
// MAIN BUILDER
// =============================================================================

export function buildRevenueMoodCorrelation(args: BuildCorrelationArgs): RevenueMoodCorrelation {
  const { revenue, mood, context } = args;
  
  // Compute momentum for both series
  const revenueMomentum = computeRevenueMomentum(
    revenue.currentSessions,
    revenue.previousSessions
  );
  
  const moodMomentum = computeMoodMomentum(
    mood.currentBalance,
    mood.previousBalance,
    mood.deltaBalance
  );
  
  // Compute confidence
  const confidence = computeConfidence(revenue, mood);
  
  // Determine if we have enough data
  const hasEnoughData = confidence.score >= 30;
  
  // Detect signal
  const signal = detectSignal(
    revenueMomentum.deltaPct,
    moodMomentum.direction,
    hasEnoughData
  );
  
  // Generate headline
  const headline = generateHeadline(signal);
  
  // Generate bullets
  const bullets = generateBullets(revenue, mood, revenueMomentum, moodMomentum);
  
  return {
    headline,
    bullets,
    signal,
    confidence,
    debug: {
      revenueDeltaPct: revenueMomentum.deltaPct,
      revenueDirection: revenueMomentum.direction,
      moodDelta: moodMomentum.delta,
      moodDirection: moodMomentum.direction,
      confidenceScore: confidence.score,
      regionLabel: context.regionLabel,
      timeRangeLabel: context.timeRangeLabel,
    },
  };
}
