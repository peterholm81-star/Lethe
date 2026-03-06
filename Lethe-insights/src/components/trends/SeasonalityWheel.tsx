import { useState, useMemo } from 'react';
import type { YearWheelMonth } from '../../hooks/useYearWheelV1';

// =============================================================================
// TYPES
// =============================================================================

export interface SeasonalityWheelProps {
  data: YearWheelMonth[];
  loading: boolean;
  error: string | null;
}

// =============================================================================
// CONSTANTS
// =============================================================================

const SIZE = 300;
const CX = SIZE / 2;
const CY = SIZE / 2;

const R_OUTER_MAX = 140;
const R_OUTER_MIN = 105;
const R_MID_MAX = 100;
const R_MID_MIN = 75;
const R_INNER_MAX = 70;
const R_INNER_MIN = 38;

const MONTH_LABELS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

const SEG_GAP_DEG = 1.5;

// =============================================================================
// HELPERS
// =============================================================================

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

function arcPath(
  cx: number, cy: number,
  rOuter: number, rInner: number,
  startDeg: number, endDeg: number,
): string {
  const s1 = toRad(startDeg - 90);
  const e1 = toRad(endDeg - 90);
  const largeArc = (endDeg - startDeg) > 180 ? 1 : 0;

  const ox1 = cx + rOuter * Math.cos(s1);
  const oy1 = cy + rOuter * Math.sin(s1);
  const ox2 = cx + rOuter * Math.cos(e1);
  const oy2 = cy + rOuter * Math.sin(e1);
  const ix1 = cx + rInner * Math.cos(e1);
  const iy1 = cy + rInner * Math.sin(e1);
  const ix2 = cx + rInner * Math.cos(s1);
  const iy2 = cy + rInner * Math.sin(s1);

  return [
    `M${ox1.toFixed(2)},${oy1.toFixed(2)}`,
    `A${rOuter},${rOuter} 0 ${largeArc} 1 ${ox2.toFixed(2)},${oy2.toFixed(2)}`,
    `L${ix1.toFixed(2)},${iy1.toFixed(2)}`,
    `A${rInner},${rInner} 0 ${largeArc} 0 ${ix2.toFixed(2)},${iy2.toFixed(2)}`,
    'Z',
  ].join(' ');
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * Math.max(0, Math.min(1, t));
}

function sessionsColor(t: number): string {
  const alpha = lerp(0.12, 0.85, t);
  return `rgba(80,160,255,${alpha.toFixed(2)})`;
}

function postsColor(t: number): string {
  const alpha = lerp(0.12, 0.85, t);
  return `rgba(160,100,220,${alpha.toFixed(2)})`;
}

function moodColor(balance: number | null): string {
  if (balance == null) return 'rgba(255,255,255,0.06)';
  if (balance > 0.15) return `rgba(80,200,130,${lerp(0.3, 0.85, balance).toFixed(2)})`;
  if (balance < -0.15) return `rgba(220,90,90,${lerp(0.3, 0.85, Math.abs(balance)).toFixed(2)})`;
  return 'rgba(255,255,255,0.15)';
}

function fmtBalance(b: number | null): string {
  if (b == null) return '—';
  return (b >= 0 ? '+' : '') + b.toFixed(2);
}

// Sort RPC data into calendar order (Jan=0..Dec=11) and pad missing months
function toCalendar(data: YearWheelMonth[]): YearWheelMonth[] {
  const byMonth = new Map<number, YearWheelMonth>();
  for (const d of data) {
    const m = new Date(d.monthStart + 'T00:00:00Z').getUTCMonth();
    byMonth.set(m, d);
  }
  return Array.from({ length: 12 }, (_, i) =>
    byMonth.get(i) ?? {
      monthStart: '',
      sessions: 0,
      posts: 0,
      postsPerSession: null,
      moodPos: 0,
      moodNeg: 0,
      moodBalance: null,
    },
  );
}

// =============================================================================
// COMPONENT
// =============================================================================

export function SeasonalityWheel({ data, loading, error }: SeasonalityWheelProps) {
  const [hovered, setHovered] = useState<number | null>(null);

  const months = useMemo(() => toCalendar(data), [data]);

  const maxSessions = useMemo(() => Math.max(...months.map(m => m.sessions), 1), [months]);
  const maxPPS = useMemo(() => Math.max(...months.map(m => m.postsPerSession ?? 0), 0.01), [months]);
  const allZero = useMemo(() => months.every(m => m.sessions === 0), [months]);

  if (loading) return <div style={st.empty}>Loading seasonality...</div>;
  if (error) return <div style={{ ...st.empty, color: 'rgba(220,120,120,0.8)' }}>{error}</div>;
  if (allZero) return <div style={st.empty}>No seasonality data yet</div>;

  const segDeg = 360 / 12;

  return (
    <div style={st.wrapper}>
      <svg
        width={SIZE}
        height={SIZE}
        viewBox={`0 0 ${SIZE} ${SIZE}`}
        style={{ display: 'block', margin: '0 auto' }}
      >
        {months.map((m, i) => {
          const startDeg = i * segDeg + SEG_GAP_DEG / 2;
          const endDeg = (i + 1) * segDeg - SEG_GAP_DEG / 2;

          const sessT = m.sessions / maxSessions;
          const ppsT = (m.postsPerSession ?? 0) / maxPPS;

          const isHovered = hovered === i;
          const dimmed = hovered != null && !isHovered;
          const baseOpacity = dimmed ? 0.3 : 1;

          return (
            <g
              key={i}
              onMouseEnter={() => setHovered(i)}
              onMouseLeave={() => setHovered(null)}
              style={{ cursor: 'default', opacity: baseOpacity, transition: 'opacity 0.15s ease' }}
            >
              {/* Outer: sessions */}
              <path
                d={arcPath(CX, CY, R_OUTER_MAX, R_OUTER_MIN, startDeg, endDeg)}
                fill={sessionsColor(sessT)}
                stroke="rgba(255,255,255,0.04)"
                strokeWidth={0.5}
              />
              {/* Middle: posts per session */}
              <path
                d={arcPath(CX, CY, R_MID_MAX, R_MID_MIN, startDeg, endDeg)}
                fill={postsColor(ppsT)}
                stroke="rgba(255,255,255,0.04)"
                strokeWidth={0.5}
              />
              {/* Inner: mood */}
              <path
                d={arcPath(CX, CY, R_INNER_MAX, R_INNER_MIN, startDeg, endDeg)}
                fill={moodColor(m.moodBalance)}
                stroke="rgba(255,255,255,0.04)"
                strokeWidth={0.5}
              />
            </g>
          );
        })}

        {/* Month labels around outside */}
        {MONTH_LABELS.map((label, i) => {
          const midDeg = (i + 0.5) * segDeg;
          const rad = toRad(midDeg - 90);
          const lx = CX + (R_OUTER_MAX + 8) * Math.cos(rad);
          const ly = CY + (R_OUTER_MAX + 8) * Math.sin(rad);
          return (
            <text
              key={label}
              x={lx}
              y={ly}
              textAnchor="middle"
              dominantBaseline="middle"
              fontSize={8}
              fontWeight={hovered === i ? 700 : 500}
              fill={hovered === i ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.35)'}
              style={{ transition: 'fill 0.15s ease', letterSpacing: '0.04em' }}
            >
              {label}
            </text>
          );
        })}
      </svg>

      {/* Tooltip */}
      {hovered != null && (
        <div style={st.tooltip}>
          <div style={st.tooltipTitle}>{MONTH_LABELS[hovered]}</div>
          <div style={st.tooltipRow}>
            <span style={st.tooltipDot('#50a0ff')} />
            <span>Sessions</span>
            <span style={st.tooltipVal}>{months[hovered].sessions.toLocaleString()}</span>
          </div>
          <div style={st.tooltipRow}>
            <span style={st.tooltipDot('#a064dc')} />
            <span>Posts / session</span>
            <span style={st.tooltipVal}>{months[hovered].postsPerSession?.toFixed(2) ?? '—'}</span>
          </div>
          <div style={st.tooltipRow}>
            <span style={st.tooltipDot(moodColor(months[hovered].moodBalance))} />
            <span>Mood balance</span>
            <span style={st.tooltipVal}>{fmtBalance(months[hovered].moodBalance)}</span>
          </div>
        </div>
      )}

      {/* Legend */}
      <div style={st.legend}>
        <LegendItem color="#50a0ff" label="Sessions volume" />
        <LegendItem color="#a064dc" label="Confessions intensity" />
        <LegendItem color="#50c882" label="Mood +" />
        <LegendItem color="#dc5a5a" label="Mood −" />
      </div>
    </div>
  );
}

function LegendItem({ color, label }: { color: string; label: string }) {
  return (
    <div style={st.legendItem}>
      <div style={{ width: 8, height: 8, borderRadius: 2, background: color, flexShrink: 0 }} />
      <span>{label}</span>
    </div>
  );
}

// =============================================================================
// STYLES
// =============================================================================

const st = {
  wrapper: {
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    gap: 12,
    position: 'relative' as const,
  },
  empty: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.3)',
    padding: '24px 0',
    textAlign: 'center' as const,
  },
  tooltip: {
    position: 'absolute' as const,
    top: 4,
    right: 4,
    background: 'rgba(10,10,16,0.92)',
    border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 8,
    padding: '10px 14px',
    minWidth: 160,
    backdropFilter: 'blur(10px)',
    zIndex: 10,
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
    fontSize: 10,
    color: 'rgba(255,255,255,0.55)',
    padding: '2px 0',
  },
  tooltipVal: {
    marginLeft: 'auto' as const,
    fontWeight: 600 as const,
    color: 'rgba(255,255,255,0.8)',
    fontVariantNumeric: 'tabular-nums' as const,
  },
  tooltipDot: (color: string): React.CSSProperties => ({
    width: 6,
    height: 6,
    borderRadius: '50%',
    background: color,
    flexShrink: 0,
  }),
  legend: {
    display: 'flex',
    flexWrap: 'wrap' as const,
    justifyContent: 'center',
    gap: '6px 14px',
  },
  legendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 5,
    fontSize: 9,
    color: 'rgba(255,255,255,0.4)',
  },
};
