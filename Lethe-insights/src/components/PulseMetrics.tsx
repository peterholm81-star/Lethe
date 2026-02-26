import { usePulseMetrics } from '../hooks/usePulseMetrics';
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
    marginBottom: '20px',
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

  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
    gap: '12px',
  } as React.CSSProperties,

  tile: {
    padding: '20px 16px',
    background: 'rgba(255, 255, 255, 0.025)',
    borderRadius: '12px',
    textAlign: 'center' as const,
  } as React.CSSProperties,

  value: {
    fontSize: '44px',
    fontWeight: 600,
    lineHeight: 1,
    color: 'rgba(255, 255, 255, 0.92)',
    fontVariantNumeric: 'tabular-nums',
  } as React.CSSProperties,

  valueSkeleton: {
    fontSize: '44px',
    fontWeight: 600,
    lineHeight: 1,
    color: 'rgba(255, 255, 255, 0.15)',
  } as React.CSSProperties,

  label: {
    marginTop: '10px',
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.4)',
    letterSpacing: '0.01em',
  } as React.CSSProperties,

  errorContainer: {
    textAlign: 'center' as const,
    padding: '24px 0',
  } as React.CSSProperties,

  errorText: {
    margin: '0 0 6px 0',
    fontSize: '14px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.7)',
  } as React.CSSProperties,

  errorHint: {
    margin: '0 0 20px 0',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,

  retryButton: {
    padding: '10px 24px',
    fontSize: '13px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.85)',
    background: 'rgba(255, 255, 255, 0.08)',
    border: '1px solid rgba(255, 255, 255, 0.12)',
    borderRadius: '8px',
    cursor: 'pointer',
  } as React.CSSProperties,
};

interface StatTileProps {
  value: number | null;
  label: string;
  loading?: boolean;
}

function StatTile({ value, label, loading }: StatTileProps) {
  return (
    <div style={styles.tile}>
      <div style={loading ? styles.valueSkeleton : styles.value}>
        {loading ? '—' : (value ?? 0).toLocaleString()}
      </div>
      <div style={styles.label}>{label}</div>
    </div>
  );
}

export function PulseMetrics() {
  const { filters, window, lensLabel, windowLabel } = useInsightsFilters();
  
  const { data, loading, error, refetch } = usePulseMetrics(filters, window);

  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <h2 style={styles.title}>Pulse</h2>
        <span style={styles.lens}>
          {lensLabel} · {windowLabel}
        </span>
      </div>

      {error && !loading ? (
        <div style={styles.errorContainer}>
          <p style={styles.errorText}>Failed to load metrics</p>
          <p style={styles.errorHint}>Check connection and try again</p>
          <button style={styles.retryButton} onClick={refetch}>
            Retry
          </button>
        </div>
      ) : (
        <div style={styles.grid}>
          <StatTile value={data?.sessions ?? null} label="Sessions" loading={loading} />
          <StatTile value={data?.readers ?? null} label="Readers" loading={loading} />
          <StatTile value={data?.posts ?? null} label="Posts" loading={loading} />
        </div>
      )}
    </div>
  );
}
