/**
 * TrendsMoversPanel — Rising / Falling / Emerging emotion tags.
 * Three side-by-side cards, each showing up to 8 tags with delta%.
 * When compare is on, each card shows A and B columns.
 */

import { useMemo } from 'react';
import type { MoverRow } from '../../hooks/useTrendsMoversV1';

// =============================================================================
// CONSTANTS
// =============================================================================

const MAX_ROWS = 8;

const STATUS_META: Record<string, { icon: string; label: string; color: string; emptyText: string }> = {
  rising:   { icon: '▲', label: 'Rising',   color: 'rgba(100,210,170,0.9)',  emptyText: 'No rising tags' },
  falling:  { icon: '▼', label: 'Falling',  color: 'rgba(220,120,120,0.9)',  emptyText: 'No falling tags' },
  emerging: { icon: '★', label: 'Emerging', color: 'rgba(200,170,80,0.9)',   emptyText: 'No emerging tags' },
};

// =============================================================================
// HELPERS
// =============================================================================

function capitalize(s: string): string {
  const l = s.toLowerCase();
  return l.charAt(0).toUpperCase() + l.slice(1);
}

function fmtDelta(d: number | null): string {
  if (d == null) return '—';
  const sign = d > 0 ? '+' : '';
  return `${sign}${d.toFixed(1)}%`;
}

function deltaColor(d: number | null): string {
  if (d == null) return 'rgba(255,255,255,0.3)';
  if (d > 0) return 'rgba(100,210,170,0.9)';
  if (d < 0) return 'rgba(220,120,120,0.9)';
  return 'rgba(255,255,255,0.4)';
}

function sliceByStatus(rows: MoverRow[], status: string): MoverRow[] {
  const filtered = rows.filter(r => r.status === status);
  if (status === 'falling') {
    filtered.sort((a, b) => (a.deltaPct ?? 0) - (b.deltaPct ?? 0));
  }
  return filtered.slice(0, MAX_ROWS);
}

// Mini sparkline placeholder (thin bar showing current vs baseline/4)
function MiniBar({ current, baseline }: { current: number; baseline: number }) {
  const base7 = baseline / 4;
  const max = Math.max(current, base7, 1);
  const curW = (current / max) * 100;
  const basW = (base7 / max) * 100;

  return (
    <div style={st.miniBarWrap}>
      <div style={{ ...st.miniBarBase, width: `${basW}%` }} />
      <div style={{ ...st.miniBarCur, width: `${curW}%` }} />
    </div>
  );
}

// =============================================================================
// PROPS
// =============================================================================

export interface TrendsMoversPanelProps {
  rowsA: MoverRow[];
  rowsB?: MoverRow[] | null;
  compare?: boolean;
  loading?: boolean;
  error?: string | null;
}

// =============================================================================
// COMPONENT
// =============================================================================

export function TrendsMoversPanel({
  rowsA, rowsB, compare, loading, error,
}: TrendsMoversPanelProps) {
  if (loading) return <div style={st.loading}>Loading emotion movers...</div>;
  if (error) return <div style={st.error}>{error}</div>;

  return (
    <div style={st.grid}>
      {(['rising', 'falling', 'emerging'] as const).map(status => (
        <MoverCard
          key={status}
          status={status}
          rowsA={rowsA}
          rowsB={compare ? rowsB : null}
          compare={!!compare}
        />
      ))}
    </div>
  );
}

// =============================================================================
// CARD
// =============================================================================

function MoverCard({ status, rowsA, rowsB, compare }: {
  status: string;
  rowsA: MoverRow[];
  rowsB?: MoverRow[] | null;
  compare: boolean;
}) {
  const meta = STATUS_META[status];
  const aSlice = useMemo(() => sliceByStatus(rowsA, status), [rowsA, status]);
  const bSlice = useMemo(() => rowsB ? sliceByStatus(rowsB, status) : [], [rowsB, status]);

  const allTags = useMemo(() => {
    if (!compare || !rowsB) return aSlice.map(r => r.tag);
    const set = new Set<string>();
    for (const r of aSlice) set.add(r.tag);
    for (const r of bSlice) set.add(r.tag);
    return [...set].slice(0, MAX_ROWS);
  }, [aSlice, bSlice, compare, rowsB]);

  const aMap = useMemo(() => new Map(aSlice.map(r => [r.tag, r])), [aSlice]);
  const bMap = useMemo(() => new Map(bSlice.map(r => [r.tag, r])), [bSlice]);

  const isEmpty = allTags.length === 0;

  return (
    <div style={st.card}>
      <div style={st.cardHeader}>
        <span style={{ ...st.cardIcon, color: meta.color }}>{meta.icon}</span>
        <span style={st.cardTitle}>{meta.label}</span>
        <span style={st.cardBadge}>7d vs 28d</span>
      </div>

      {isEmpty ? (
        <div style={st.empty}>{meta.emptyText}</div>
      ) : (
        <div style={st.list}>
          {/* Column headers when comparing */}
          {compare && rowsB && (
            <div style={st.compareHeader}>
              <span style={st.chLabel}>Tag</span>
              <span style={st.chVal}>A</span>
              <span style={st.chVal}>B</span>
            </div>
          )}

          {allTags.map(tag => {
            const a = aMap.get(tag);
            const b = bMap.get(tag);

            if (compare && rowsB) {
              return (
                <div key={tag} style={st.compareRow}>
                  <span style={st.tag}>{capitalize(tag)}</span>
                  <span style={{ ...st.delta, color: deltaColor(a?.deltaPct ?? null) }}>
                    {a ? fmtDelta(a.deltaPct) : '—'}
                  </span>
                  <span style={{ ...st.delta, color: deltaColor(b?.deltaPct ?? null) }}>
                    {b ? fmtDelta(b.deltaPct) : '—'}
                  </span>
                </div>
              );
            }

            return (
              <div key={tag} style={st.row}>
                <span style={st.tag}>{capitalize(tag)}</span>
                <MiniBar current={a?.current7d ?? 0} baseline={a?.baseline28d ?? 0} />
                <span style={{ ...st.delta, color: deltaColor(a?.deltaPct ?? null) }}>
                  {fmtDelta(a?.deltaPct ?? null)}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// STYLES
// =============================================================================

const st: Record<string, React.CSSProperties> = {
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: 12,
  },
  loading: {
    padding: 16,
    textAlign: 'center',
    color: 'rgba(255,255,255,0.4)',
    fontSize: 11,
  },
  error: {
    padding: '10px 14px',
    background: 'rgba(220,120,120,0.08)',
    border: '1px solid rgba(220,120,120,0.15)',
    borderRadius: 8,
    color: 'rgba(220,120,120,0.85)',
    fontSize: 11,
  },
  card: {
    padding: '14px 16px',
    background: 'linear-gradient(135deg, rgba(20,20,30,0.9) 0%, rgba(15,15,22,0.95) 100%)',
    border: '1px solid rgba(255,255,255,0.06)',
    borderRadius: 10,
    boxShadow: '0 4px 20px rgba(0,0,0,0.25)',
  },
  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    marginBottom: 10,
  },
  cardIcon: {
    fontSize: 10,
    width: 14,
    textAlign: 'center',
  },
  cardTitle: {
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: 'rgba(255,255,255,0.65)',
  },
  cardBadge: {
    fontSize: 8,
    fontWeight: 600,
    padding: '1px 5px',
    borderRadius: 3,
    background: 'rgba(255,255,255,0.05)',
    color: 'rgba(255,255,255,0.3)',
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
    marginLeft: 'auto',
  },
  empty: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.25)',
    padding: '8px 0',
  },
  list: {
    display: 'flex',
    flexDirection: 'column',
    gap: 0,
  },
  row: {
    display: 'grid',
    gridTemplateColumns: '1fr 48px 52px',
    gap: 6,
    alignItems: 'center',
    padding: '4px 0',
    borderBottom: '1px solid rgba(255,255,255,0.02)',
  },
  compareRow: {
    display: 'grid',
    gridTemplateColumns: '1fr 52px 52px',
    gap: 6,
    alignItems: 'center',
    padding: '4px 0',
    borderBottom: '1px solid rgba(255,255,255,0.02)',
  },
  compareHeader: {
    display: 'grid',
    gridTemplateColumns: '1fr 52px 52px',
    gap: 6,
    paddingBottom: 4,
    marginBottom: 2,
    borderBottom: '1px solid rgba(255,255,255,0.06)',
  },
  chLabel: {
    fontSize: 8,
    fontWeight: 600,
    color: 'rgba(255,255,255,0.25)',
    textTransform: 'uppercase',
    letterSpacing: '0.08em',
  },
  chVal: {
    fontSize: 8,
    fontWeight: 600,
    color: 'rgba(255,255,255,0.25)',
    textTransform: 'uppercase',
    letterSpacing: '0.08em',
    textAlign: 'right',
  },
  tag: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.7)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  delta: {
    fontSize: 10,
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    textAlign: 'right',
  },
  miniBarWrap: {
    position: 'relative',
    height: 5,
    borderRadius: 2,
    background: 'rgba(255,255,255,0.03)',
    overflow: 'hidden',
  },
  miniBarBase: {
    position: 'absolute',
    top: 0,
    left: 0,
    height: '100%',
    background: 'rgba(255,255,255,0.06)',
    borderRadius: 2,
  },
  miniBarCur: {
    position: 'absolute',
    top: 0,
    left: 0,
    height: '100%',
    background: 'rgba(100,180,255,0.4)',
    borderRadius: 2,
  },
};
