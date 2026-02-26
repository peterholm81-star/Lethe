import { useEngagementFlow } from '../hooks/useEngagementFlow';
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

  section: {
    marginBottom: '20px',
  } as React.CSSProperties,

  sectionTitle: {
    margin: '0 0 12px 0',
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))',
    gap: '10px',
  } as React.CSSProperties,

  gridWide: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: '10px',
  } as React.CSSProperties,

  tile: {
    padding: '16px 12px',
    background: 'rgba(255, 255, 255, 0.025)',
    borderRadius: '10px',
    textAlign: 'center' as const,
  } as React.CSSProperties,

  tileHighlight: {
    padding: '16px 12px',
    background: 'rgba(100, 200, 100, 0.08)',
    border: '1px solid rgba(100, 200, 100, 0.15)',
    borderRadius: '10px',
    textAlign: 'center' as const,
  } as React.CSSProperties,

  tileWarning: {
    padding: '16px 12px',
    background: 'rgba(255, 180, 100, 0.08)',
    border: '1px solid rgba(255, 180, 100, 0.15)',
    borderRadius: '10px',
    textAlign: 'center' as const,
  } as React.CSSProperties,

  value: {
    fontSize: '28px',
    fontWeight: 600,
    lineHeight: 1,
    color: 'rgba(255, 255, 255, 0.92)',
    fontVariantNumeric: 'tabular-nums',
  } as React.CSSProperties,

  valueSmall: {
    fontSize: '22px',
    fontWeight: 600,
    lineHeight: 1,
    color: 'rgba(255, 255, 255, 0.92)',
    fontVariantNumeric: 'tabular-nums',
  } as React.CSSProperties,

  valueSkeleton: {
    fontSize: '28px',
    fontWeight: 600,
    lineHeight: 1,
    color: 'rgba(255, 255, 255, 0.15)',
  } as React.CSSProperties,

  valuePercent: {
    fontSize: '22px',
    fontWeight: 600,
    lineHeight: 1,
    color: 'rgba(100, 200, 100, 0.9)',
    fontVariantNumeric: 'tabular-nums',
  } as React.CSSProperties,

  label: {
    marginTop: '8px',
    fontSize: '10px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.4)',
    letterSpacing: '0.01em',
  } as React.CSSProperties,

  divider: {
    height: '1px',
    background: 'rgba(255, 255, 255, 0.06)',
    margin: '16px 0',
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
  format?: 'number' | 'decimal' | 'percent';
  variant?: 'default' | 'highlight' | 'warning';
  size?: 'normal' | 'small';
}

function StatTile({ value, label, loading, format = 'number', variant = 'default', size = 'normal' }: StatTileProps) {
  const tileStyle = variant === 'highlight' ? styles.tileHighlight 
    : variant === 'warning' ? styles.tileWarning 
    : styles.tile;

  const valueStyle = loading ? styles.valueSkeleton 
    : variant === 'highlight' ? styles.valuePercent
    : size === 'small' ? styles.valueSmall
    : styles.value;

  let displayValue: string;
  if (loading) {
    displayValue = '—';
  } else if (format === 'percent') {
    displayValue = `${((value ?? 0) * 100).toFixed(0)}%`;
  } else if (format === 'decimal') {
    displayValue = (value ?? 0).toFixed(1);
  } else {
    displayValue = (value ?? 0).toLocaleString();
  }

  return (
    <div style={tileStyle}>
      <div style={valueStyle}>{displayValue}</div>
      <div style={styles.label}>{label}</div>
    </div>
  );
}

export function EngagementFlow() {
  const { filters, window, lensLabel, windowLabel } = useInsightsFilters();
  
  const { data, loading, error, refetch } = useEngagementFlow(filters, window);

  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <h2 style={styles.title}>Engagement Flow</h2>
        <span style={styles.lens}>{lensLabel} · {windowLabel}</span>
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
        <>
          {/* Funnel Overview */}
          <div style={styles.section}>
            <h3 style={styles.sectionTitle}>Funnel</h3>
            <div style={styles.grid}>
              <StatTile value={data?.sessions ?? null} label="Sessions" loading={loading} />
              <StatTile value={data?.pages_loaded ?? null} label="Pages" loading={loading} />
              <StatTile value={data?.post_attempts ?? null} label="Attempts" loading={loading} />
              <StatTile value={data?.post_success ?? null} label="Posts" loading={loading} />
            </div>
          </div>

          <div style={styles.divider} />

          {/* Per-Session Rates */}
          <div style={styles.section}>
            <h3 style={styles.sectionTitle}>Per Session</h3>
            <div style={styles.gridWide}>
              <StatTile 
                value={data?.pages_per_session ?? null} 
                label="Pages/session" 
                loading={loading} 
                format="decimal"
                size="small"
              />
              <StatTile 
                value={data?.posts_per_session ?? null} 
                label="Posts/session" 
                loading={loading} 
                format="decimal"
                size="small"
              />
              <StatTile 
                value={data?.ads_shown ?? null} 
                label="Ads shown" 
                loading={loading}
                size="small"
              />
            </div>
          </div>

          <div style={styles.divider} />

          {/* Ad Impact */}
          <div style={styles.section}>
            <h3 style={styles.sectionTitle}>After Ad</h3>
            <div style={styles.gridWide}>
              <StatTile 
                value={data?.ad_continue_sessions ?? null} 
                label="Continued" 
                loading={loading}
                variant="highlight"
                size="small"
              />
              <StatTile 
                value={data?.ad_drop_sessions ?? null} 
                label="Dropped" 
                loading={loading}
                variant="warning"
                size="small"
              />
              <StatTile 
                value={data?.ad_continue_rate ?? null} 
                label="Continue rate" 
                loading={loading}
                format="percent"
                variant="highlight"
                size="small"
              />
            </div>
          </div>
        </>
      )}
    </div>
  );
}
