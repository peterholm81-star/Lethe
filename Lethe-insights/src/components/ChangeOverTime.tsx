import { useMemo } from 'react';
import { useChangeOverTimeMetrics, type DailyMetric } from '../hooks/useChangeOverTimeMetrics';
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
    margin: '0 0 20px 0',
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  errorText: {
    fontSize: '11px',
    color: '#ff6b6b',
    marginTop: '8px',
  } as React.CSSProperties,

  summaryGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(5, 1fr)',
    gap: '8px',
    marginBottom: '24px',
  } as React.CSSProperties,

  summaryTile: {
    textAlign: 'center' as const,
    padding: '12px 4px',
    background: 'rgba(255, 255, 255, 0.025)',
    borderRadius: '10px',
  } as React.CSSProperties,

  summaryValue: {
    fontSize: '18px',
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(255, 255, 255, 0.9)',
    lineHeight: 1,
  } as React.CSSProperties,

  summaryLabel: {
    marginTop: '6px',
    fontSize: '9px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.4)',
    lineHeight: 1.2,
  } as React.CSSProperties,

  chartContainer: {
    position: 'relative' as const,
    height: '160px',
    marginBottom: '12px',
  } as React.CSSProperties,

  chartSvg: {
    width: '100%',
    height: '100%',
  } as React.CSSProperties,

  chartLegend: {
    display: 'flex',
    justifyContent: 'center',
    gap: '16px',
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  legendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  } as React.CSSProperties,

  legendDot: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
  } as React.CSSProperties,

  loadingText: {
    textAlign: 'center' as const,
    padding: '40px 0',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  noData: {
    textAlign: 'center' as const,
    padding: '40px 0',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,
};

interface SummaryTileProps {
  value: string;
  label: string;
}

function SummaryTile({ value, label }: SummaryTileProps) {
  return (
    <div style={styles.summaryTile}>
      <div style={styles.summaryValue}>{value}</div>
      <div style={styles.summaryLabel}>{label}</div>
    </div>
  );
}

interface MiniChartProps {
  data: DailyMetric[];
}

function MiniChart({ data }: MiniChartProps) {
  const { sessionsPath, postsPath, pagesPath, xLabels } = useMemo(() => {
    if (data.length === 0) return { sessionsPath: '', postsPath: '', pagesPath: '', xLabels: [] };

    const width = 100;
    const height = 100;
    const padding = { top: 10, bottom: 20, left: 5, right: 5 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;

    // Find max value across all metrics
    const maxVal = Math.max(
      ...data.map(d => Math.max(d.sessions, d.posts, d.pages_loaded)),
      1
    );

    const xStep = chartWidth / Math.max(data.length - 1, 1);

    const buildPath = (values: number[]) => {
      return values.map((v, i) => {
        const x = padding.left + i * xStep;
        const y = padding.top + chartHeight - (v / maxVal) * chartHeight;
        return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
      }).join(' ');
    };

    // X-axis labels (show first, middle, last)
    const labels: { x: number; label: string }[] = [];
    if (data.length > 0) {
      const formatDate = (d: string) => {
        const date = new Date(d);
        return `${date.getMonth() + 1}/${date.getDate()}`;
      };
      labels.push({ x: padding.left, label: formatDate(data[0].day_bucket) });
      if (data.length > 2) {
        const midIdx = Math.floor(data.length / 2);
        labels.push({ x: padding.left + midIdx * xStep, label: formatDate(data[midIdx].day_bucket) });
      }
      labels.push({ x: padding.left + (data.length - 1) * xStep, label: formatDate(data[data.length - 1].day_bucket) });
    }

    return {
      sessionsPath: buildPath(data.map(d => d.sessions)),
      postsPath: buildPath(data.map(d => d.posts)),
      pagesPath: buildPath(data.map(d => d.pages_loaded)),
      xLabels: labels,
    };
  }, [data]);

  if (data.length === 0) {
    return <div style={styles.noData}>No data to display</div>;
  }

  return (
    <div style={styles.chartContainer}>
      <svg style={styles.chartSvg} viewBox="0 0 100 100" preserveAspectRatio="none">
        {/* Sessions line (blue) */}
        <path
          d={sessionsPath}
          fill="none"
          stroke="rgba(100, 180, 255, 0.8)"
          strokeWidth="1.5"
          vectorEffect="non-scaling-stroke"
        />
        {/* Posts line (green) */}
        <path
          d={postsPath}
          fill="none"
          stroke="rgba(100, 255, 150, 0.8)"
          strokeWidth="1.5"
          vectorEffect="non-scaling-stroke"
        />
        {/* Pages line (yellow) */}
        <path
          d={pagesPath}
          fill="none"
          stroke="rgba(255, 220, 100, 0.8)"
          strokeWidth="1.5"
          vectorEffect="non-scaling-stroke"
        />
        {/* X-axis labels */}
        {xLabels.map((l, i) => (
          <text
            key={i}
            x={l.x}
            y="98"
            fill="rgba(255, 255, 255, 0.35)"
            fontSize="6"
            textAnchor={i === 0 ? 'start' : i === xLabels.length - 1 ? 'end' : 'middle'}
          >
            {l.label}
          </text>
        ))}
      </svg>
      <div style={styles.chartLegend}>
        <div style={styles.legendItem}>
          <div style={{ ...styles.legendDot, background: 'rgba(100, 180, 255, 0.8)' }} />
          Sessions
        </div>
        <div style={styles.legendItem}>
          <div style={{ ...styles.legendDot, background: 'rgba(100, 255, 150, 0.8)' }} />
          Posts
        </div>
        <div style={styles.legendItem}>
          <div style={{ ...styles.legendDot, background: 'rgba(255, 220, 100, 0.8)' }} />
          Pages
        </div>
      </div>
    </div>
  );
}

export function ChangeOverTime() {
  const { filters, window, lensLabel, windowLabel } = useInsightsFilters();
  
  const { data, loading, error } = useChangeOverTimeMetrics(filters, window);

  // Calculate summary stats (5 KPIs)
  const summary = useMemo(() => {
    if (data.length === 0) {
      return { 
        totalSessions: 0, 
        totalPosts: 0, 
        postRate: 0, 
        totalPages: 0, 
        pagesPerSession: 0 
      };
    }
    const totalSessions = data.reduce((sum, d) => sum + d.sessions, 0);
    const totalPosts = data.reduce((sum, d) => sum + d.posts, 0);
    const totalPages = data.reduce((sum, d) => sum + d.pages_loaded, 0);
    const postRate = totalSessions > 0 ? totalPosts / totalSessions : 0;
    const pagesPerSession = totalSessions > 0 ? totalPages / totalSessions : 0;

    return { totalSessions, totalPosts, postRate, totalPages, pagesPerSession };
  }, [data]);

  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <h2 style={styles.title}>Change Over Time</h2>
        <span style={styles.lens}>{lensLabel} · {windowLabel}</span>
      </div>
      <p style={styles.subtitle}>Track daily trends in engagement</p>

      {loading && (
        <div style={styles.loadingText}>Loading...</div>
      )}

      {error && !loading && (
        <div style={styles.errorText}>{error}</div>
      )}

      {!loading && !error && data.length === 0 && (
        <div style={styles.noData}>No data for this range</div>
      )}

      {!loading && !error && data.length > 0 && (
        <>
          {/* 5 KPI Summary tiles */}
          <div style={styles.summaryGrid}>
            <SummaryTile 
              value={summary.totalSessions.toLocaleString()} 
              label="Sessions" 
            />
            <SummaryTile 
              value={summary.totalPosts.toLocaleString()} 
              label="Posts" 
            />
            <SummaryTile 
              value={`${(summary.postRate * 100).toFixed(1)}%`} 
              label="Post Rate" 
            />
            <SummaryTile 
              value={summary.totalPages.toLocaleString()} 
              label="Pages Loaded" 
            />
            <SummaryTile 
              value={summary.pagesPerSession.toFixed(1)} 
              label="Pages / Session" 
            />
          </div>

          {/* Chart */}
          <MiniChart data={data} />
        </>
      )}
    </div>
  );
}
