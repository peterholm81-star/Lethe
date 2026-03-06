import { useState, useMemo, useCallback } from 'react';
import {
  useTrendsV1,
  type TrendComparisonRow,
  type TrendScope,
  type TrendScopeData,
} from '../hooks/useTrendsV1';
import { useTrendsSummaryV1, type ScopeSummary } from '../hooks/useTrendsSummaryV1';
import { useYearWheelV1 } from '../hooks/useYearWheelV1';
import { useEmotionFingerprintV1 } from '../hooks/useEmotionFingerprintV1';
import { useTrendsMoversV1 } from '../hooks/useTrendsMoversV1';
import { DualSeasonalityWheels } from '../components/trends/SeasonalityWheelV2';
import { EmotionalFingerprintWheel } from '../components/trends/EmotionalFingerprintWheel';
import { TrendsMoversPanel } from '../components/trends/TrendsMoversPanel';
import { useFiltersCore, FilterBarCore, toLegacyFilters } from '../engine/filters_core';
import { InfoHint } from '../components/ui/InfoHint';

// =============================================================================
// INFO TEXTS
// =============================================================================

const info = {
  periodSummary: {
    title: 'Period Summary',
    body: [
      'Alltid 7d og 30d side-by-side — uavhengig av valgt tidsvindu.',
      'Momentum = delta% 7d minus delta% 30d (percentage points).',
      'Positivt momentum → akselererende vekst. Negativt → avtagende.',
    ],
  },
  topMovers: {
    title: 'Top Movers',
    body: [
      'Viser nøkkelmetrikker sammenlignet med forrige periode.',
      'Delta% = prosentvis endring (current vs previous).',
      'Null-delta betyr ikke nok data i forrige periode.',
    ],
  },
  geoMovers: {
    title: 'Geo Movers',
    body: [
      'Topp 5 land med sterkest vekst og topp 5 med størst nedgang.',
      'Basert på sessions i valgt tidsvindu vs forrige.',
      'Krever minst 2 perioder med data for sammenligning.',
    ],
  },
  trendlines: {
    title: 'Trendlines',
    body: [
      'Daglig utvikling for valgt tidsperiode.',
      'Brukes for å se momentum og mønstre.',
      'Sparklines — ingen tall-akse, kun form.',
    ],
  },
  spikes: {
    title: 'Spikes & Alerts',
    body: [
      'Metrikker med |delta| > 25% flagges automatisk.',
      'Positiv spike = vekst, negativ spike = mulig problem.',
      'Basert på valgt scope.',
    ],
  },
  seasonality: {
    title: 'Seasonality',
    body: [
      '12 måneder visualisert som konsentriske ringer.',
      'Ytterst: sessions-volum (blå). Midt: posts/session (lilla). Innerst: mood-balance (grønn/rød).',
      'Brukes for å finne sesong-mønstre i trafikk, aktivitet og stemning.',
    ],
  },
  emotionMovers: {
    title: 'Emotion Movers',
    body: [
      'Sammenligner emosjons-tagger siste 7 dager mot gjennomsnittlig 7-dagersrate de siste 28 dagene.',
      'Rising = øker. Falling = synker. Emerging = nesten 0 i baseline, eksploderer nå.',
    ],
  },
  emotionalFingerprint: {
    title: 'Emotional Fingerprint',
    body: [
      'Radar-chart med 12 måneders-akser og ett polygon per emosjon.',
      'Hver emosjon er selv-normalisert (0..1) slik at formen viser sesong-rytme, ikke absolutt volum.',
      'Brukes for å oppdage emosjonelle mønstre gjennom året — f.eks. ensomhet om vinteren, håp om våren.',
    ],
  },
};

// =============================================================================
// HELPERS
// =============================================================================

const METRIC_LABELS: Record<string, string> = {
  sessions: 'Sessions',
  reads: 'Reads',
  posts: 'Posts',
  ads_shown: 'Ads Shown',
};

const METRIC_ORDER = ['sessions', 'reads', 'posts', 'ads_shown'];

function fmtNum(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(Math.round(n));
}

function fmtDelta(pct: number | null): string {
  if (pct == null) return '—';
  const sign = pct >= 0 ? '+' : '';
  return `${sign}${pct.toFixed(1)}%`;
}

function fmtPP(pp: number | null): string {
  if (pp == null) return '—';
  const sign = pp >= 0 ? '+' : '';
  return `${sign}${pp.toFixed(1)}pp`;
}

function deltaColor(pct: number | null): string {
  if (pct == null) return 'rgba(255,255,255,0.35)';
  if (pct > 5) return 'rgba(100, 200, 150, 0.9)';
  if (pct < -5) return 'rgba(220, 120, 120, 0.9)';
  return 'rgba(255, 255, 255, 0.6)';
}

function momentumColor(pp: number | null): string {
  if (pp == null) return 'rgba(255,255,255,0.25)';
  if (pp > 3) return 'rgba(100,220,160,0.85)';
  if (pp < -3) return 'rgba(220,120,120,0.85)';
  return 'rgba(255,255,255,0.45)';
}

function getCountryName(code: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'region' }).of(code) ?? code;
  } catch { return code; }
}

const SPIKE_THRESHOLD = 25;

function scopeLabel(s: TrendScope): string {
  if (s.type === 'global') return 'Global';
  if (s.type === 'region') return s.region;
  return getCountryName(s.country);
}

const COLORS_A = { line: 'rgba(100,180,255,0.7)', label: 'rgba(100,180,255,0.85)' };
const COLORS_B = { line: 'rgba(255,180,100,0.7)', label: 'rgba(255,180,100,0.85)' };

const KNOWN_REGIONS = [
  'Europe', 'North America', 'South America', 'Asia', 'Africa', 'Oceania', 'Middle East',
];

// =============================================================================
// SPARKLINE (supports 1 or 2 lines)
// =============================================================================

function Sparkline({ lines, width = 260, height = 48 }: {
  lines: { points: number[]; color: string }[];
  width?: number;
  height?: number;
}) {
  const allPts = lines.flatMap(l => l.points);
  if (allPts.length < 2) return <div style={{ width, height, opacity: 0.3, fontSize: 10, color: 'rgba(255,255,255,0.3)' }}>No data</div>;
  const max = Math.max(...allPts, 1);
  const min = Math.min(...allPts, 0);
  const range = max - min || 1;

  function toPath(pts: number[]): string {
    if (pts.length < 2) return '';
    const xStep = width / (pts.length - 1);
    return pts.map((v, i) => {
      const x = i * xStep;
      const y = height - ((v - min) / range) * (height - 4) - 2;
      return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
    }).join(' ');
  }

  return (
    <svg width={width} height={height} style={{ display: 'block' }}>
      {lines.map((l, idx) => (
        <path key={idx} d={toPath(l.points)} fill="none" stroke={l.color}
          strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round"
          opacity={lines.length > 1 ? 0.85 : 1}
        />
      ))}
    </svg>
  );
}

// =============================================================================
// DERIVED DATA HELPERS
// =============================================================================

function sortedGlobal(data: TrendScopeData): TrendComparisonRow[] {
  return [...data.global].sort((a, b) => Math.abs(b.deltaAbs) - Math.abs(a.deltaAbs));
}

function getSpikes(data: TrendScopeData): TrendComparisonRow[] {
  return data.global
    .filter(r => r.deltaPct != null && Math.abs(r.deltaPct) >= SPIKE_THRESHOLD)
    .sort((a, b) => Math.abs(b.deltaPct ?? 0) - Math.abs(a.deltaPct ?? 0));
}

function getGeoMovers(data: TrendScopeData) {
  const sess = data.countries.filter(r => r.metricKey === 'sessions' && r.deltaPct != null);
  const sorted = [...sess].sort((a, b) => (b.deltaPct ?? 0) - (a.deltaPct ?? 0));
  return {
    up: sorted.filter(r => (r.deltaPct ?? 0) > 0).slice(0, 5),
    down: sorted.filter(r => (r.deltaPct ?? 0) < 0).slice(-5).reverse(),
  };
}

function getTrendByMetric(data: TrendScopeData): Record<string, number[]> {
  const map: Record<string, number[]> = {};
  const sorted = [...data.trendline].sort((a, b) => a.day.localeCompare(b.day));
  for (const p of sorted) {
    if (!map[p.metricKey]) map[p.metricKey] = [];
    map[p.metricKey].push(p.value);
  }
  return map;
}

// =============================================================================
// SCOPE SELECTOR
// =============================================================================

function ScopeSelector({ value, onChange, label, color }: {
  value: TrendScope;
  onChange: (s: TrendScope) => void;
  label: string;
  color: string;
}) {
  const handleTypeChange = useCallback((type: string) => {
    if (type === 'global') onChange({ type: 'global' });
    else if (type === 'region') onChange({ type: 'region', region: KNOWN_REGIONS[0] });
    else onChange({ type: 'country', country: 'US' });
  }, [onChange]);

  return (
    <div style={sel.row}>
      <span style={{ ...sel.label, color }}>{label}</span>
      <select
        value={value.type}
        onChange={e => handleTypeChange(e.target.value)}
        style={sel.select}
      >
        <option value="global">Global</option>
        <option value="region">Region</option>
        <option value="country">Country</option>
      </select>

      {value.type === 'region' && (
        <select
          value={value.region}
          onChange={e => onChange({ type: 'region', region: e.target.value })}
          style={sel.select}
        >
          {KNOWN_REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
        </select>
      )}

      {value.type === 'country' && (
        <input
          type="text"
          value={value.country}
          onChange={e => onChange({ type: 'country', country: e.target.value.toUpperCase().slice(0, 2) })}
          placeholder="CC"
          maxLength={2}
          style={{ ...sel.select, width: 50, textTransform: 'uppercase' as const }}
        />
      )}
    </div>
  );
}

// =============================================================================
// PERIOD SUMMARY SUB-COMPONENTS
// =============================================================================

function PeriodSummaryColumn({ summary, label, color }: {
  summary: ScopeSummary;
  label?: string;
  color?: string;
}) {
  return (
    <div style={{ flex: 1, minWidth: 0 }}>
      {label && <div style={{ fontSize: 9, fontWeight: 700, color: color ?? 'rgba(255,255,255,0.5)', marginBottom: 8, letterSpacing: '0.06em' }}>{label}</div>}
      <PeriodRow period="7d" data={summary.d7} dataOther={summary.d30} />
      <div style={{ height: 8 }} />
      <PeriodRow period="30d" data={summary.d30} dataOther={summary.d7} />
    </div>
  );
}

function PeriodRow({ period, data, dataOther }: {
  period: '7d' | '30d';
  data: { rows: TrendComparisonRow[] } | null;
  dataOther: { rows: TrendComparisonRow[] } | null;
}) {
  if (!data || data.rows.length === 0) {
    return (
      <div>
        <div style={ps.periodLabel}>{period} vs prev {period}</div>
        <div style={card.empty}>No data for {period}</div>
      </div>
    );
  }

  const byMetric = new Map(data.rows.map(r => [r.metricKey, r]));
  const otherByMetric = dataOther ? new Map(dataOther.rows.map(r => [r.metricKey, r])) : null;

  return (
    <div>
      <div style={ps.periodLabel}>{period} vs prev {period}</div>
      <div style={ps.metricsGrid}>
        {METRIC_ORDER.map(mk => {
          const r = byMetric.get(mk);
          if (!r) return null;
          const otherR = otherByMetric?.get(mk);

          // Momentum: delta% this period minus delta% other period (7d - 30d or 30d - 7d)
          let momentum: number | null = null;
          if (period === '7d' && r.deltaPct != null && otherR?.deltaPct != null) {
            momentum = r.deltaPct - otherR.deltaPct;
          }

          return (
            <div key={mk} style={ps.metricCell}>
              <div style={ps.metricName}>{METRIC_LABELS[mk] ?? mk}</div>
              <div style={ps.metricValues}>
                <span style={ps.current}>{fmtNum(r.current)}</span>
                <span style={ps.prev}>{fmtNum(r.previous)}</span>
                <span style={{ ...ps.delta, color: deltaColor(r.deltaPct) }}>{fmtDelta(r.deltaPct)}</span>
                {momentum != null && (
                  <span style={{ ...ps.momentum, color: momentumColor(momentum) }} title="Momentum: 7d delta minus 30d delta">
                    {fmtPP(momentum)}
                  </span>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// =============================================================================
// COMPONENT
// =============================================================================

export function TrendsPage() {
  const { filters: coreFilters } = useFiltersCore();
  const { window: win } = useMemo(() => toLegacyFilters(coreFilters), [coreFilters]);

  // Compare state
  const [compareOn, setCompareOn] = useState(false);
  const [scopeA, setScopeA] = useState<TrendScope>({ type: 'global' });
  const [scopeB, setScopeB] = useState<TrendScope>({ type: 'region', region: 'Europe' });

  // Main trends (uses selected time window)
  const { a, b, loading, error } = useTrendsV1(
    win.days,
    scopeA,
    compareOn ? scopeB : null,
  );

  // Period summary (always 7d + 30d regardless of selected time window)
  const summary = useTrendsSummaryV1(scopeA, compareOn ? scopeB : null);

  // Year wheel (always 365d)
  const yearWheelA = useYearWheelV1(scopeA);
  const yearWheelB = useYearWheelV1(compareOn ? scopeB : scopeA);

  // Emotional fingerprint (always 365d)
  const emoFp = useEmotionFingerprintV1(scopeA, compareOn ? scopeB : null);

  // Emotion movers (7d vs 28d baseline)
  const emoMovers = useTrendsMoversV1(scopeA, compareOn ? scopeB : null);

  // Derived data for A
  const aGlobal = useMemo(() => sortedGlobal(a), [a]);
  const aSpikes = useMemo(() => getSpikes(a), [a]);
  const aGeo = useMemo(() => getGeoMovers(a), [a]);
  const aTrend = useMemo(() => getTrendByMetric(a), [a]);

  // Derived data for B
  const bGlobal = useMemo(() => b ? sortedGlobal(b) : [], [b]);
  const bGeo = useMemo(() => b ? getGeoMovers(b) : { up: [], down: [] }, [b]);
  const bTrend = useMemo(() => b ? getTrendByMetric(b) : {}, [b]);

  const isEmpty = !loading && a.global.length === 0;

  return (
    <div style={page.container}>
      {/* Filter Row */}
      <div style={page.filterRow}>
        <div style={page.titleSection}>
          <h1 style={page.title}>Trends</h1>
          <span style={page.subtitle}>{win.days}d vs prev {win.days}d</span>
        </div>
        <FilterBarCore
          enableCountry={false}
          enableCity={false}
          showReset={true}
          showCompare={false}
          sticky={true}
        />
      </div>

      {/* Compare controls */}
      <div style={cmp.bar}>
        <label style={cmp.toggle}>
          <input type="checkbox" checked={compareOn} onChange={e => setCompareOn(e.target.checked)} />
          <span style={cmp.toggleLabel}>Compare</span>
        </label>
        <ScopeSelector value={scopeA} onChange={setScopeA} label="A" color={COLORS_A.label} />
        {compareOn && (
          <ScopeSelector value={scopeB} onChange={setScopeB} label="B" color={COLORS_B.label} />
        )}
      </div>

      {/* PERIOD SUMMARY — always at top */}
      <div style={{ ...card.box, marginBottom: 16 }}>
        <div style={card.header}>
          <span style={card.title}>Period Summary</span>
          <span style={card.badge}>7d + 30d</span>
          <InfoHint {...info.periodSummary} />
        </div>
        {summary.loading ? (
          <div style={card.empty}>Loading summary...</div>
        ) : summary.error ? (
          <div style={{ ...card.empty, color: 'rgba(220,120,120,0.8)' }}>{summary.error}</div>
        ) : (
          <div style={{ display: 'flex', gap: 20 }}>
            <PeriodSummaryColumn
              summary={summary.a}
              label={compareOn ? `A: ${scopeLabel(scopeA)}` : undefined}
              color={compareOn ? COLORS_A.label : undefined}
            />
            {compareOn && summary.b && (
              <>
                <div style={{ width: 1, background: 'rgba(255,255,255,0.06)', alignSelf: 'stretch' }} />
                <PeriodSummaryColumn
                  summary={summary.b}
                  label={`B: ${scopeLabel(scopeB)}`}
                  color={COLORS_B.label}
                />
              </>
            )}
          </div>
        )}
      </div>

      {/* EMOTION MOVERS — Rising / Falling / Emerging */}
      <div style={{ marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
          <span style={card.title}>Emotion Movers</span>
          <span style={card.badge}>7d vs 28d</span>
          <InfoHint {...info.emotionMovers} />
        </div>
        <TrendsMoversPanel
          rowsA={emoMovers.rowsA}
          rowsB={compareOn ? emoMovers.rowsB : null}
          compare={compareOn}
          loading={emoMovers.loading}
          error={emoMovers.error}
        />
      </div>

      {error && <div style={page.error}>{error}</div>}
      {loading && <div style={page.loading}>Loading trends...</div>}

      {isEmpty && !error && (
        <div style={page.empty}>
          Not enough data yet. Trends need at least {win.days * 2} days of event data.
        </div>
      )}

      {!loading && !isEmpty && (
        <div style={page.grid}>
          {/* LEFT COLUMN */}
          <div style={page.column}>
            {/* Top Movers */}
            <div style={card.box}>
              <div style={card.header}>
                <span style={card.title}>Top Movers</span>
                {compareOn && <span style={{ ...card.badge, color: COLORS_A.label }}>A: {scopeLabel(scopeA)}</span>}
                {compareOn && b && <span style={{ ...card.badge, color: COLORS_B.label }}>B: {scopeLabel(scopeB)}</span>}
                <InfoHint {...info.topMovers} />
              </div>
              {compareOn && b ? (
                <MoversCompareTable a={aGlobal} b={bGlobal} />
              ) : (
                <MoversTable rows={aGlobal} />
              )}
            </div>

            {/* Spikes */}
            <div style={card.box}>
              <div style={card.header}>
                <span style={card.title}>Spikes & Alerts</span>
                <InfoHint {...info.spikes} />
              </div>
              <SpikesList spikes={aSpikes} label={compareOn ? scopeLabel(scopeA) : undefined} />
              {compareOn && b && (
                <>
                  <div style={{ marginTop: 10, marginBottom: 4, fontSize: 9, color: COLORS_B.label, fontWeight: 600 }}>
                    B: {scopeLabel(scopeB)}
                  </div>
                  <SpikesList spikes={getSpikes(b)} />
                </>
              )}
            </div>
          </div>

          {/* RIGHT COLUMN */}
          <div style={page.column}>
            {/* Geo Movers */}
            <div style={card.box}>
              <div style={card.header}>
                <span style={card.title}>Geo Movers</span>
                <span style={card.badge}>Sessions</span>
                <InfoHint {...info.geoMovers} />
              </div>
              {compareOn && b ? (
                <div style={{ display: 'flex', flexDirection: 'column' as const, gap: 12 }}>
                  <GeoSection data={aGeo} label={`A: ${scopeLabel(scopeA)}`} color={COLORS_A.label} />
                  <GeoSection data={bGeo} label={`B: ${scopeLabel(scopeB)}`} color={COLORS_B.label} />
                </div>
              ) : (
                <GeoSection data={aGeo} />
              )}
            </div>

            {/* Trendlines */}
            <div style={card.box}>
              <div style={card.header}>
                <span style={card.title}>Trendlines</span>
                <span style={card.badge}>{win.days}d</span>
                <InfoHint {...info.trendlines} />
              </div>
              {Object.keys(aTrend).length === 0 ? (
                <div style={card.empty}>No trendline data</div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column' as const, gap: '16px' }}>
                  {(['sessions', 'posts'] as const).map(mk => {
                    const ptsA = aTrend[mk];
                    const ptsB = bTrend[mk];
                    if (!ptsA && !ptsB) return null;
                    const lines: { points: number[]; color: string }[] = [];
                    if (ptsA) lines.push({ points: ptsA, color: compareOn ? COLORS_A.line : (mk === 'sessions' ? 'rgba(100,180,255,0.7)' : 'rgba(100,200,150,0.7)') });
                    if (compareOn && ptsB) lines.push({ points: ptsB, color: COLORS_B.line });
                    return (
                      <div key={mk}>
                        <div style={trend.label}>
                          {METRIC_LABELS[mk] ?? mk}
                          {compareOn && (
                            <span style={{ marginLeft: 8, fontSize: 9, opacity: 0.5 }}>
                              <span style={{ color: COLORS_A.label }}>A</span>
                              {ptsB && <> / <span style={{ color: COLORS_B.label }}>B</span></>}
                            </span>
                          )}
                        </div>
                        <Sparkline lines={lines} />
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Seasonality Year Wheel */}
            <div style={card.box}>
              <div style={card.header}>
                <span style={card.title}>Seasonality</span>
                <span style={card.badge}>12mo</span>
                <InfoHint {...info.seasonality} />
              </div>
              <DualSeasonalityWheels
                aData={yearWheelA.data}
                bData={compareOn ? yearWheelB.data : null}
                aLabel={compareOn ? `A: ${scopeLabel(scopeA)}` : undefined}
                bLabel={compareOn ? `B: ${scopeLabel(scopeB)}` : undefined}
                loading={yearWheelA.loading || (compareOn && yearWheelB.loading)}
                error={yearWheelA.error || yearWheelB.error}
              />
            </div>

            {/* Emotional Fingerprint Wheel */}
            <div style={card.box}>
              <div style={card.header}>
                <span style={card.title}>Emotional Fingerprint</span>
                <span style={card.badge}>12mo</span>
                <InfoHint {...info.emotionalFingerprint} />
              </div>
              <EmotionalFingerprintWheel
                rowsA={emoFp.rowsA}
                rowsB={compareOn ? emoFp.rowsB : null}
                compare={compareOn}
                loading={emoFp.loading}
                error={emoFp.error}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// =============================================================================
// SUB-COMPONENTS
// =============================================================================

function MoversTable({ rows }: { rows: TrendComparisonRow[] }) {
  if (rows.length === 0) return <div style={card.empty}>No data</div>;
  return (
    <div style={card.table}>
      <div style={card.tableHeaderRow}>
        <span style={card.th}>Metric</span>
        <span style={card.thR}>Current</span>
        <span style={card.thR}>Previous</span>
        <span style={card.thR}>Delta</span>
      </div>
      {rows.map(r => (
        <div key={r.metricKey} style={card.row}>
          <span style={card.td}>{METRIC_LABELS[r.metricKey] ?? r.metricKey}</span>
          <span style={card.tdR}>{fmtNum(r.current)}</span>
          <span style={card.tdR}>{fmtNum(r.previous)}</span>
          <span style={{ ...card.tdR, color: deltaColor(r.deltaPct), fontWeight: 600 }}>
            {fmtDelta(r.deltaPct)}
          </span>
        </div>
      ))}
    </div>
  );
}

function MoversCompareTable({ a, b }: { a: TrendComparisonRow[]; b: TrendComparisonRow[] }) {
  const metrics = [...new Set([...a, ...b].map(r => r.metricKey))];
  if (metrics.length === 0) return <div style={card.empty}>No data</div>;

  const bMap = new Map(b.map(r => [r.metricKey, r]));

  return (
    <div style={card.table}>
      <div style={{ ...card.tableHeaderRow, gridTemplateColumns: '1.2fr 0.8fr 0.8fr 0.8fr 0.8fr' }}>
        <span style={card.th}>Metric</span>
        <span style={{ ...card.thR, color: COLORS_A.label }}>A Δ</span>
        <span style={{ ...card.thR, color: COLORS_A.label }}>A cur</span>
        <span style={{ ...card.thR, color: COLORS_B.label }}>B Δ</span>
        <span style={{ ...card.thR, color: COLORS_B.label }}>B cur</span>
      </div>
      {metrics.map(mk => {
        const ra = a.find(r => r.metricKey === mk);
        const rb = bMap.get(mk);
        return (
          <div key={mk} style={{ ...card.row, gridTemplateColumns: '1.2fr 0.8fr 0.8fr 0.8fr 0.8fr' }}>
            <span style={card.td}>{METRIC_LABELS[mk] ?? mk}</span>
            <span style={{ ...card.tdR, color: deltaColor(ra?.deltaPct ?? null), fontWeight: 600 }}>
              {fmtDelta(ra?.deltaPct ?? null)}
            </span>
            <span style={card.tdR}>{ra ? fmtNum(ra.current) : '—'}</span>
            <span style={{ ...card.tdR, color: deltaColor(rb?.deltaPct ?? null), fontWeight: 600 }}>
              {fmtDelta(rb?.deltaPct ?? null)}
            </span>
            <span style={card.tdR}>{rb ? fmtNum(rb.current) : '—'}</span>
          </div>
        );
      })}
    </div>
  );
}

function SpikesList({ spikes, label }: { spikes: TrendComparisonRow[]; label?: string }) {
  return (
    <>
      {label && <div style={{ fontSize: 9, color: COLORS_A.label, fontWeight: 600, marginBottom: 4 }}>A: {label}</div>}
      {spikes.length === 0 ? (
        <div style={card.empty}>No significant spikes detected</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column' as const, gap: '6px' }}>
          {spikes.map(r => (
            <div key={r.metricKey} style={spike.row}>
              <span style={spike.icon}>{(r.deltaPct ?? 0) > 0 ? '▲' : '▼'}</span>
              <span style={spike.label}>{METRIC_LABELS[r.metricKey] ?? r.metricKey}</span>
              <span style={{ ...spike.delta, color: deltaColor(r.deltaPct) }}>
                {fmtDelta(r.deltaPct)} vs prev
              </span>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function GeoSection({ data, label, color }: {
  data: { up: TrendComparisonRow[]; down: TrendComparisonRow[] };
  label?: string;
  color?: string;
}) {
  const hasData = data.up.length > 0 || data.down.length > 0;
  return (
    <div>
      {label && <div style={{ fontSize: 9, fontWeight: 600, color: color ?? 'rgba(255,255,255,0.5)', marginBottom: 6 }}>{label}</div>}
      {!hasData ? (
        <div style={card.empty}>No country-level data</div>
      ) : (
        <div style={{ display: 'flex', gap: '16px' }}>
          <div style={{ flex: 1 }}>
            <div style={geo.sectionLabel}>Rising</div>
            {data.up.map(r => (
              <div key={r.scopeKey} style={geo.row}>
                <span style={geo.country}>{getCountryName(r.scopeKey)}</span>
                <span style={{ ...geo.delta, color: 'rgba(100,200,150,0.9)' }}>{fmtDelta(r.deltaPct)}</span>
              </div>
            ))}
            {data.up.length === 0 && <div style={card.empty}>—</div>}
          </div>
          <div style={geo.sep} />
          <div style={{ flex: 1 }}>
            <div style={geo.sectionLabel}>Falling</div>
            {data.down.map(r => (
              <div key={r.scopeKey} style={geo.row}>
                <span style={geo.country}>{getCountryName(r.scopeKey)}</span>
                <span style={{ ...geo.delta, color: 'rgba(220,120,120,0.9)' }}>{fmtDelta(r.deltaPct)}</span>
              </div>
            ))}
            {data.down.length === 0 && <div style={card.empty}>—</div>}
          </div>
        </div>
      )}
    </div>
  );
}

// =============================================================================
// STYLES
// =============================================================================

const page: Record<string, React.CSSProperties> = {
  container: {
    padding: '16px 28px 40px',
    minHeight: '100vh',
    background: 'linear-gradient(180deg, rgba(12,12,18,0.95) 0%, rgba(8,8,12,1) 100%)',
  },
  filterRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    marginBottom: 8,
    flexWrap: 'wrap',
    position: 'sticky',
    top: 0,
    zIndex: 100,
    background: 'linear-gradient(180deg, rgba(12,12,18,0.98) 0%, rgba(12,12,18,0.95) 100%)',
    backdropFilter: 'blur(12px)',
    padding: '16px 0',
    borderBottom: '1px solid rgba(255,255,255,0.04)',
  },
  titleSection: {
    display: 'flex',
    alignItems: 'baseline',
    gap: 12,
    marginRight: 'auto',
  },
  title: { margin: 0, fontSize: 14, fontWeight: 600, color: 'rgba(255,255,255,0.7)', letterSpacing: '-0.01em' },
  subtitle: { fontSize: 10, color: 'rgba(255,255,255,0.4)' },
  grid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 16,
    alignItems: 'start',
  },
  column: { display: 'flex', flexDirection: 'column', gap: 16 },
  error: {
    padding: '12px 16px',
    background: 'rgba(220,120,120,0.1)',
    border: '1px solid rgba(220,120,120,0.2)',
    borderRadius: 8,
    color: 'rgba(220,120,120,0.9)',
    fontSize: 12,
    marginBottom: 16,
  },
  loading: { padding: 24, textAlign: 'center', color: 'rgba(255,255,255,0.4)', fontSize: 12 },
  empty: { padding: 32, textAlign: 'center', color: 'rgba(255,255,255,0.35)', fontSize: 12 },
};

const cmp: Record<string, React.CSSProperties> = {
  bar: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    flexWrap: 'wrap',
    padding: '8px 0 14px',
  },
  toggle: { display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' },
  toggleLabel: { fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.6)' },
};

const sel: Record<string, React.CSSProperties> = {
  row: { display: 'flex', alignItems: 'center', gap: 6 },
  label: { fontSize: 10, fontWeight: 700, minWidth: 12 },
  select: {
    padding: '4px 8px',
    fontSize: 11,
    fontWeight: 500,
    color: 'rgba(255,255,255,0.85)',
    background: 'rgba(255,255,255,0.05)',
    border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 6,
    cursor: 'pointer',
  },
};

const card: Record<string, React.CSSProperties> = {
  box: {
    padding: '16px 18px',
    background: 'linear-gradient(135deg, rgba(20,20,30,0.9) 0%, rgba(15,15,22,0.95) 100%)',
    border: '1px solid rgba(255,255,255,0.06)',
    borderRadius: 10,
    boxShadow: '0 4px 20px rgba(0,0,0,0.25)',
  },
  header: { display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 },
  title: { fontSize: 12, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'rgba(255,255,255,0.7)' },
  badge: { fontSize: 9, fontWeight: 600, padding: '2px 6px', borderRadius: 4, background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.4)', textTransform: 'uppercase', letterSpacing: '0.06em' },
  empty: { fontSize: 11, color: 'rgba(255,255,255,0.3)', padding: '8px 0' },
  table: { display: 'flex', flexDirection: 'column', gap: 0 },
  tableHeaderRow: { display: 'grid', gridTemplateColumns: '1.2fr 1fr 1fr 1fr', gap: 8, paddingBottom: 6, borderBottom: '1px solid rgba(255,255,255,0.06)', marginBottom: 4 },
  th: { fontSize: 9, fontWeight: 600, color: 'rgba(255,255,255,0.3)', textTransform: 'uppercase', letterSpacing: '0.08em' },
  thR: { fontSize: 9, fontWeight: 600, color: 'rgba(255,255,255,0.3)', textTransform: 'uppercase', letterSpacing: '0.08em', textAlign: 'right' },
  row: { display: 'grid', gridTemplateColumns: '1.2fr 1fr 1fr 1fr', gap: 8, padding: '5px 0', borderBottom: '1px solid rgba(255,255,255,0.02)' },
  td: { fontSize: 11, color: 'rgba(255,255,255,0.7)' },
  tdR: { fontSize: 11, color: 'rgba(255,255,255,0.6)', textAlign: 'right', fontVariantNumeric: 'tabular-nums' },
};

const ps: Record<string, React.CSSProperties> = {
  periodLabel: {
    fontSize: 9,
    fontWeight: 600,
    textTransform: 'uppercase',
    letterSpacing: '0.08em',
    color: 'rgba(255,255,255,0.35)',
    marginBottom: 6,
    borderBottom: '1px solid rgba(255,255,255,0.04)',
    paddingBottom: 4,
  },
  metricsGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '6px 16px',
  },
  metricCell: {
    padding: '4px 0',
  },
  metricName: {
    fontSize: 9,
    fontWeight: 500,
    color: 'rgba(255,255,255,0.4)',
    textTransform: 'uppercase',
    letterSpacing: '0.06em',
    marginBottom: 2,
  },
  metricValues: {
    display: 'flex',
    alignItems: 'baseline',
    gap: 6,
    flexWrap: 'wrap',
  },
  current: {
    fontSize: 13,
    fontWeight: 600,
    color: 'rgba(255,255,255,0.85)',
    fontVariantNumeric: 'tabular-nums',
  },
  prev: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.3)',
    fontVariantNumeric: 'tabular-nums',
  },
  delta: {
    fontSize: 10,
    fontWeight: 600,
    fontVariantNumeric: 'tabular-nums',
  },
  momentum: {
    fontSize: 9,
    fontWeight: 700,
    padding: '1px 5px',
    borderRadius: 3,
    background: 'rgba(255,255,255,0.04)',
    fontVariantNumeric: 'tabular-nums',
  },
};

const spike: Record<string, React.CSSProperties> = {
  row: { display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px', background: 'rgba(255,255,255,0.02)', borderRadius: 6, border: '1px solid rgba(255,255,255,0.04)' },
  icon: { fontSize: 10, width: 14, textAlign: 'center' },
  label: { fontSize: 11, color: 'rgba(255,255,255,0.7)', flex: 1 },
  delta: { fontSize: 11, fontWeight: 600, fontVariantNumeric: 'tabular-nums' },
};

const geo: Record<string, React.CSSProperties> = {
  sectionLabel: { fontSize: 9, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.08em', color: 'rgba(255,255,255,0.3)', marginBottom: 6 },
  row: { display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid rgba(255,255,255,0.02)' },
  country: { fontSize: 11, color: 'rgba(255,255,255,0.7)' },
  delta: { fontSize: 11, fontWeight: 600, fontVariantNumeric: 'tabular-nums' },
  sep: { width: 1, background: 'rgba(255,255,255,0.06)', alignSelf: 'stretch' },
};

const trend: Record<string, React.CSSProperties> = {
  label: { fontSize: 10, fontWeight: 600, color: 'rgba(255,255,255,0.45)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 4 },
};
