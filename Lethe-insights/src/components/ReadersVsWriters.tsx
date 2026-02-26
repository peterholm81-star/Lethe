import { useReadersWritersMetrics } from '../hooks/useReadersWritersMetrics';
import { useInsightsFilters } from '../contexts/InsightsContext';

const styles = {
  card: {
    padding: '24px',
    background: 'rgba(255, 255, 255, 0.05)',
    border: '1px solid rgba(255, 255, 255, 0.09)',
    borderRadius: '16px',
  } as React.CSSProperties,

  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    marginBottom: '6px',
  } as React.CSSProperties,

  title: {
    margin: 0,
    fontSize: '12px',
    fontWeight: 550,
    letterSpacing: '0.14em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.85)',
  } as React.CSSProperties,

  lens: {
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,

  subtitle: {
    margin: '0 0 24px 0',
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: '16px',
  } as React.CSSProperties,

  statTile: {
    textAlign: 'center' as const,
    padding: '16px 8px',
    background: 'rgba(255, 255, 255, 0.025)',
    borderRadius: '12px',
  } as React.CSSProperties,

  statValue: {
    fontSize: '28px',
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(255, 255, 255, 0.9)',
    lineHeight: 1,
  } as React.CSSProperties,

  statValueSkeleton: {
    fontSize: '28px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.15)',
    lineHeight: 1,
  } as React.CSSProperties,

  statLabel: {
    marginTop: '8px',
    fontSize: '11px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,
};

interface StatTileProps {
  value: string;
  label: string;
  loading?: boolean;
}

function StatTile({ value, label, loading }: StatTileProps) {
  return (
    <div style={styles.statTile}>
      <div style={loading ? styles.statValueSkeleton : styles.statValue}>
        {loading ? '—' : value}
      </div>
      <div style={styles.statLabel}>{label}</div>
    </div>
  );
}

export function ReadersVsWriters() {
  const { filters, window, lensLabel, windowLabel } = useInsightsFilters();
  
  const { data, loading } = useReadersWritersMetrics(filters, window);

  // Calculate writer share percentage
  let writerSharePct = 0;
  if (data) {
    if (data.writerShare > 0) {
      writerSharePct = data.writerShare * 100;
    } else if (data.readers > 0) {
      writerSharePct = (data.writers / data.readers) * 100;
    }
  }

  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <h2 style={styles.title}>Readers vs Writers</h2>
        <span style={styles.lens}>{lensLabel} · {windowLabel}</span>
      </div>
      <p style={styles.subtitle}>Who observes — and who chooses to speak</p>

      <div style={styles.statsGrid}>
        <StatTile
          value={(data?.readers ?? 0).toLocaleString()}
          label="Readers"
          loading={loading}
        />
        <StatTile
          value={(data?.writers ?? 0).toLocaleString()}
          label="Writers"
          loading={loading}
        />
        <StatTile
          value={`${writerSharePct.toFixed(1)}%`}
          label="Writer Share"
          loading={loading}
        />
      </div>
    </div>
  );
}
