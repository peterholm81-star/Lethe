import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { useInsightsFilters } from '../contexts/InsightsContext';
import { createLatestOnlyGuard, type LatestOnlyGuard } from '../insights/insightsRpc';

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
    gridTemplateColumns: '80px 52px 1fr auto',
    alignItems: 'center',
    gap: '12px',
  } as React.CSSProperties,

  label: {
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.5)',
    textTransform: 'capitalize' as const,
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
    minWidth: '72px',
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

  noData: {
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.4)',
    textAlign: 'center' as const,
    padding: '24px 0',
  } as React.CSSProperties,
};

interface IntentRowProps {
  label: string;
  percent: number;
  count: number;
  loading?: boolean;
}

function IntentRow({ label, percent, count, loading }: IntentRowProps) {
  return (
    <div style={styles.row}>
      <div style={styles.label}>{label}</div>
      <div style={loading ? styles.percentSkeleton : styles.percent}>
        {loading ? '—' : `${percent}%`}
      </div>
      <div style={styles.trackContainer}>
        <div style={{ ...styles.trackFill, width: loading ? '0%' : `${percent}%` }} />
      </div>
      <div style={styles.tally}>{loading ? '—' : `≈ ${count} posts`}</div>
    </div>
  );
}

interface IntentData {
  label: string;
  percent: number;
  count: number;
}

// Skeleton placeholder labels for loading state
const skeletonLabels = ['Curiosity', 'Regret', 'Loneliness', 'Desire', 'Relief'];

export function IntentCard() {
  const { window, lensLabel, windowLabel } = useInsightsFilters();
  
  const [data, setData] = useState<IntentData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchIntentData = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();
    
    setLoading(true);
    setError(null);

    try {
      // Use window timestamps for time filtering
      const startIso = window.startUtcIso;
      const endIso = window.endUtcIso;

      // Query confessions table for intents within window
      const { data: confessions, error: queryError } = await supabase
        .from('confessions')
        .select('intent')
        .gte('created_at', startIso)
        .lt('created_at', endIso)
        .not('intent', 'is', null);

      if (guardRef.current.warnIfStale(reqId, 'INTENT')) {
        return;
      }

      if (queryError) {
        throw queryError;
      }

      if (!confessions || confessions.length === 0) {
        setData([]);
        setLoading(false);
        return;
      }

      // Aggregate intent counts
      const intentCounts: Record<string, number> = {};
      for (const row of confessions) {
        const intent = row.intent as string;
        if (intent) {
          intentCounts[intent] = (intentCounts[intent] || 0) + 1;
        }
      }

      // Sort by count descending and take top 5
      const sorted = Object.entries(intentCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5);

      // Calculate total for top 5 (percentage based on top 5 total, not all)
      const top5Total = sorted.reduce((sum, [, count]) => sum + count, 0);

      // Build result with percentages
      const result: IntentData[] = sorted.map(([label, count]) => ({
        label: label.charAt(0).toUpperCase() + label.slice(1), // Capitalize
        count,
        percent: top5Total > 0 ? Math.round((count / top5Total) * 100) : 0,
      }));

      // Adjust percentages to sum to 100
      const percentSum = result.reduce((sum, r) => sum + r.percent, 0);
      if (percentSum !== 100 && result.length > 0) {
        result[0].percent += 100 - percentSum;
      }

      setData(result);
      setLoading(false);

    } catch (err) {
      if (guardRef.current.warnIfStale(reqId, 'INTENT')) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to fetch intent data';
      setError(message);
      setLoading(false);
    }
  }, [window.startUtcIso, window.endUtcIso]);

  useEffect(() => {
    fetchIntentData();
  }, [fetchIntentData]);

  const showError = !loading && error;
  const showNoData = !loading && !error && data.length === 0;
  const showData = !loading && !error && data.length > 0;

  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <h2 style={styles.title}>Intent</h2>
        <span style={styles.lens}>{lensLabel} · {windowLabel}</span>
      </div>
      <p style={styles.subtitle}>What people came here to do</p>

      {loading && (
        <div style={styles.rows}>
          {skeletonLabels.map((label) => (
            <IntentRow key={label} label={label} percent={0} count={0} loading />
          ))}
        </div>
      )}

      {showError && (
        <div style={{ textAlign: 'center', padding: '16px 0' }}>
          <p style={styles.errorText}>Failed to load intent data</p>
          <p style={styles.errorHint}>Check connection and try again</p>
          <button style={styles.retryButton} onClick={fetchIntentData}>
            Retry
          </button>
        </div>
      )}

      {showNoData && (
        <div style={styles.noData}>No data for this date</div>
      )}

      {showData && (
        <div style={styles.rows}>
          {data.map((intent) => (
            <IntentRow
              key={intent.label}
              label={intent.label}
              percent={intent.percent}
              count={intent.count}
            />
          ))}
        </div>
      )}
    </div>
  );
}
