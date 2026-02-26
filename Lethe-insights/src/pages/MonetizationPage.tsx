import { useState, useMemo } from 'react';
import { useEngagementFlow } from '../hooks/useEngagementFlow';
import { useFiltersCore, FilterBarCore, toLegacyFilters } from '../engine/filters_core';

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  page: {
    padding: '32px',
    maxWidth: '1100px',
  } as React.CSSProperties,

  header: {
    marginBottom: '32px',
  } as React.CSSProperties,

  title: {
    margin: '0 0 8px 0',
    fontSize: '24px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
  } as React.CSSProperties,

  disclaimer: {
    margin: 0,
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.45)',
    maxWidth: '600px',
    lineHeight: 1.5,
  } as React.CSSProperties,

  grid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '24px',
    alignItems: 'start',
  } as React.CSSProperties,

  card: {
    padding: '20px',
    background: 'rgba(255, 255, 255, 0.05)',
    border: '1px solid rgba(255, 255, 255, 0.09)',
    borderRadius: '14px',
  } as React.CSSProperties,

  cardTitle: {
    margin: '0 0 16px 0',
    fontSize: '12px',
    fontWeight: 550,
    letterSpacing: '0.12em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.85)',
  } as React.CSSProperties,

  inputGroup: {
    marginBottom: '16px',
  } as React.CSSProperties,

  inputLabel: {
    display: 'block',
    marginBottom: '6px',
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  inputRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  } as React.CSSProperties,

  slider: {
    flex: 1,
    height: '4px',
    WebkitAppearance: 'none' as const,
    appearance: 'none' as const,
    background: 'rgba(255, 255, 255, 0.15)',
    borderRadius: '2px',
    outline: 'none',
    cursor: 'pointer',
  } as React.CSSProperties,

  numberInput: {
    width: '70px',
    padding: '6px 10px',
    fontSize: '13px',
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '6px',
    color: 'rgba(255, 255, 255, 0.85)',
    outline: 'none',
    textAlign: 'right' as const,
  } as React.CSSProperties,

  select: {
    padding: '6px 10px',
    fontSize: '13px',
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '6px',
    color: 'rgba(255, 255, 255, 0.85)',
    outline: 'none',
    cursor: 'pointer',
  } as React.CSSProperties,

  metricRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    padding: '10px 0',
    borderBottom: '1px solid rgba(255, 255, 255, 0.05)',
  } as React.CSSProperties,

  metricLabel: {
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.6)',
  } as React.CSSProperties,

  metricValue: {
    fontSize: '18px',
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(255, 255, 255, 0.9)',
  } as React.CSSProperties,

  metricValueLarge: {
    fontSize: '28px',
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
    color: 'rgba(100, 200, 150, 0.9)',
  } as React.CSSProperties,

  sensitivityList: {
    margin: 0,
    padding: '0 0 0 16px',
    listStyle: 'decimal',
  } as React.CSSProperties,

  sensitivityItem: {
    padding: '8px 0',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.7)',
    lineHeight: 1.5,
  } as React.CSSProperties,

  sensitivityImpact: {
    fontWeight: 600,
    color: 'rgba(100, 200, 150, 0.9)',
  } as React.CSSProperties,

  recommendationList: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
  } as React.CSSProperties,

  recommendationItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: '10px',
    padding: '10px 0',
    borderBottom: '1px solid rgba(255, 255, 255, 0.05)',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.7)',
    lineHeight: 1.5,
  } as React.CSSProperties,

  recommendationIcon: {
    flexShrink: 0,
    width: '20px',
    height: '20px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '12px',
    background: 'rgba(255, 200, 100, 0.15)',
    borderRadius: '4px',
  } as React.CSSProperties,

  dataSource: {
    marginTop: '12px',
    padding: '10px 12px',
    background: 'rgba(255, 255, 255, 0.03)',
    borderRadius: '6px',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,

  dataSourceRow: {
    display: 'flex',
    justifyContent: 'space-between',
    padding: '2px 0',
  } as React.CSSProperties,

  fullWidth: {
    gridColumn: '1 / -1',
  } as React.CSSProperties,
};

// =============================================================================
// HELPERS
// =============================================================================

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function formatNOK(value: number): string {
  return `${value.toLocaleString('nb-NO', { minimumFractionDigits: 0, maximumFractionDigits: 0 })} NOK`;
}

function formatNumber(value: number, decimals = 0): string {
  return value.toLocaleString('nb-NO', { 
    minimumFractionDigits: decimals, 
    maximumFractionDigits: decimals 
  });
}

// =============================================================================
// COMPONENT
// =============================================================================

export function MonetizationPage() {
  // New filter system with URL sync
  const { filters: coreFilters } = useFiltersCore();
  
  // Convert to legacy format for existing hooks
  const { filters, window, lensLabel, windowLabel } = useMemo(
    () => toLegacyFilters(coreFilters),
    [coreFilters]
  );
  
  const { data: engagementData, loading } = useEngagementFlow(filters, window);

  // Assumptions (inputs)
  const [ecpm, setEcpm] = useState(35);
  const [fillRate, setFillRate] = useState(0.85);
  const [adsPerSessionCap, setAdsPerSessionCap] = useState(1);
  const [triggerShare, setTriggerShare] = useState(0.60);
  const [dropRateAfterAd, setDropRateAfterAd] = useState(0.40);

  // Derived data from engagement flow
  const sessionsTotal = engagementData?.sessions ?? 0;
  const pagesPerSession = engagementData?.pages_per_session ?? 0;
  const adsShownSessions = engagementData?.ads_shown_sessions ?? 0;
  const adDropSessions = engagementData?.ad_drop_sessions ?? 0;

  // Calculate drop rate from data if available
  const dataDropRate = adsShownSessions > 0 
    ? adDropSessions / adsShownSessions 
    : 0.40;

  // Use data-driven drop rate on first render if we have data
  const effectiveDropRate = engagementData && adsShownSessions > 0 
    ? dropRateAfterAd 
    : dropRateAfterAd;

  // Sessions per day based on window
  const sessionsPerDay = useMemo(() => {
    if (sessionsTotal === 0) return 0;
    switch (window.days) {
      case 1: return sessionsTotal;
      case 7: return sessionsTotal / 7;
      case 30: return sessionsTotal / 30;
      default: return sessionsTotal / 7;
    }
  }, [sessionsTotal, window.days]);

  // Revenue calculations
  const calculations = useMemo(() => {
    const impressionsPerDay = sessionsPerDay * adsPerSessionCap * triggerShare * fillRate;
    const revenuePerDay = (impressionsPerDay / 1000) * ecpm;
    const revenuePerMonth = revenuePerDay * 30;

    return {
      impressionsPerDay,
      revenuePerDay,
      revenuePerMonth,
    };
  }, [sessionsPerDay, adsPerSessionCap, triggerShare, fillRate, ecpm]);

  // Sensitivity analysis: +10% each input, calculate revenue impact
  const sensitivityAnalysis = useMemo(() => {
    const baseRevenue = calculations.revenuePerDay;
    if (baseRevenue === 0) return [];

    const factors = [
      { 
        name: 'eCPM', 
        newRevenue: ((sessionsPerDay * adsPerSessionCap * triggerShare * fillRate) / 1000) * (ecpm * 1.1),
      },
      { 
        name: 'Fill rate', 
        newRevenue: ((sessionsPerDay * adsPerSessionCap * triggerShare * clamp(fillRate * 1.1, 0, 1)) / 1000) * ecpm,
      },
      { 
        name: 'Trigger share', 
        newRevenue: ((sessionsPerDay * adsPerSessionCap * clamp(triggerShare * 1.1, 0, 1) * fillRate) / 1000) * ecpm,
      },
      { 
        name: 'Sessions', 
        newRevenue: ((sessionsPerDay * 1.1 * adsPerSessionCap * triggerShare * fillRate) / 1000) * ecpm,
      },
    ];

    return factors
      .map(f => ({
        name: f.name,
        impact: ((f.newRevenue - baseRevenue) / baseRevenue) * 100,
      }))
      .sort((a, b) => b.impact - a.impact)
      .slice(0, 3);
  }, [calculations.revenuePerDay, sessionsPerDay, adsPerSessionCap, triggerShare, fillRate, ecpm]);

  // Recommendations based on current values
  const recommendations = useMemo(() => {
    const recs: string[] = [];

    if (triggerShare < 0.4) {
      recs.push('Lower trigger threshold (show ad earlier) OR improve scroll depth to increase trigger share.');
    }
    if (fillRate < 0.7) {
      recs.push('Fill rate is low — likely low demand or geo mismatch. Test ad format/placement and ensure network setup.');
    }
    if (effectiveDropRate > 0.45) {
      recs.push('High drop rate after ad — consider moving ad later in session or reducing intrusiveness.');
    }
    if (pagesPerSession < 3) {
      recs.push('Low pages per session — focus on retention before increasing ad pressure.');
    }
    if (recs.length === 0) {
      recs.push('Current settings look balanced. Monitor fill rate and eCPM trends.');
    }

    return recs;
  }, [triggerShare, fillRate, effectiveDropRate, pagesPerSession]);

  return (
    <div style={styles.page}>
      {/* Header */}
      <div style={styles.header}>
        <h1 style={styles.title}>Revenue Lab</h1>
        <p style={styles.disclaimer}>
          Scenario calculator. Revenue depends on fill, eCPM, and ad timing. 
          All numbers are estimates based on current filter ({lensLabel} · {windowLabel}).
        </p>
      </div>

      {/* Filter Bar */}
      <FilterBarCore
        enableCountry={false}
        enableCity={false}
        showReset={true}
      />

      {/* Grid layout */}
      <div style={styles.grid}>
        {/* Assumptions Card */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Assumptions</h2>

          {/* eCPM */}
          <div style={styles.inputGroup}>
            <label style={styles.inputLabel}>eCPM (NOK)</label>
            <div style={styles.inputRow}>
              <input
                type="range"
                min="5"
                max="100"
                step="1"
                value={ecpm}
                onChange={(e) => setEcpm(Number(e.target.value))}
                style={styles.slider}
              />
              <input
                type="number"
                min="1"
                max="200"
                value={ecpm}
                onChange={(e) => setEcpm(clamp(Number(e.target.value), 1, 200))}
                style={styles.numberInput}
              />
            </div>
          </div>

          {/* Fill Rate */}
          <div style={styles.inputGroup}>
            <label style={styles.inputLabel}>Fill rate (0–1)</label>
            <div style={styles.inputRow}>
              <input
                type="range"
                min="0"
                max="1"
                step="0.01"
                value={fillRate}
                onChange={(e) => setFillRate(Number(e.target.value))}
                style={styles.slider}
              />
              <input
                type="number"
                min="0"
                max="1"
                step="0.01"
                value={fillRate}
                onChange={(e) => setFillRate(clamp(Number(e.target.value), 0, 1))}
                style={styles.numberInput}
              />
            </div>
          </div>

          {/* Ads per session cap */}
          <div style={styles.inputGroup}>
            <label style={styles.inputLabel}>Ads per session cap</label>
            <select
              value={adsPerSessionCap}
              onChange={(e) => setAdsPerSessionCap(Number(e.target.value))}
              style={styles.select}
            >
              <option value={0}>0</option>
              <option value={1}>1</option>
              <option value={2}>2</option>
              <option value={3}>3</option>
            </select>
          </div>

          {/* Trigger Share */}
          <div style={styles.inputGroup}>
            <label style={styles.inputLabel}>
              Trigger share (0–1)
              <span style={{ opacity: 0.6, marginLeft: '6px', fontSize: '10px' }}>
                % sessions reaching ad trigger
              </span>
            </label>
            <div style={styles.inputRow}>
              <input
                type="range"
                min="0"
                max="1"
                step="0.01"
                value={triggerShare}
                onChange={(e) => setTriggerShare(Number(e.target.value))}
                style={styles.slider}
              />
              <input
                type="number"
                min="0"
                max="1"
                step="0.01"
                value={triggerShare}
                onChange={(e) => setTriggerShare(clamp(Number(e.target.value), 0, 1))}
                style={styles.numberInput}
              />
            </div>
          </div>

          {/* Drop Rate After Ad */}
          <div style={styles.inputGroup}>
            <label style={styles.inputLabel}>
              Drop rate after ad (0–1)
              <span style={{ opacity: 0.6, marginLeft: '6px', fontSize: '10px' }}>
                {engagementData && adsShownSessions > 0 
                  ? `From data: ${(dataDropRate * 100).toFixed(0)}%` 
                  : 'No data'}
              </span>
            </label>
            <div style={styles.inputRow}>
              <input
                type="range"
                min="0"
                max="1"
                step="0.01"
                value={dropRateAfterAd}
                onChange={(e) => setDropRateAfterAd(Number(e.target.value))}
                style={styles.slider}
              />
              <input
                type="number"
                min="0"
                max="1"
                step="0.01"
                value={dropRateAfterAd}
                onChange={(e) => setDropRateAfterAd(clamp(Number(e.target.value), 0, 1))}
                style={styles.numberInput}
              />
            </div>
          </div>

          {/* Data source info */}
          <div style={styles.dataSource}>
            <div style={styles.dataSourceRow}>
              <span>Sessions ({window.days}d)</span>
              <span>{loading ? '—' : formatNumber(sessionsTotal)}</span>
            </div>
            <div style={styles.dataSourceRow}>
              <span>Sessions/day</span>
              <span>{loading ? '—' : formatNumber(sessionsPerDay, 1)}</span>
            </div>
            <div style={styles.dataSourceRow}>
              <span>Pages/session</span>
              <span>{loading ? '—' : formatNumber(pagesPerSession, 1)}</span>
            </div>
          </div>
        </div>

        {/* Estimated Revenue Card */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Estimated Revenue</h2>

          <div style={{ ...styles.metricRow, borderBottom: 'none', paddingBottom: '16px' }}>
            <span style={styles.metricLabel}>Revenue / month</span>
            <span style={styles.metricValueLarge}>
              {loading ? '—' : formatNOK(calculations.revenuePerMonth)}
            </span>
          </div>

          <div style={styles.metricRow}>
            <span style={styles.metricLabel}>Impressions / day</span>
            <span style={styles.metricValue}>
              {loading ? '—' : formatNumber(calculations.impressionsPerDay, 0)}
            </span>
          </div>

          <div style={styles.metricRow}>
            <span style={styles.metricLabel}>Revenue / day</span>
            <span style={styles.metricValue}>
              {loading ? '—' : formatNOK(calculations.revenuePerDay)}
            </span>
          </div>

          <div style={{ ...styles.metricRow, borderBottom: 'none' }}>
            <span style={styles.metricLabel}>Revenue / year (est.)</span>
            <span style={styles.metricValue}>
              {loading ? '—' : formatNOK(calculations.revenuePerMonth * 12)}
            </span>
          </div>
        </div>

        {/* Sensitivity Card */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>What Moves Revenue Most</h2>
          <p style={{ margin: '0 0 12px 0', fontSize: '12px', color: 'rgba(255, 255, 255, 0.4)' }}>
            Impact of +10% change in each factor
          </p>

          {sensitivityAnalysis.length === 0 ? (
            <p style={{ color: 'rgba(255, 255, 255, 0.4)', fontSize: '13px' }}>
              No data to analyze (revenue is zero)
            </p>
          ) : (
            <ol style={styles.sensitivityList}>
              {sensitivityAnalysis.map((item, i) => (
                <li key={i} style={styles.sensitivityItem}>
                  <strong>{item.name}</strong>:{' '}
                  <span style={styles.sensitivityImpact}>+{item.impact.toFixed(1)}%</span> revenue
                </li>
              ))}
            </ol>
          )}
        </div>

        {/* Recommendations Card */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Recommendations</h2>

          <ul style={styles.recommendationList}>
            {recommendations.map((rec, i) => (
              <li key={i} style={styles.recommendationItem}>
                <span style={styles.recommendationIcon}>💡</span>
                <span>{rec}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
