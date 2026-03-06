/**
 * EmotionalFingerprintWheel — Radar/spider chart showing emotion seasonality.
 *
 * 12 month-axes around a circle, with one polygon per emotion.
 * Each emotion is self-normalized (0..1) so the shape shows seasonal
 * rhythm, not absolute volume. Compare mode overlays A (solid) and B (dashed).
 */

import { useMemo, useState, useRef, useCallback } from 'react';
import type { EmotionFingerprintRow } from '../../hooks/useEmotionFingerprintV1';

// =============================================================================
// CONSTANTS
// =============================================================================

const SIZE = 290;
const CX = SIZE / 2;
const CY = SIZE / 2;
const R_MAX = 110;
const R_MIN = 16;
const GRID_LEVELS = [0.25, 0.5, 0.75, 1.0];
const LABEL_R = R_MAX + 14;
const MONTHS = 12;
const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const PREFERRED_EMOTIONS = ['love', 'desire', 'loneliness', 'hope', 'anxiety', 'anger'];

const EMOTION_COLORS: Record<string, string> = {
  love:       'rgba(240,90,140,0.8)',
  desire:     'rgba(200,130,220,0.8)',
  loneliness: 'rgba(100,140,220,0.8)',
  hope:       'rgba(100,210,170,0.8)',
  anxiety:    'rgba(230,180,60,0.8)',
  anger:      'rgba(220,80,70,0.8)',
  joy:        'rgba(255,210,80,0.8)',
  calm:       'rgba(120,200,200,0.8)',
  gratitude:  'rgba(160,210,120,0.8)',
  confidence: 'rgba(180,150,240,0.8)',
  sadness:    'rgba(100,120,200,0.8)',
  shame:      'rgba(180,100,120,0.8)',
};

const FALLBACK_COLORS = [
  'rgba(240,90,140,0.8)', 'rgba(200,130,220,0.8)', 'rgba(100,140,220,0.8)',
  'rgba(100,210,170,0.8)', 'rgba(230,180,60,0.8)', 'rgba(220,80,70,0.8)',
];

const HOVER_GRACE_MS = 80;

// =============================================================================
// MATH
// =============================================================================

function toRad(deg: number): number { return (deg * Math.PI) / 180; }

function axisXY(index: number, r: number): [number, number] {
  const deg = (index / MONTHS) * 360 - 90;
  const rad = toRad(deg);
  return [CX + r * Math.cos(rad), CY + r * Math.sin(rad)];
}

function polyPoints(values: number[]): string {
  return values.map((v, i) => {
    const r = R_MIN + v * (R_MAX - R_MIN);
    const [x, y] = axisXY(i, r);
    return `${x.toFixed(2)},${y.toFixed(2)}`;
  }).join(' ');
}

// =============================================================================
// DATA PREP
// =============================================================================

interface EmotionSeries {
  emotion: string;
  color: string;
  values: number[];       // 12 normalized values (0..1)
  rawValues: number[];    // 12 raw counts
  peakMonth: number;      // index of max
  total: number;
}

function buildSeries(
  rows: EmotionFingerprintRow[],
  emotions: string[],
): EmotionSeries[] {
  // Group: emotion -> month(0..11) -> count
  const map = new Map<string, number[]>();
  for (const r of rows) {
    if (!r.monthStart || !r.emotion) continue;
    const emo = r.emotion.toLowerCase();
    if (!emotions.includes(emo)) continue;
    if (!map.has(emo)) map.set(emo, new Array(12).fill(0));
    const m = new Date(r.monthStart + 'T00:00:00Z').getUTCMonth();
    map.get(emo)![m] += r.count;
  }

  return emotions
    .filter(e => map.has(e))
    .map((emo, idx) => {
      const raw = map.get(emo)!;
      const maxVal = Math.max(...raw, 1);
      const values = raw.map(v => v / maxVal);
      const peakMonth = raw.indexOf(Math.max(...raw));
      const color = EMOTION_COLORS[emo] ?? FALLBACK_COLORS[idx % FALLBACK_COLORS.length];
      return { emotion: emo, color, values, rawValues: raw, peakMonth, total: raw.reduce((a, b) => a + b, 0) };
    });
}

function pickEmotions(rows: EmotionFingerprintRow[]): string[] {
  const totals = new Map<string, number>();
  for (const r of rows) {
    const e = r.emotion.toLowerCase();
    totals.set(e, (totals.get(e) ?? 0) + r.count);
  }
  // Use preferred list filtered to those present, then fill up to 6 from top by volume
  const present = new Set(totals.keys());
  const picked: string[] = [];
  for (const e of PREFERRED_EMOTIONS) {
    if (present.has(e) && picked.length < 6) picked.push(e);
  }
  if (picked.length < 6) {
    const sorted = [...totals.entries()].sort((a, b) => b[1] - a[1]);
    for (const [e] of sorted) {
      if (!picked.includes(e) && picked.length < 6) picked.push(e);
    }
  }
  return picked;
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// =============================================================================
// PROPS
// =============================================================================

export interface EmotionalFingerprintWheelProps {
  rowsA: EmotionFingerprintRow[];
  rowsB?: EmotionFingerprintRow[] | null;
  compare?: boolean;
  loading?: boolean;
  error?: string | null;
}

// =============================================================================
// COMPONENT
// =============================================================================

export function EmotionalFingerprintWheel({
  rowsA, rowsB, compare, loading, error,
}: EmotionalFingerprintWheelProps) {
  const [hoveredEmo, setHoveredEmo] = useState<string | null>(null);
  const [hoveredMonth, setHoveredMonth] = useState<number | null>(null);
  const leaveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const emotions = useMemo(() => pickEmotions(rowsA), [rowsA]);
  const seriesA = useMemo(() => buildSeries(rowsA, emotions), [rowsA, emotions]);
  const seriesB = useMemo(() => (compare && rowsB) ? buildSeries(rowsB, emotions) : null, [rowsB, emotions, compare]);

  const allEmpty = seriesA.length === 0;

  const enterMonth = useCallback((i: number) => {
    if (leaveTimer.current) { clearTimeout(leaveTimer.current); leaveTimer.current = null; }
    setHoveredMonth(i);
  }, []);

  const leaveMonth = useCallback(() => {
    if (leaveTimer.current) clearTimeout(leaveTimer.current);
    leaveTimer.current = setTimeout(() => setHoveredMonth(null), HOVER_GRACE_MS);
  }, []);

  const leaveSvg = useCallback(() => {
    if (leaveTimer.current) clearTimeout(leaveTimer.current);
    setHoveredMonth(null);
  }, []);

  if (loading) return <div style={st.empty}>Loading fingerprint...</div>;
  if (error) return <div style={{ ...st.empty, color: 'rgba(220,120,120,0.8)' }}>{error}</div>;
  if (allEmpty) return <div style={st.empty}>No emotion fingerprint data yet</div>;

  return (
    <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start', flexWrap: 'wrap' as const }}>
      {/* SVG radar */}
      <div style={st.chartContainer}>
        <svg
          width={SIZE} height={SIZE}
          viewBox={`0 0 ${SIZE} ${SIZE}`}
          style={{ display: 'block' }}
          onPointerLeave={leaveSvg}
        >
          {/* Grid rings */}
          {GRID_LEVELS.map(frac => {
            const r = R_MIN + frac * (R_MAX - R_MIN);
            return (
              <circle
                key={frac} cx={CX} cy={CY} r={r}
                fill="none"
                stroke={frac === 1 ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.04)'}
                strokeWidth={0.5}
                strokeDasharray={frac < 1 ? '2 4' : 'none'}
                style={{ pointerEvents: 'none' }}
              />
            );
          })}

          {/* Axis lines */}
          {MONTH_LABELS.map((_, i) => {
            const [x, y] = axisXY(i, R_MAX);
            return (
              <line
                key={i}
                x1={CX} y1={CY} x2={x} y2={y}
                stroke="rgba(255,255,255,0.04)" strokeWidth={0.5}
                style={{ pointerEvents: 'none' }}
              />
            );
          })}

          {/* Invisible month hit areas (pie slices for stable hover) */}
          {MONTH_LABELS.map((_, i) => {
            const startDeg = (i / MONTHS) * 360 - (360 / MONTHS / 2);
            const endDeg = startDeg + 360 / MONTHS;
            const s = toRad(startDeg - 90);
            const e = toRad(endDeg - 90);
            const hr = R_MAX + 20;
            const d = [
              `M${CX},${CY}`,
              `L${(CX + hr * Math.cos(s)).toFixed(2)},${(CY + hr * Math.sin(s)).toFixed(2)}`,
              `A${hr},${hr} 0 0 1 ${(CX + hr * Math.cos(e)).toFixed(2)},${(CY + hr * Math.sin(e)).toFixed(2)}`,
              'Z',
            ].join(' ');
            return (
              <path
                key={`hit-${i}`}
                d={d}
                fill="transparent" stroke="none"
                style={{ cursor: 'default' }}
                onPointerEnter={() => enterMonth(i)}
                onPointerLeave={leaveMonth}
              />
            );
          })}

          {/* A polygons (solid) */}
          {seriesA.map(s => {
            const dimmed = hoveredEmo != null && hoveredEmo !== s.emotion;
            return (
              <polygon
                key={`a-${s.emotion}`}
                points={polyPoints(s.values)}
                fill={s.color.replace(/[\d.]+\)$/, '0.08)')}
                stroke={s.color}
                strokeWidth={hoveredEmo === s.emotion ? 2 : 1.2}
                strokeLinejoin="round"
                style={{ pointerEvents: 'none', opacity: dimmed ? 0.2 : 1, transition: 'opacity 0.15s ease' }}
              />
            );
          })}

          {/* B polygons (dashed) */}
          {seriesB?.map(s => {
            const dimmed = hoveredEmo != null && hoveredEmo !== s.emotion;
            return (
              <polygon
                key={`b-${s.emotion}`}
                points={polyPoints(s.values)}
                fill="none"
                stroke={s.color}
                strokeWidth={hoveredEmo === s.emotion ? 2 : 1}
                strokeDasharray="4 3"
                strokeLinejoin="round"
                style={{ pointerEvents: 'none', opacity: dimmed ? 0.2 : 0.7, transition: 'opacity 0.15s ease' }}
              />
            );
          })}

          {/* Peak dots per emotion (A only, to avoid clutter) */}
          {seriesA.map(s => {
            const r = R_MIN + s.values[s.peakMonth] * (R_MAX - R_MIN);
            const [px, py] = axisXY(s.peakMonth, r);
            return (
              <circle
                key={`peak-${s.emotion}`}
                cx={px} cy={py} r={2.5}
                fill={s.color} stroke="rgba(0,0,0,0.5)" strokeWidth={0.5}
                style={{ pointerEvents: 'none' }}
              />
            );
          })}

          {/* Month labels */}
          {MONTH_LABELS.map((label, i) => {
            const [lx, ly] = axisXY(i, LABEL_R);
            const active = hoveredMonth === i;
            return (
              <text
                key={label}
                x={lx} y={ly}
                textAnchor="middle" dominantBaseline="middle"
                fontSize={7.5} fontWeight={active ? 700 : 500}
                fill={active ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.38)'}
                style={{ pointerEvents: 'none', transition: 'fill 0.12s ease', letterSpacing: '0.03em' }}
              >
                {label}
              </text>
            );
          })}

          {/* Active month crosshair */}
          {hoveredMonth != null && (
            <line
              x1={CX} y1={CY}
              x2={axisXY(hoveredMonth, R_MAX + 4)[0]}
              y2={axisXY(hoveredMonth, R_MAX + 4)[1]}
              stroke="rgba(255,255,255,0.15)" strokeWidth={1}
              style={{ pointerEvents: 'none' }}
            />
          )}
        </svg>

        {/* Hover tooltip */}
        {hoveredMonth != null && (
          <div style={st.tooltip}>
            <div style={st.tooltipTitle}>{MONTH_LABELS[hoveredMonth]}</div>
            {seriesA.map(s => (
              <div key={s.emotion} style={st.tooltipRow}>
                <span style={{ ...st.dot, background: s.color }} />
                <span>{capitalize(s.emotion)}</span>
                <span style={st.tooltipVal}>{s.rawValues[hoveredMonth].toLocaleString()}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Legend + summary sidebar */}
      <div style={st.sidebar}>
        <div style={st.sidebarTitle}>Emotions</div>
        {compare && seriesB && (
          <div style={st.compareLegend}>
            <span style={st.compareLine} /> A (solid)
            <span style={st.compareDash} /> B (dashed)
          </div>
        )}
        {seriesA.map(s => (
          <div
            key={s.emotion}
            style={{
              ...st.legendRow,
              opacity: hoveredEmo != null && hoveredEmo !== s.emotion ? 0.35 : 1,
              background: hoveredEmo === s.emotion ? 'rgba(255,255,255,0.04)' : 'transparent',
            }}
            onPointerEnter={() => setHoveredEmo(s.emotion)}
            onPointerLeave={() => setHoveredEmo(null)}
          >
            <span style={{ ...st.dot, background: s.color }} />
            <span style={st.legendLabel}>{capitalize(s.emotion)}</span>
            <span style={st.legendPeak}>
              peak {MONTH_LABELS[s.peakMonth]}
            </span>
          </div>
        ))}
      </div>
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
  chartContainer: {
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
    minWidth: 140,
    backdropFilter: 'blur(10px)',
    zIndex: 10,
    pointerEvents: 'none' as const,
  },
  tooltipTitle: {
    fontSize: 11,
    fontWeight: 700 as const,
    color: 'rgba(255,255,255,0.85)',
    marginBottom: 5,
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
    display: 'inline-block',
  } as React.CSSProperties,
  sidebar: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 3,
    minWidth: 0,
    flex: 1,
    padding: '4px 0',
  },
  sidebarTitle: {
    fontSize: 9,
    fontWeight: 700 as const,
    letterSpacing: '0.06em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255,255,255,0.35)',
    marginBottom: 4,
  },
  compareLegend: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 8,
    color: 'rgba(255,255,255,0.35)',
    marginBottom: 4,
  },
  compareLine: {
    display: 'inline-block',
    width: 14,
    height: 0,
    borderTop: '2px solid rgba(255,255,255,0.5)',
  } as React.CSSProperties,
  compareDash: {
    display: 'inline-block',
    width: 14,
    height: 0,
    borderTop: '2px dashed rgba(255,255,255,0.5)',
    marginLeft: 6,
  } as React.CSSProperties,
  legendRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '4px 8px',
    borderRadius: 5,
    cursor: 'default',
    transition: 'opacity 0.15s ease, background 0.15s ease',
  },
  legendLabel: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.65)',
    flex: 1,
  },
  legendPeak: {
    fontSize: 8,
    color: 'rgba(255,255,255,0.3)',
    fontVariantNumeric: 'tabular-nums' as const,
    whiteSpace: 'nowrap' as const,
  },
};
