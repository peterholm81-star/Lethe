import { useInsightsFilters } from '../contexts/InsightsContext';
import { useFrictionMetrics } from '../hooks/useFrictionMetrics';

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

  rows: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '14px',
  } as React.CSSProperties,

  row: {
    display: 'grid',
    gridTemplateColumns: '100px 52px 1fr auto',
    alignItems: 'center',
    gap: '12px',
  } as React.CSSProperties,

  label: {
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  percent: {
    fontSize: '22px',
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(255, 255, 255, 0.9)',
    textAlign: 'right' as const,
  } as React.CSSProperties,

  percentSkeleton: {
    fontSize: '22px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.15)',
    textAlign: 'right' as const,
  } as React.CSSProperties,

  trackContainer: {
    height: '8px',
    background: 'rgba(255, 255, 255, 0.08)',
    borderRadius: '4px',
    overflow: 'hidden',
  } as React.CSSProperties,

  trackFill: {
    height: '100%',
    background: 'rgba(255, 255, 255, 0.22)',
    borderRadius: '4px',
  } as React.CSSProperties,

  tally: {
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.35)',
    textAlign: 'right' as const,
    minWidth: '80px',
  } as React.CSSProperties,

  frictionScore: {
    marginTop: '20px',
    paddingTop: '16px',
    borderTop: '1px solid rgba(255, 255, 255, 0.06)',
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  scoreValue: {
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(255, 255, 255, 0.6)',
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

interface FrictionRowProps {
  label: string;
  percent: number;
  tally: string;
  loading?: boolean;
}

function FrictionRow({ label, percent, tally, loading }: FrictionRowProps) {
  return (
    <div style={styles.row}>
      <div style={styles.label}>{label}</div>
      <div style={loading ? styles.percentSkeleton : styles.percent}>
        {loading ? '—' : `${percent}%`}
      </div>
      <div style={styles.trackContainer}>
        <div style={{ ...styles.trackFill, width: loading ? '0%' : `${percent}%` }} />
      </div>
      <div style={styles.tally}>{loading ? '—' : tally}</div>
    </div>
  );
}

export function FrictionCard() {
  const { filters, window, lensLabel, windowLabel } = useInsightsFilters();
  const { data, loading, error, refetch } = useFrictionMetrics(filters, window);

  // Calculate display values
  const attemptsTotal = data?.attemptsTotal ?? 0;
  const successTotal = data?.successTotal ?? 0;
  const rejectedTotal = data?.rejectedTotal ?? 0;
  const successRate = data?.successRate ?? 0;
  const rejectRate = data?.rejectRate ?? 0;
  const frictionScore = data?.frictionScore ?? 0;

  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <h2 style={styles.title}>Friction</h2>
        <span style={styles.lens}>{lensLabel} · {windowLabel}</span>
      </div>
      <p style={styles.subtitle}>Where people get stuck</p>

      {error && !loading ? (
        <div style={styles.errorContainer}>
          <p style={styles.errorText}>Failed to load metrics</p>
          <p style={styles.errorHint}>Check connection and try again</p>
          <button style={styles.retryButton} onClick={refetch}>
            Retry
          </button>
        </div>
      ) : (
        <>
          <div style={styles.rows}>
            <FrictionRow
              label="Post attempts"
              percent={100}
              tally={`≈ ${attemptsTotal.toLocaleString()} attempts`}
              loading={loading}
            />
            <FrictionRow
              label="Post success"
              percent={successRate}
              tally={`≈ ${successTotal.toLocaleString()} posts`}
              loading={loading}
            />
            <FrictionRow
              label="Post rejected"
              percent={rejectRate}
              tally={`≈ ${rejectedTotal.toLocaleString()} rejects`}
              loading={loading}
            />
          </div>

          <div style={styles.frictionScore}>
            Friction score:{' '}
            <span style={styles.scoreValue}>
              {loading ? '—' : frictionScore.toFixed(2)}
            </span>
          </div>
        </>
      )}
    </div>
  );
}
