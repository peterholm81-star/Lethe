/**
 * SeasonalityWheelV2 — Multi-layer Year Wheel
 *
 * Three visual encodings per month-segment:
 *   1. Sessions  = OUTER radius (taller wedge = more sessions)
 *   2. Posts/ses = MID band thickness (thicker = higher engagement)
 *   3. Mood      = Glow color (green = positive, red = negative, gray = neutral/null)
 *
 * Instant-insight features (no hover required):
 *   - Radial tick circles at 33/66/100% scale on sessions ring
 *   - Inline value labels on peak and low months
 *   - Seasonality Summary panel alongside the wheel
 *
 * DualSeasonalityWheels renders A and B side-by-side when Compare is enabled.
 */

import { useState, useMemo, useRef, useCallback } from 'react';
import type { YearWheelMonth } from '../../hooks/useYearWheelV1';

// =============================================================================
// CONSTANTS
// =============================================================================

const SIZE = 290;
const CX = SIZE / 2;
const CY = SIZE / 2;

const OUTER_BASE = 100;
const OUTER_AMP = 30;
const OUTER_BAND = 22;

const MID_OUTER_BASE = OUTER_BASE - OUTER_BAND - 4;
const MID_THICKNESS_MIN = 8;
const MID_THICKNESS_AMP = 14;

const INNER_OUTER = MID_OUTER_BASE - MID_THICKNESS_MIN - MID_THICKNESS_AMP - 4;
const INNER_BAND = 16;

const SEGMENTS = 12;
const SEG_DEG = 360 / SEGMENTS;
const GAP_DEG = 1.8;

const LABEL_R = OUTER_BASE + OUTER_AMP + 12;
const HOVER_GRACE_MS = 80;

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Radial tick levels (fraction of OUTER_AMP)
const TICK_LEVELS = [0.33, 0.66, 1.0];

// =============================================================================
// POLAR MATH
// =============================================================================

function toRad(deg: number): number { return (deg * Math.PI) / 180; }

function polarXY(cx: number, cy: number, r: number, deg: number): [number, number] {
  const rad = toRad(deg - 90);
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

function arcPath(
  cx: number, cy: number,
  rOuter: number, rInner: number,
  startDeg: number, endDeg: number,
): string {
  const s = toRad(startDeg - 90);
  const e = toRad(endDeg - 90);
  const large = endDeg - startDeg > 180 ? 1 : 0;
  const ox1 = cx + rOuter * Math.cos(s), oy1 = cy + rOuter * Math.sin(s);
  const ox2 = cx + rOuter * Math.cos(e), oy2 = cy + rOuter * Math.sin(e);
  const ix1 = cx + rInner * Math.cos(e), iy1 = cy + rInner * Math.sin(e);
  const ix2 = cx + rInner * Math.cos(s), iy2 = cy + rInner * Math.sin(s);
  return [
    `M${n(ox1)},${n(oy1)}`,
    `A${rOuter},${rOuter} 0 ${large} 1 ${n(ox2)},${n(oy2)}`,
    `L${n(ix1)},${n(iy1)}`,
    `A${rInner},${rInner} 0 ${large} 0 ${n(ix2)},${n(iy2)}`,
    'Z',
  ].join(' ');
}

function n(v: number): string { return v.toFixed(2); }
function clamp01(v: number): number { return Math.max(0, Math.min(1, v)); }
function lerp(a: number, b: number, t: number): number { return a + (b - a) * clamp01(t); }

function fmtCompact(v: number): string {
  if (v >= 10000) return `${(v / 1000).toFixed(0)}k`;
  if (v >= 1000) return `${(v / 1000).toFixed(1)}k`;
  return String(Math.round(v));
}

function fmtBal(b: number | null): string {
  if (b == null) return '—';
  return (b >= 0 ? '+' : '') + b.toFixed(3);
}

function fmtBalShort(b: number | null): string {
  if (b == null) return '—';
  return (b >= 0 ? '+' : '') + b.toFixed(2);
}

// =============================================================================
// COLORS
// =============================================================================

function sessionsColor(t: number): string {
  return `rgba(70,155,255,${lerp(0.15, 0.8, t).toFixed(2)})`;
}

function ppsColor(t: number): string {
  return `rgba(155,95,220,${lerp(0.15, 0.8, t).toFixed(2)})`;
}

function moodFill(balance: number | null): string {
  if (balance == null) return 'rgba(255,255,255,0.06)';
  if (balance > 0.15) return `rgba(70,200,120,${lerp(0.25, 0.8, balance).toFixed(2)})`;
  if (balance < -0.15) return `rgba(220,80,80,${lerp(0.25, 0.8, Math.abs(balance)).toFixed(2)})`;
  return 'rgba(255,255,255,0.12)';
}

function moodGlow(balance: number | null): string {
  if (balance == null) return 'none';
  if (balance > 0.15) return `rgba(70,200,120,${lerp(0.1, 0.5, balance).toFixed(2)})`;
  if (balance < -0.15) return `rgba(220,80,80,${lerp(0.1, 0.5, Math.abs(balance)).toFixed(2)})`;
  return 'none';
}

// =============================================================================
// DATA PREP
// =============================================================================

function toCalendar(data: YearWheelMonth[]): YearWheelMonth[] {
  const byMonth = new Map<number, YearWheelMonth>();
  for (const d of data) {
    if (!d.monthStart) continue;
    const m = new Date(d.monthStart + 'T00:00:00Z').getUTCMonth();
    byMonth.set(m, d);
  }
  const empty: YearWheelMonth = { monthStart: '', sessions: 0, posts: 0, postsPerSession: null, moodPos: 0, moodNeg: 0, moodBalance: null };
  return Array.from({ length: 12 }, (_, i) => byMonth.get(i) ?? { ...empty });
}

interface MarkerSet {
  peakSessions: number | null;
  lowSessions: number | null;
  peakPps: number | null;
  bestMood: number | null;
  worstMood: number | null;
}

function findMarkers(months: YearWheelMonth[]): MarkerSet {
  let peakSI = -1, lowSI = -1, peakPI = -1, bestMI = -1, worstMI = -1;
  let maxS = -1, minS = Infinity, maxP = -1, maxMood = -Infinity, minMood = Infinity;
  const hasSessions = months.some(m => m.sessions > 0);

  for (let i = 0; i < 12; i++) {
    const m = months[i];
    if (m.sessions > maxS) { maxS = m.sessions; peakSI = i; }
    if (hasSessions && m.sessions > 0 && m.sessions < minS) { minS = m.sessions; lowSI = i; }
    const pps = m.postsPerSession ?? 0;
    if (pps > maxP) { maxP = pps; peakPI = i; }
    if (m.moodBalance != null) {
      if (m.moodBalance > maxMood) { maxMood = m.moodBalance; bestMI = i; }
      if (m.moodBalance < minMood) { minMood = m.moodBalance; worstMI = i; }
    }
  }

  return {
    peakSessions: maxS > 0 ? peakSI : null,
    lowSessions: hasSessions && lowSI !== peakSI ? lowSI : null,
    peakPps: maxP > 0 ? peakPI : null,
    bestMood: maxMood > -Infinity ? bestMI : null,
    worstMood: minMood < Infinity && worstMI !== bestMI ? worstMI : null,
  };
}

function getGlyphs(i: number, mk: MarkerSet): string[] {
  const g: string[] = [];
  if (mk.peakSessions === i) g.push('★');
  if (mk.lowSessions === i) g.push('▽');
  if (mk.peakPps === i) g.push('⚡');
  if (mk.bestMood === i) g.push('☺');
  if (mk.worstMood === i) g.push('☹');
  return g;
}

// =============================================================================
// SEASONALITY SUMMARY (right-side block)
// =============================================================================

function SeasonalitySummary({ months, mk }: { months: YearWheelMonth[]; mk: MarkerSet }) {
  const rows: { icon: string; label: string; value: string; color: string }[] = [];

  if (mk.peakSessions != null) {
    const m = months[mk.peakSessions];
    rows.push({ icon: '★', label: `Peak traffic · ${MONTH_LABELS[mk.peakSessions]}`, value: fmtCompact(m.sessions), color: '#469bff' });
  }
  if (mk.lowSessions != null) {
    const m = months[mk.lowSessions];
    rows.push({ icon: '▽', label: `Low traffic · ${MONTH_LABELS[mk.lowSessions]}`, value: fmtCompact(m.sessions), color: 'rgba(255,255,255,0.45)' });
  }
  if (mk.peakPps != null) {
    const m = months[mk.peakPps];
    rows.push({ icon: '⚡', label: `Peak posts/ses · ${MONTH_LABELS[mk.peakPps]}`, value: m.postsPerSession?.toFixed(2) ?? '—', color: '#9b5fdc' });
  }
  if (mk.bestMood != null) {
    const m = months[mk.bestMood];
    rows.push({ icon: '☺', label: `Best mood · ${MONTH_LABELS[mk.bestMood]}`, value: fmtBalShort(m.moodBalance), color: '#46c878' });
  }
  if (mk.worstMood != null) {
    const m = months[mk.worstMood];
    rows.push({ icon: '☹', label: `Worst mood · ${MONTH_LABELS[mk.worstMood]}`, value: fmtBalShort(m.moodBalance), color: '#dc5050' });
  }

  if (rows.length === 0) return null;

  return (
    <div style={st.summary}>
      <div style={st.summaryTitle}>Seasonality Summary</div>
      {rows.map((r, i) => (
        <div key={i} style={st.summaryRow}>
          <span style={{ fontSize: 11, width: 16, textAlign: 'center' as const, flexShrink: 0 }}>{r.icon}</span>
          <span style={st.summaryLabel}>{r.label}</span>
          <span style={{ ...st.summaryVal, color: r.color }}>{r.value}</span>
        </div>
      ))}
    </div>
  );
}

// =============================================================================
// SINGLE WHEEL
// =============================================================================

interface WheelProps {
  months: YearWheelMonth[];
  size?: number;
  compact?: boolean;
}

function Wheel({ months, size = SIZE, compact = false }: WheelProps) {
  const [hovered, setHovered] = useState<number | null>(null);
  const leaveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const enter = useCallback((i: number) => {
    if (leaveTimer.current) { clearTimeout(leaveTimer.current); leaveTimer.current = null; }
    setHovered(i);
  }, []);

  const leaveSegment = useCallback(() => {
    if (leaveTimer.current) clearTimeout(leaveTimer.current);
    leaveTimer.current = setTimeout(() => setHovered(null), HOVER_GRACE_MS);
  }, []);

  const leaveSvg = useCallback(() => {
    if (leaveTimer.current) clearTimeout(leaveTimer.current);
    setHovered(null);
  }, []);

  const maxSessions = useMemo(() => Math.max(...months.map(m => m.sessions), 1), [months]);
  const maxPps = useMemo(() => Math.max(...months.map(m => m.postsPerSession ?? 0), 0.01), [months]);
  const mk = useMemo(() => findMarkers(months), [months]);
  const allZero = useMemo(() => months.every(m => m.sessions === 0), [months]);

  // Which months get inline value labels (only peak + low sessions to avoid clutter)
  const inlineLabels = useMemo(() => {
    const set = new Set<number>();
    if (mk.peakSessions != null) set.add(mk.peakSessions);
    if (mk.lowSessions != null) set.add(mk.lowSessions);
    return set;
  }, [mk]);

  if (allZero) return <div style={st.empty}>No seasonality data yet</div>;

  const scale = size / SIZE;
  const filterId = `moodGlow_${size}`;

  return (
    <div style={{ display: 'flex', gap: compact ? 8 : 14, alignItems: 'flex-start', flexWrap: 'wrap' as const }}>
      <div style={st.wheelContainer}>
        <svg
          width={size}
          height={size}
          viewBox={`0 0 ${SIZE} ${SIZE}`}
          style={{ display: 'block' }}
          onPointerLeave={leaveSvg}
        >
          <defs>
            <filter id={filterId} x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* Radial tick circles for sessions scale */}
          {TICK_LEVELS.map((frac) => {
            const r = OUTER_BASE + frac * OUTER_AMP;
            return (
              <circle
                key={frac}
                cx={CX} cy={CY} r={r}
                fill="none"
                stroke="rgba(255,255,255,0.06)"
                strokeWidth={0.5}
                strokeDasharray={frac < 1 ? '2 4' : '3 3'}
                style={{ pointerEvents: 'none' }}
              />
            );
          })}

          {months.map((m, i) => {
            const startDeg = i * SEG_DEG + GAP_DEG / 2;
            const endDeg = (i + 1) * SEG_DEG - GAP_DEG / 2;

            const sNorm = clamp01(m.sessions / maxSessions);
            const pNorm = clamp01((m.postsPerSession ?? 0) / maxPps);

            const outerR = OUTER_BASE + sNorm * OUTER_AMP;
            const outerInnerR = outerR - OUTER_BAND;

            const midOuter = MID_OUTER_BASE;
            const midThick = MID_THICKNESS_MIN + pNorm * MID_THICKNESS_AMP;
            const midInner = midOuter - midThick;

            const innerOuter = INNER_OUTER;
            const innerInner = innerOuter - INNER_BAND;

            const isHovered = hovered === i;
            const dimmed = hovered != null && !isHovered;
            const glow = moodGlow(m.moodBalance);

            const hitOuterR = OUTER_BASE + OUTER_AMP + 2;
            const hitInnerR = innerInner - 1;

            return (
              <g
                key={i}
                style={{ opacity: dimmed ? 0.35 : 1, transition: 'opacity 0.15s ease' }}
              >
                <path
                  d={arcPath(CX, CY, hitOuterR, hitInnerR, startDeg, endDeg)}
                  fill="transparent" stroke="none"
                  style={{ cursor: 'default' }}
                  onPointerEnter={() => enter(i)}
                  onPointerLeave={leaveSegment}
                />
                <path
                  d={arcPath(CX, CY, outerR, outerInnerR, startDeg, endDeg)}
                  fill={sessionsColor(sNorm)}
                  stroke={isHovered ? 'rgba(255,255,255,0.2)' : 'rgba(255,255,255,0.04)'}
                  strokeWidth={isHovered ? 1 : 0.5}
                  style={{ pointerEvents: 'none' }}
                />
                <path
                  d={arcPath(CX, CY, midOuter, midInner, startDeg, endDeg)}
                  fill={ppsColor(pNorm)}
                  stroke="rgba(255,255,255,0.04)" strokeWidth={0.5}
                  style={{ pointerEvents: 'none' }}
                />
                <path
                  d={arcPath(CX, CY, innerOuter, innerInner, startDeg, endDeg)}
                  fill={moodFill(m.moodBalance)}
                  stroke={glow !== 'none' ? glow : 'rgba(255,255,255,0.03)'}
                  strokeWidth={glow !== 'none' ? 2 : 0.5}
                  filter={glow !== 'none' ? `url(#${filterId})` : undefined}
                  style={{ pointerEvents: 'none' }}
                />
              </g>
            );
          })}

          {/* Month labels */}
          {MONTH_LABELS.map((label, i) => {
            const midDeg = (i + 0.5) * SEG_DEG;
            const [lx, ly] = polarXY(CX, CY, LABEL_R, midDeg);
            const isKey = inlineLabels.has(i);
            return (
              <text
                key={label}
                x={lx} y={ly}
                textAnchor="middle" dominantBaseline="middle"
                fontSize={7.5 / scale}
                fontWeight={hovered === i || isKey ? 700 : 500}
                fill={hovered === i ? 'rgba(255,255,255,0.9)' : isKey ? 'rgba(255,255,255,0.7)' : 'rgba(255,255,255,0.38)'}
                style={{ transition: 'fill 0.12s ease', letterSpacing: '0.03em', pointerEvents: 'none' }}
              >
                {label}
              </text>
            );
          })}

          {/* Inline value labels for peak/low months */}
          {Array.from(inlineLabels).map(i => {
            const midDeg = (i + 0.5) * SEG_DEG;
            const sNorm = clamp01(months[i].sessions / maxSessions);
            const valR = OUTER_BASE + sNorm * OUTER_AMP + 22;
            const [vx, vy] = polarXY(CX, CY, valR, midDeg);
            const isPeak = mk.peakSessions === i;
            return (
              <text
                key={`val-${i}`}
                x={vx} y={vy}
                textAnchor="middle" dominantBaseline="middle"
                fontSize={7} fontWeight={700}
                fill={isPeak ? 'rgba(100,180,255,0.85)' : 'rgba(255,255,255,0.5)'}
                style={{ pointerEvents: 'none', fontVariantNumeric: 'tabular-nums' }}
              >
                {fmtCompact(months[i].sessions)}
              </text>
            );
          })}

          {/* Glyph markers */}
          {months.map((_, i) => {
            const glyphs = getGlyphs(i, mk);
            if (glyphs.length === 0) return null;
            const midDeg = (i + 0.5) * SEG_DEG;
            const sNorm = clamp01(months[i].sessions / maxSessions);
            const baseR = OUTER_BASE + sNorm * OUTER_AMP + 3;

            return glyphs.map((g, gi) => {
              const offsetDeg = (gi - (glyphs.length - 1) / 2) * 3;
              const [mx, my] = polarXY(CX, CY, baseR + gi * 5, midDeg + offsetDeg);
              return (
                <text
                  key={`mk-${i}-${gi}`}
                  x={mx} y={my}
                  textAnchor="middle" dominantBaseline="middle"
                  fontSize={8} style={{ pointerEvents: 'none' }}
                >
                  {g}
                </text>
              );
            });
          })}
        </svg>

        {hovered != null && <WheelTooltip month={months[hovered]} index={hovered} />}
      </div>

      {!compact && <SeasonalitySummary months={months} mk={mk} />}
    </div>
  );
}

// =============================================================================
// TOOLTIP
// =============================================================================

function WheelTooltip({ month: m, index }: { month: YearWheelMonth; index: number }) {
  return (
    <div style={st.tooltip}>
      <div style={st.tooltipTitle}>{MONTH_LABELS[index]}</div>
      <TRow dot="#469bff" label="Sessions" value={m.sessions.toLocaleString()} />
      <TRow dot="#9b5fdc" label="Posts" value={String(m.posts)} />
      <TRow dot="#9b5fdc" label="Posts / ses" value={m.postsPerSession?.toFixed(2) ?? '—'} />
      <TRow dot={moodFill(m.moodBalance)} label="Mood bal" value={fmtBal(m.moodBalance)} />
      <TRow dot="rgba(70,200,120,0.6)" label="Mood +" value={String(m.moodPos)} />
      <TRow dot="rgba(220,80,80,0.6)" label="Mood −" value={String(m.moodNeg)} />
    </div>
  );
}

function TRow({ dot, label, value }: { dot: string; label: string; value: string }) {
  return (
    <div style={st.tooltipRow}>
      <span style={{ ...st.dot, background: dot }} />
      <span>{label}</span>
      <span style={st.tooltipVal}>{value}</span>
    </div>
  );
}

// =============================================================================
// LEGEND
// =============================================================================

function Legend() {
  return (
    <div style={st.legend}>
      <LI color="#469bff" label="Sessions (radius)" />
      <LI color="#9b5fdc" label="Posts/ses (thickness)" />
      <LI color="#46c878" label="Mood +" />
      <LI color="#dc5050" label="Mood −" />
    </div>
  );
}

function LI({ color, label }: { color: string; label: string }) {
  return (
    <div style={st.legendItem}>
      <div style={{ width: 8, height: 8, borderRadius: 2, flexShrink: 0, background: color }} />
      <span>{label}</span>
    </div>
  );
}

// =============================================================================
// DUAL COMPARE WRAPPER (exported)
// =============================================================================

export interface DualSeasonalityWheelsProps {
  aData: YearWheelMonth[];
  bData: YearWheelMonth[] | null;
  aLabel?: string;
  bLabel?: string;
  loading: boolean;
  error: string | null;
}

export function DualSeasonalityWheels({
  aData, bData, aLabel, bLabel, loading, error,
}: DualSeasonalityWheelsProps) {
  const aMonths = useMemo(() => toCalendar(aData), [aData]);
  const bMonths = useMemo(() => bData ? toCalendar(bData) : null, [bData]);

  if (loading) return <div style={st.empty}>Loading seasonality...</div>;
  if (error) return <div style={{ ...st.empty, color: 'rgba(220,120,120,0.8)' }}>{error}</div>;

  const dual = bMonths != null;

  return (
    <div>
      {dual ? (
        <div style={st.dualGrid}>
          <div style={st.wheelColumn}>
            {aLabel && <div style={st.scopeLabel}>{aLabel}</div>}
            <Wheel months={aMonths} size={240} compact />
            <SeasonalitySummary months={aMonths} mk={findMarkers(aMonths)} />
          </div>
          <div style={st.wheelColumn}>
            {bLabel && <div style={{ ...st.scopeLabel, color: 'rgba(255,180,100,0.85)' }}>{bLabel}</div>}
            <Wheel months={bMonths} size={240} compact />
            <SeasonalitySummary months={bMonths} mk={findMarkers(bMonths)} />
          </div>
        </div>
      ) : (
        <Wheel months={aMonths} size={SIZE} />
      )}
      <Legend />
    </div>
  );
}

// =============================================================================
// STYLES
// =============================================================================

const st = {
  empty: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.3)',
    padding: '24px 0',
    textAlign: 'center' as const,
  },
  wheelContainer: {
    position: 'relative' as const,
    flexShrink: 0,
  },
  tooltip: {
    position: 'absolute' as const,
    top: 4,
    right: 4,
    background: 'rgba(10,10,16,0.94)',
    border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 8,
    padding: '10px 14px',
    minWidth: 150,
    backdropFilter: 'blur(10px)',
    zIndex: 10,
    pointerEvents: 'none' as const,
  },
  tooltipTitle: {
    fontSize: 11,
    fontWeight: 700 as const,
    color: 'rgba(255,255,255,0.85)',
    marginBottom: 6,
    letterSpacing: '0.04em',
  },
  tooltipRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 9,
    color: 'rgba(255,255,255,0.5)',
    padding: '1.5px 0',
  },
  tooltipVal: {
    marginLeft: 'auto' as const,
    fontWeight: 600 as const,
    color: 'rgba(255,255,255,0.8)',
    fontVariantNumeric: 'tabular-nums' as const,
  },
  dot: {
    width: 6,
    height: 6,
    borderRadius: '50%' as const,
    flexShrink: 0,
  } as React.CSSProperties,
  legend: {
    display: 'flex',
    flexWrap: 'wrap' as const,
    justifyContent: 'center',
    gap: '5px 14px',
    marginTop: 10,
  },
  legendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    fontSize: 8,
    color: 'rgba(255,255,255,0.38)',
  },
  dualGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 12,
    alignItems: 'start',
  },
  singleGrid: {
    display: 'flex',
    justifyContent: 'center',
  },
  wheelColumn: {
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    gap: 6,
  },
  scopeLabel: {
    fontSize: 9,
    fontWeight: 700 as const,
    color: 'rgba(100,180,255,0.85)',
    letterSpacing: '0.06em',
    textTransform: 'uppercase' as const,
  },
  summary: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 5,
    padding: '6px 0',
    minWidth: 0,
    flex: 1,
  },
  summaryTitle: {
    fontSize: 9,
    fontWeight: 700 as const,
    letterSpacing: '0.06em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255,255,255,0.35)',
    marginBottom: 2,
  },
  summaryRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '3px 8px',
    background: 'rgba(255,255,255,0.02)',
    borderRadius: 5,
    border: '1px solid rgba(255,255,255,0.04)',
  },
  summaryLabel: {
    fontSize: 9,
    color: 'rgba(255,255,255,0.5)',
    flex: 1,
    minWidth: 0,
    whiteSpace: 'nowrap' as const,
    overflow: 'hidden' as const,
    textOverflow: 'ellipsis' as const,
  },
  summaryVal: {
    fontSize: 11,
    fontWeight: 700 as const,
    fontVariantNumeric: 'tabular-nums' as const,
    flexShrink: 0,
  },
};
