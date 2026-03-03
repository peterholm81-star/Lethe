import React, { useState, useMemo, useEffect, useCallback } from 'react';
import type { CountryOptRow } from '../../hooks/useCountryOptimizationV1';
import { useCountryOptimizationActionSummary } from '../../hooks/useCountryOptimizationActionSummary';
import { useAdPolicyEffective, type AdPolicyEffectiveRow } from '../../hooks/useAdPolicyEffective';
import { useAdPolicyActions, type CountryPolicyFull } from '../../hooks/useAdPolicyActions';

// =============================================================================
// TYPES
// =============================================================================

interface CountryOptimizationPanelProps {
  data: CountryOptRow[];
  loading?: boolean;
  error?: string | null;
  onPolicyApplied?: () => void;
}

type SignalTab = 'ALL' | 'INCREASE' | 'DECREASE' | 'HOLD';
type SortMode = 'ads' | 'signal' | 'risk';

interface PolicyEditorState {
  ads_per_session_cap: number;
  trigger_pages: number;
  enabled: boolean;
}

// =============================================================================
// HELPERS
// =============================================================================

const countryNameCache = new Map<string, string>();

function getCountryName(code: string): string {
  if (countryNameCache.has(code)) return countryNameCache.get(code)!;
  try {
    const dn = new Intl.DisplayNames(['en'], { type: 'region' });
    const name = dn.of(code) || code;
    countryNameCache.set(code, name);
    return name;
  } catch {
    countryNameCache.set(code, code);
    return code;
  }
}

const SIGNAL_PRIORITY: Record<string, number> = { INCREASE: 0, DECREASE: 1, HOLD: 2 };
const CONF_PRIORITY: Record<string, number> = { HIGH: 0, MED: 1, LOW: 2 };
const RISK_PRIORITY: Record<string, number> = { HIGH: 0, MED: 1, LOW: 2, LOW_VOLUME: 3 };

function sortRows(rows: CountryOptRow[], mode: SortMode): CountryOptRow[] {
  return [...rows].sort((a, b) => {
    if (mode === 'risk') {
      // Higher risk first (HIGH=0, MED=1, LOW=2), then by score desc
      const rp = (RISK_PRIORITY[a.frictionRiskLevel ?? 'LOW'] ?? 9) - (RISK_PRIORITY[b.frictionRiskLevel ?? 'LOW'] ?? 9);
      if (rp !== 0) return rp;
      return (b.frictionRiskScore ?? 0) - (a.frictionRiskScore ?? 0);
    }
    if (mode === 'signal') {
      const sp = (SIGNAL_PRIORITY[a.signal ?? 'HOLD'] ?? 9) - (SIGNAL_PRIORITY[b.signal ?? 'HOLD'] ?? 9);
      if (sp !== 0) return sp;
      // Tie-breaker: higher risk first
      const rp = (RISK_PRIORITY[a.frictionRiskLevel ?? 'LOW'] ?? 9) - (RISK_PRIORITY[b.frictionRiskLevel ?? 'LOW'] ?? 9);
      if (rp !== 0) return rp;
    }
    const cp = (CONF_PRIORITY[a.confidence ?? 'LOW'] ?? 9) - (CONF_PRIORITY[b.confidence ?? 'LOW'] ?? 9);
    if (cp !== 0) return cp;
    return (b.ads30d ?? 0) - (a.ads30d ?? 0);
  });
}

function fmtNum(v: number | null, decimals = 1): string {
  if (v === null || v === undefined) return '—';
  return v.toFixed(decimals);
}

// =============================================================================
// STYLES (dark analytics theme — matches existing panels)
// =============================================================================

const s = {
  container: {
    background: 'rgba(255,255,255,0.02)', borderRadius: 12,
    border: '1px solid rgba(255,255,255,0.06)', overflow: 'hidden',
  } as React.CSSProperties,

  header: {
    padding: '14px 20px', display: 'flex', alignItems: 'center',
    justifyContent: 'space-between', cursor: 'pointer', userSelect: 'none' as const,
    transition: 'background 0.15s ease',
  } as React.CSSProperties,
  headerLeft: { display: 'flex', alignItems: 'center', gap: 12 } as React.CSSProperties,
  chevron: { fontSize: 12, color: 'rgba(255,255,255,0.4)', transition: 'transform 0.2s ease', width: 16 } as React.CSSProperties,
  chevronOpen: { transform: 'rotate(90deg)' } as React.CSSProperties,
  title: { fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.85)', margin: 0 } as React.CSSProperties,
  meta: { display: 'flex', alignItems: 'center', gap: 12, fontSize: 11, color: 'rgba(255,255,255,0.4)' } as React.CSSProperties,

  badge: (bg: string, fg: string): React.CSSProperties => ({
    background: bg, color: fg, padding: '2px 8px', borderRadius: 4, fontSize: 10, fontWeight: 500,
  }),

  content: { borderTop: '1px solid rgba(255,255,255,0.06)' } as React.CSSProperties,

  glossary: {
    padding: '10px 20px', fontSize: 11, color: 'rgba(255,255,255,0.35)', lineHeight: 1.6,
    borderBottom: '1px solid rgba(255,255,255,0.04)',
  } as React.CSSProperties,

  toolbar: {
    padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    gap: 12, flexWrap: 'wrap' as const, borderBottom: '1px solid rgba(255,255,255,0.04)',
  } as React.CSSProperties,
  toolLeft: { display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' as const } as React.CSSProperties,

  tab: {
    padding: '6px 14px', borderRadius: 6, fontSize: 11, fontWeight: 500, cursor: 'pointer',
    transition: 'all 0.15s ease', border: '1px solid transparent',
    background: 'rgba(255,255,255,0.04)', color: 'rgba(255,255,255,0.5)',
  } as React.CSSProperties,
  tabActive: { background: 'rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.9)', border: '1px solid rgba(255,255,255,0.1)' } as React.CSSProperties,
  tabIncrease: { background: 'rgba(100,200,150,0.12)', color: 'rgba(100,200,150,0.95)', border: '1px solid rgba(100,200,150,0.2)' } as React.CSSProperties,
  tabDecrease: { background: 'rgba(255,120,100,0.12)', color: 'rgba(255,120,100,0.95)', border: '1px solid rgba(255,120,100,0.2)' } as React.CSSProperties,
  tabCount: { marginLeft: 6, opacity: 0.6, fontSize: 10 } as React.CSSProperties,

  sortBtn: {
    padding: '5px 12px', borderRadius: 6, fontSize: 11, fontWeight: 500, cursor: 'pointer',
    border: '1px solid rgba(255,255,255,0.1)', background: 'rgba(255,255,255,0.04)',
    color: 'rgba(255,255,255,0.6)', transition: 'all 0.15s ease',
  } as React.CSSProperties,

  searchInput: {
    padding: '6px 12px', borderRadius: 6, border: '1px solid rgba(255,255,255,0.08)',
    background: 'rgba(255,255,255,0.03)', color: 'rgba(255,255,255,0.85)', fontSize: 12,
    outline: 'none', width: 180,
  } as React.CSSProperties,

  safetyNote: {
    fontSize: 10, color: 'rgba(255,200,100,0.6)', padding: '8px 20px',
    borderBottom: '1px solid rgba(255,255,255,0.04)', display: 'flex', alignItems: 'center', gap: 6,
  } as React.CSSProperties,

  tableWrap: { overflowX: 'auto' as const } as React.CSSProperties,
  table: { width: '100%', borderCollapse: 'collapse' as const } as React.CSSProperties,

  th: {
    padding: '10px 12px', fontSize: 10, fontWeight: 500, textTransform: 'uppercase' as const,
    letterSpacing: '0.05em', color: 'rgba(255,255,255,0.4)', textAlign: 'left' as const,
    borderBottom: '1px solid rgba(255,255,255,0.06)', whiteSpace: 'nowrap' as const,
  } as React.CSSProperties,
  thR: {
    padding: '10px 12px', fontSize: 10, fontWeight: 500, textTransform: 'uppercase' as const,
    letterSpacing: '0.05em', color: 'rgba(255,255,255,0.4)', textAlign: 'right' as const,
    borderBottom: '1px solid rgba(255,255,255,0.06)', whiteSpace: 'nowrap' as const,
  } as React.CSSProperties,
  thC: {
    padding: '10px 12px', fontSize: 10, fontWeight: 500, textTransform: 'uppercase' as const,
    letterSpacing: '0.05em', color: 'rgba(255,255,255,0.4)', textAlign: 'center' as const,
    borderBottom: '1px solid rgba(255,255,255,0.06)', whiteSpace: 'nowrap' as const,
  } as React.CSSProperties,

  tr: { borderBottom: '1px solid rgba(255,255,255,0.03)', transition: 'background 0.15s ease' } as React.CSSProperties,
  trExpanded: { background: 'rgba(100,180,255,0.03)' } as React.CSSProperties,

  td: { padding: '10px 12px', fontSize: 12, color: 'rgba(255,255,255,0.85)', verticalAlign: 'middle' as const } as React.CSSProperties,
  tdR: { padding: '10px 12px', fontSize: 12, color: 'rgba(255,255,255,0.85)', textAlign: 'right' as const, fontVariantNumeric: 'tabular-nums', verticalAlign: 'middle' as const } as React.CSSProperties,
  tdC: { padding: '10px 12px', fontSize: 12, color: 'rgba(255,255,255,0.85)', textAlign: 'center' as const, verticalAlign: 'middle' as const } as React.CSSProperties,

  countryCell: { display: 'flex', flexDirection: 'column' as const, gap: 2 } as React.CSSProperties,
  countryName: { fontWeight: 500, display: 'flex', alignItems: 'center', gap: 6 } as React.CSSProperties,
  countryCode: { fontSize: 10, color: 'rgba(255,255,255,0.4)' } as React.CSSProperties,

  srcBadge: { fontSize: 8, padding: '1px 4px', borderRadius: 3, fontWeight: 600, textTransform: 'uppercase' as const, letterSpacing: '0.02em' } as React.CSSProperties,
  srcOverride: { background: 'rgba(100,180,255,0.15)', color: 'rgba(100,180,255,0.9)' } as React.CSSProperties,
  srcDefault: { background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.5)' } as React.CSSProperties,

  policyCell: { display: 'flex', flexDirection: 'column' as const, gap: 2, fontSize: 11 } as React.CSSProperties,
  policyRow: { display: 'flex', alignItems: 'center', gap: 4 } as React.CSSProperties,
  policyLabel: { color: 'rgba(255,255,255,0.4)', fontSize: 9, width: 40 } as React.CSSProperties,
  policyValue: { color: 'rgba(255,255,255,0.8)', fontWeight: 500 } as React.CSSProperties,

  enabledBadge: { fontSize: 9, padding: '1px 5px', borderRadius: 3, fontWeight: 500 } as React.CSSProperties,
  enabledOn: { background: 'rgba(100,200,150,0.15)', color: 'rgba(100,200,150,0.9)' } as React.CSSProperties,
  enabledOff: { background: 'rgba(255,120,100,0.15)', color: 'rgba(255,120,100,0.9)' } as React.CSSProperties,

  confHigh: { color: 'rgba(100,200,150,0.9)', fontWeight: 600 } as React.CSSProperties,
  confMed: { color: 'rgba(255,200,100,0.8)' } as React.CSSProperties,
  confLow: { color: 'rgba(255,255,255,0.4)', fontStyle: 'italic' as const } as React.CSSProperties,

  actionCell: { display: 'flex', alignItems: 'center', gap: 6 } as React.CSSProperties,
  editBtn: {
    padding: '4px 8px', borderRadius: 4, fontSize: 10, fontWeight: 500, cursor: 'pointer',
    border: '1px solid rgba(100,180,255,0.3)', background: 'rgba(100,180,255,0.1)', color: 'rgba(100,180,255,0.95)',
    transition: 'all 0.15s ease',
  } as React.CSSProperties,
  applyBtn: {
    padding: '4px 8px', borderRadius: 4, fontSize: 10, fontWeight: 500, cursor: 'pointer',
    border: '1px solid rgba(100,200,150,0.3)', background: 'rgba(100,200,150,0.1)', color: 'rgba(100,200,150,0.95)',
    transition: 'all 0.15s ease',
  } as React.CSSProperties,
  btnDisabled: { opacity: 0.4, cursor: 'not-allowed' } as React.CSSProperties,

  editorRow: { background: 'rgba(100,180,255,0.05)', borderBottom: '1px solid rgba(100,180,255,0.1)' } as React.CSSProperties,
  editorCell: { padding: '12px 16px' } as React.CSSProperties,
  editorContent: { display: 'flex', alignItems: 'center', gap: 20, flexWrap: 'wrap' as const } as React.CSSProperties,
  editorField: { display: 'flex', alignItems: 'center', gap: 8 } as React.CSSProperties,
  editorLabel: { fontSize: 11, color: 'rgba(255,255,255,0.6)', whiteSpace: 'nowrap' as const } as React.CSSProperties,
  editorInput: {
    padding: '4px 8px', borderRadius: 4, border: '1px solid rgba(255,255,255,0.15)',
    background: 'rgba(255,255,255,0.05)', color: 'rgba(255,255,255,0.9)', fontSize: 12, width: 60, outline: 'none',
  } as React.CSSProperties,
  editorToggle: { display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' } as React.CSSProperties,
  toggleSwitch: { width: 32, height: 18, borderRadius: 9, position: 'relative' as const, cursor: 'pointer', transition: 'background 0.2s ease' } as React.CSSProperties,
  toggleOn: { background: 'rgba(100,200,150,0.5)' } as React.CSSProperties,
  toggleOff: { background: 'rgba(255,255,255,0.15)' } as React.CSSProperties,
  toggleKnob: { width: 14, height: 14, borderRadius: 7, background: 'white', position: 'absolute' as const, top: 2, transition: 'left 0.2s ease' } as React.CSSProperties,
  editorActions: { display: 'flex', alignItems: 'center', gap: 8, marginLeft: 'auto' } as React.CSSProperties,
  saveBtn: { padding: '5px 12px', borderRadius: 4, fontSize: 11, fontWeight: 500, cursor: 'pointer', border: 'none', background: 'rgba(100,200,150,0.8)', color: 'white', transition: 'all 0.15s ease' } as React.CSSProperties,
  resetBtn: { padding: '5px 12px', borderRadius: 4, fontSize: 11, fontWeight: 500, cursor: 'pointer', border: '1px solid rgba(255,200,100,0.3)', background: 'rgba(255,200,100,0.1)', color: 'rgba(255,200,100,0.9)', transition: 'all 0.15s ease' } as React.CSSProperties,
  cancelBtn: { padding: '5px 12px', borderRadius: 4, fontSize: 11, fontWeight: 500, cursor: 'pointer', border: '1px solid rgba(255,255,255,0.15)', background: 'transparent', color: 'rgba(255,255,255,0.6)', transition: 'all 0.15s ease' } as React.CSSProperties,

  empty: { padding: '32px 20px', textAlign: 'center' as const, color: 'rgba(255,255,255,0.4)', fontSize: 12 } as React.CSSProperties,
  error: { padding: '16px 20px', background: 'rgba(255,100,100,0.1)', color: 'rgba(255,150,150,0.9)', fontSize: 12 } as React.CSSProperties,
  fbInline: { fontSize: 10, marginLeft: 8 } as React.CSSProperties,
  fbOk: { color: 'rgba(100,200,150,0.9)' } as React.CSSProperties,
  fbErr: { color: 'rgba(255,120,100,0.9)' } as React.CSSProperties,
};

// =============================================================================
// IMPACT SIMULATION (v1 — frontend-only, hardcoded eCPM + fill rate)
// =============================================================================

const DEFAULT_ECPM_NOK = 35;
const DEFAULT_FILL_RATE = 0.85;

interface SimResult {
  adsPerSession: number;
  revenuePerSession: number;
  revenuePer1k: number;
}

function simulateRevenue(cap: number, triggerPages: number, depth: number): SimResult {
  const adsPerSession = Math.min(cap, triggerPages > 0 ? depth / triggerPages : 0);
  const revenuePerSession = (adsPerSession * DEFAULT_FILL_RATE / 1000) * DEFAULT_ECPM_NOK;
  return { adsPerSession, revenuePerSession, revenuePer1k: revenuePerSession * 1000 };
}

function estimateSessions30d(totalAds30d: number, adsPerSession: number): number | null {
  if (!totalAds30d || totalAds30d <= 0 || !adsPerSession || adsPerSession <= 0) return null;
  return Math.round(totalAds30d / adsPerSession);
}

function fmtNok(v: number): string {
  if (Math.abs(v) >= 100) return v.toFixed(0);
  if (Math.abs(v) >= 1) return v.toFixed(1);
  return v.toFixed(2);
}

function fmtDelta(v: number): string {
  const prefix = v >= 0 ? '+' : '';
  return prefix + fmtNok(v);
}

function riskNote(level: string | null): { text: string; color: string } {
  if (level === 'HIGH') return { text: 'High friction risk', color: 'rgba(255,130,130,0.9)' };
  if (level === 'MED') return { text: 'Moderate risk', color: 'rgba(255,200,100,0.85)' };
  return { text: 'Low risk', color: 'rgba(255,255,255,0.4)' };
}

const simStyles = {
  row: {
    background: 'rgba(100,200,150,0.03)', borderBottom: '1px solid rgba(100,200,150,0.08)',
  } as React.CSSProperties,
  cell: { padding: '10px 16px' } as React.CSSProperties,
  grid: {
    display: 'grid', gridTemplateColumns: '1fr 1fr auto', gap: 20, alignItems: 'start',
    fontSize: 11, color: 'rgba(255,255,255,0.7)',
  } as React.CSSProperties,
  col: { display: 'flex', flexDirection: 'column' as const, gap: 3 } as React.CSSProperties,
  colLabel: {
    fontSize: 9, fontWeight: 600, letterSpacing: '0.06em',
    textTransform: 'uppercase' as const, color: 'rgba(255,255,255,0.4)', marginBottom: 2,
  } as React.CSSProperties,
  val: { fontSize: 13, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: 'rgba(255,255,255,0.9)' } as React.CSSProperties,
  valMuted: { fontSize: 12, color: 'rgba(255,255,255,0.6)', fontVariantNumeric: 'tabular-nums' } as React.CSSProperties,
  delta: (positive: boolean): React.CSSProperties => ({
    fontSize: 12, fontWeight: 600,
    color: positive ? 'rgba(100,200,150,0.9)' : 'rgba(255,120,100,0.9)',
  }),
  metricRow: {
    display: 'grid', gridTemplateColumns: '110px 1fr 1fr auto', gap: 8, alignItems: 'baseline',
    padding: '3px 0', borderBottom: '1px solid rgba(255,255,255,0.03)',
  } as React.CSSProperties,
  metricLabel: { fontSize: 10, color: 'rgba(255,255,255,0.4)', whiteSpace: 'nowrap' as const } as React.CSSProperties,
  metricVal: { fontSize: 12, fontVariantNumeric: 'tabular-nums', color: 'rgba(255,255,255,0.7)' } as React.CSSProperties,
  metricValBold: { fontSize: 12, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: 'rgba(255,255,255,0.9)' } as React.CSSProperties,
  riskBox: { display: 'flex', alignItems: 'center', gap: 6, fontSize: 11 } as React.CSSProperties,
  simBtn: {
    padding: '3px 7px', borderRadius: 4, fontSize: 9, fontWeight: 500, cursor: 'pointer',
    border: '1px solid rgba(100,200,150,0.25)', background: 'rgba(100,200,150,0.08)',
    color: 'rgba(100,200,150,0.85)', transition: 'all 0.15s ease', marginLeft: 4,
  } as React.CSSProperties,
};

const summaryStyles = {
  card: {
    padding: '14px 20px', borderBottom: '1px solid rgba(255,255,255,0.06)',
    background: 'rgba(255,255,255,0.015)',
  } as React.CSSProperties,
  titleRow: {
    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    gap: 12, marginBottom: 8, flexWrap: 'wrap' as const,
  } as React.CSSProperties,
  title: {
    fontSize: 11, fontWeight: 600, letterSpacing: '0.06em',
    textTransform: 'uppercase' as const, color: 'rgba(255,255,255,0.5)',
  } as React.CSSProperties,
  paragraph: {
    margin: 0, fontSize: 12, color: 'rgba(255,255,255,0.7)', lineHeight: 1.55,
  } as React.CSSProperties,
  bullets: {
    margin: '8px 0 0', paddingLeft: 18, listStyle: 'disc',
  } as React.CSSProperties,
  bullet: {
    fontSize: 11, color: 'rgba(255,255,255,0.6)', lineHeight: 1.6, marginBottom: 2,
  } as React.CSSProperties,
  skeleton: {
    fontSize: 12, color: 'rgba(255,255,255,0.25)',
  } as React.CSSProperties,
};

function signalBadgeStyle(sig: string | null): React.CSSProperties {
  if (sig === 'INCREASE') return s.badge('rgba(100,200,150,0.15)', 'rgba(100,200,150,0.95)');
  if (sig === 'DECREASE') return s.badge('rgba(255,120,100,0.15)', 'rgba(255,120,100,0.95)');
  return s.badge('rgba(255,255,255,0.06)', 'rgba(255,255,255,0.55)');
}

function riskBadgeStyle(level: string | null): React.CSSProperties {
  if (level === 'HIGH') return s.badge('rgba(255,100,100,0.18)', 'rgba(255,130,130,0.95)');
  if (level === 'MED') return s.badge('rgba(255,200,100,0.15)', 'rgba(255,200,100,0.9)');
  if (level === 'LOW_VOLUME') return s.badge('rgba(255,255,255,0.05)', 'rgba(255,255,255,0.35)');
  return s.badge('rgba(255,255,255,0.06)', 'rgba(255,255,255,0.5)');
}

function confStyle(c: string | null): React.CSSProperties {
  if (c === 'HIGH') return s.confHigh;
  if (c === 'MED') return s.confMed;
  return s.confLow;
}

// =============================================================================
// COMPONENT
// =============================================================================

export function CountryOptimizationPanel({
  data,
  loading = false,
  error = null,
  onPolicyApplied,
}: CountryOptimizationPanelProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<SignalTab>('ALL');
  const [sortMode, setSortMode] = useState<SortMode>('ads');
  const [search, setSearch] = useState('');
  const [expandedCountry, setExpandedCountry] = useState<string | null>(null);
  const [simCountry, setSimCountry] = useState<string | null>(null);
  const [editorState, setEditorState] = useState<PolicyEditorState | null>(null);
  const [feedback, setFeedback] = useState<Record<string, 'success' | 'error'>>({});

  // Action summary (single-row aggregate)
  const { data: summary, loading: summaryLoading } = useCountryOptimizationActionSummary();

  // Signal counts
  const counts = useMemo(() => {
    const c = { INCREASE: 0, DECREASE: 0, HOLD: 0 };
    for (const r of data) {
      const sig = r.signal ?? 'HOLD';
      if (sig in c) c[sig as keyof typeof c]++;
    }
    return c;
  }, [data]);

  // Filter + sort
  const rows = useMemo(() => {
    let filtered = data;
    if (activeTab !== 'ALL') {
      filtered = filtered.filter(r => (r.signal ?? 'HOLD') === activeTab);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = filtered.filter(r =>
        r.countryCode.toLowerCase().includes(q) ||
        getCountryName(r.countryCode).toLowerCase().includes(q)
      );
    }
    return sortRows(filtered, sortMode);
  }, [data, activeTab, search, sortMode]);

  // Policy fetch for visible rows
  const visibleCodes = useMemo(() => rows.map(r => r.countryCode), [rows]);

  const {
    data: policyData,
    loading: policyLoading,
    refetch: refetchPolicy,
  } = useAdPolicyEffective(visibleCodes.length > 0 ? visibleCodes : undefined);

  const {
    upsertCountryPolicyFull,
    deleteCountryPolicy,
    loading: actionLoading,
    error: actionError,
    clearError: clearActionError,
  } = useAdPolicyActions();

  const policyByCountry = useMemo(() => {
    const m = new Map<string, AdPolicyEffectiveRow>();
    policyData.forEach(p => m.set(p.country_code, p));
    return m;
  }, [policyData]);

  // Clear feedback after 3s
  useEffect(() => {
    if (Object.keys(feedback).length === 0) return;
    const t = setTimeout(() => setFeedback({}), 3000);
    return () => clearTimeout(t);
  }, [feedback]);

  // Editor handlers
  const openEditor = useCallback((cc: string) => {
    const p = policyByCountry.get(cc);
    const row = data.find(r => r.countryCode === cc);
    setExpandedCountry(cc);
    setEditorState({
      ads_per_session_cap: p?.ads_per_session_cap ?? row?.currentCap ?? 1,
      trigger_pages: p?.trigger_pages ?? row?.currentTrigger ?? 6,
      enabled: p?.enabled ?? row?.currentEnabled ?? true,
    });
    clearActionError();
  }, [policyByCountry, data, clearActionError]);

  const closeEditor = useCallback(() => {
    setExpandedCountry(null);
    setEditorState(null);
  }, []);

  const handleSave = useCallback(async () => {
    if (!expandedCountry || !editorState) return;
    const pol: CountryPolicyFull = {
      ads_per_session_cap: editorState.ads_per_session_cap,
      trigger_pages: editorState.trigger_pages,
      enabled: editorState.enabled,
    };
    const ok = await upsertCountryPolicyFull(expandedCountry, pol);
    setFeedback(prev => ({ ...prev, [expandedCountry]: ok ? 'success' : 'error' }));
    if (ok) { closeEditor(); refetchPolicy(); onPolicyApplied?.(); }
  }, [expandedCountry, editorState, upsertCountryPolicyFull, closeEditor, refetchPolicy, onPolicyApplied]);

  const handleReset = useCallback(async () => {
    if (!expandedCountry) return;
    const ok = await deleteCountryPolicy(expandedCountry);
    setFeedback(prev => ({ ...prev, [expandedCountry]: ok ? 'success' : 'error' }));
    if (ok) { closeEditor(); refetchPolicy(); onPolicyApplied?.(); }
  }, [expandedCountry, deleteCountryPolicy, closeEditor, refetchPolicy, onPolicyApplied]);

  const handleQuickApply = useCallback(async (cc: string, recCap: number | null) => {
    if (recCap === null) return;
    const cur = policyByCountry.get(cc);
    const row = data.find(r => r.countryCode === cc);
    const pol: CountryPolicyFull = {
      ads_per_session_cap: recCap,
      trigger_pages: cur?.trigger_pages ?? row?.currentTrigger ?? 6,
      enabled: cur?.enabled ?? row?.currentEnabled ?? true,
    };
    const ok = await upsertCountryPolicyFull(cc, pol);
    setFeedback(prev => ({ ...prev, [cc]: ok ? 'success' : 'error' }));
    if (ok) { refetchPolicy(); onPolicyApplied?.(); }
  }, [policyByCountry, data, upsertCountryPolicyFull, refetchPolicy, onPolicyApplied]);

  // Tab style helper
  function tabStyle(t: SignalTab): React.CSSProperties {
    if (activeTab !== t) return s.tab;
    if (t === 'INCREASE') return { ...s.tab, ...s.tabIncrease };
    if (t === 'DECREASE') return { ...s.tab, ...s.tabDecrease };
    return { ...s.tab, ...s.tabActive };
  }

  // Loading skeleton
  if (loading) {
    return (
      <div style={s.container}>
        <div style={s.header}>
          <div style={s.headerLeft}>
            <span style={s.chevron}>›</span>
            <h3 style={s.title}>Country Monetization Optimization</h3>
          </div>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)' }}>Loading…</span>
        </div>
      </div>
    );
  }

  return (
    <div style={s.container}>
      {/* Header */}
      <div style={s.header} onClick={() => setIsOpen(!isOpen)}>
        <div style={s.headerLeft}>
          <span style={{ ...s.chevron, ...(isOpen ? s.chevronOpen : {}) }}>›</span>
          <h3 style={s.title}>Country Monetization Optimization</h3>
        </div>
        <div style={s.meta}>
          <span>{data.length} countries</span>
          {counts.INCREASE > 0 && <span style={s.badge('rgba(100,200,150,0.12)', 'rgba(100,200,150,0.9)')}>↑ {counts.INCREASE}</span>}
          {counts.DECREASE > 0 && <span style={s.badge('rgba(255,120,100,0.12)', 'rgba(255,120,100,0.9)')}>↓ {counts.DECREASE}</span>}
        </div>
      </div>

      {isOpen && (
        <div style={s.content}>
          {/* Error */}
          {(error || actionError) && (
            <div style={s.error}>{error || actionError}</div>
          )}

          {/* Action Summary */}
          <div style={summaryStyles.card}>
            <div style={summaryStyles.titleRow}>
              <span style={summaryStyles.title}>Action Summary</span>
              {summary && (
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                  {summary.incCount > 0 && <span style={s.badge('rgba(100,200,150,0.12)', 'rgba(100,200,150,0.9)')}>↑ {summary.incCount}</span>}
                  {summary.decCount > 0 && <span style={s.badge('rgba(255,120,100,0.12)', 'rgba(255,120,100,0.9)')}>↓ {summary.decCount}</span>}
                  {summary.highRiskCount > 0 && <span style={s.badge('rgba(255,100,100,0.15)', 'rgba(255,130,130,0.9)')}>Risk: {summary.highRiskCount} HIGH</span>}
                  {summary.medRiskCount > 0 && <span style={s.badge('rgba(255,200,100,0.12)', 'rgba(255,200,100,0.85)')}>Risk: {summary.medRiskCount} MED</span>}
                </div>
              )}
            </div>
            {summaryLoading && (
              <div style={summaryStyles.skeleton}>Loading summary…</div>
            )}
            {!summaryLoading && !summary && (
              <p style={summaryStyles.paragraph}>Not enough data yet.</p>
            )}
            {!summaryLoading && summary && (
              <>
                <p style={summaryStyles.paragraph}>{summary.topActions}</p>
                {summary.actionBullets.length > 0 && (
                  <ul style={summaryStyles.bullets}>
                    {summary.actionBullets.map((b, i) => (
                      <li key={i} style={summaryStyles.bullet}>{b}</li>
                    ))}
                  </ul>
                )}
              </>
            )}
          </div>

          {/* Glossary */}
          <div style={s.glossary}>
            <strong>Continue %</strong> — sessions that fetched another page ≤ 60 s after ad &nbsp;|&nbsp;
            <strong>Drop %</strong> — sessions that did not continue (100 − continue) &nbsp;|&nbsp;
            <strong>Depth</strong> — median page fetches within 5 min after ad &nbsp;|&nbsp;
            <strong>Confidence</strong> — HIGH ≥ 1 000 ads, MED ≥ 100, LOW &lt; 100 &nbsp;|&nbsp;
            <strong>Signal</strong> — INCREASE / DECREASE / HOLD &nbsp;|&nbsp;
            <strong>Risk</strong> — friction risk index (drop + depth + confidence). HIGH = increasing ads likely hurts engagement.
          </div>

          {/* Toolbar */}
          <div style={s.toolbar}>
            <div style={s.toolLeft}>
              <button style={tabStyle('ALL')} onClick={() => setActiveTab('ALL')}>
                All<span style={s.tabCount}>({data.length})</span>
              </button>
              <button style={tabStyle('INCREASE')} onClick={() => setActiveTab('INCREASE')}>
                Increase<span style={s.tabCount}>({counts.INCREASE})</span>
              </button>
              <button style={tabStyle('DECREASE')} onClick={() => setActiveTab('DECREASE')}>
                Decrease<span style={s.tabCount}>({counts.DECREASE})</span>
              </button>
              <button style={tabStyle('HOLD')} onClick={() => setActiveTab('HOLD')}>
                Hold<span style={s.tabCount}>({counts.HOLD})</span>
              </button>
              <button style={s.sortBtn} onClick={() => setSortMode(m => m === 'ads' ? 'signal' : m === 'signal' ? 'risk' : 'ads')}>
                Sort: {sortMode === 'ads' ? 'Ads ↓' : sortMode === 'signal' ? 'Signal' : 'Risk ↓'}
              </button>
            </div>
            <input style={s.searchInput} placeholder="Filter country…" value={search} onChange={e => setSearch(e.target.value)} />
          </div>

          {/* Safety */}
          <div style={s.safetyNote}>
            <span>⚡</span>
            <span>Policy changes affect runtime ad behavior immediately.</span>
          </div>

          {/* Empty */}
          {rows.length === 0 && !error && (
            <div style={s.empty}>
              {data.length === 0
                ? 'No optimization data yet. Ad events will populate this view.'
                : 'No countries match your filter.'}
            </div>
          )}

          {/* Table */}
          {rows.length > 0 && (
            <div style={s.tableWrap}>
              <table style={s.table}>
                <thead>
                  <tr>
                    <th style={s.th}>Country</th>
                    <th style={s.thR}>Ads (30d)</th>
                    <th style={s.thR}>Continue %</th>
                    <th style={s.thR}>Drop %</th>
                    <th style={s.thR}>Depth</th>
                    <th style={s.th}>Confidence</th>
                    <th style={s.th}>Signal</th>
                    <th style={s.th}>Risk</th>
                    <th style={s.th}>Current Policy</th>
                    <th style={s.thC}>Rec. Cap</th>
                    <th style={s.thC}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map(row => {
                    const policy = policyByCountry.get(row.countryCode);
                    const isExpanded = expandedCountry === row.countryCode;
                    const isOverride = (policy?.source ?? row.policySource) === 'override';
                    const effectiveCap = policy?.ads_per_session_cap ?? row.currentCap ?? 1;
                    const alreadyApplied = row.recommendedCap !== null && effectiveCap === row.recommendedCap;
                    const rowFb = feedback[row.countryCode];
                    const dimRow = row.confidence === 'LOW';

                    return (
                      <React.Fragment key={row.countryCode}>
                        <tr style={{ ...s.tr, ...(dimRow ? { opacity: 0.55 } : {}), ...(isExpanded ? s.trExpanded : {}) }}>
                          {/* Country */}
                          <td style={s.td}>
                            <div style={s.countryCell}>
                              <span style={s.countryName}>
                                {getCountryName(row.countryCode)}
                                <span style={{ ...s.srcBadge, ...(isOverride ? s.srcOverride : s.srcDefault) }}>
                                  {(policy?.source ?? row.policySource) || 'default'}
                                </span>
                              </span>
                              <span style={s.countryCode}>{row.countryCode}</span>
                            </div>
                          </td>
                          {/* Ads */}
                          <td style={s.tdR}>{(row.ads30d ?? 0).toLocaleString()}</td>
                          {/* Continue */}
                          <td style={s.tdR}>{fmtNum(row.continueRate)}%</td>
                          {/* Drop */}
                          <td style={s.tdR}>{fmtNum(row.dropRate)}%</td>
                          {/* Depth */}
                          <td style={s.tdR}>{fmtNum(row.depth)}</td>
                          {/* Confidence */}
                          <td style={s.td}><span style={confStyle(row.confidence)}>{row.confidence ?? '—'}</span></td>
                          {/* Signal */}
                          <td style={s.td}><span style={signalBadgeStyle(row.signal)}>{row.signal ?? '—'}</span></td>
                          {/* Risk */}
                          <td style={s.td} title={row.frictionRiskReason ?? ''}>
                            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                              <span style={riskBadgeStyle(row.frictionRiskLevel)}>{row.frictionRiskLevel ?? '—'}</span>
                              {row.frictionRiskReason && row.frictionRiskReason !== 'Healthy engagement' && (
                                <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.35)', maxWidth: 120, lineHeight: 1.2 }}>
                                  {row.frictionRiskReason}
                                </span>
                              )}
                            </div>
                          </td>
                          {/* Current Policy */}
                          <td style={s.td}>
                            <div style={s.policyCell}>
                              <div style={s.policyRow}>
                                <span style={s.policyLabel}>Cap:</span>
                                <span style={s.policyValue}>{policyLoading ? '…' : effectiveCap}</span>
                              </div>
                              <div style={s.policyRow}>
                                <span style={s.policyLabel}>Trigger:</span>
                                <span style={s.policyValue}>{policyLoading ? '…' : (policy?.trigger_pages ?? row.currentTrigger ?? 6)}</span>
                              </div>
                              <div style={s.policyRow}>
                                <span style={s.policyLabel}>Enabled:</span>
                                <span style={{ ...s.enabledBadge, ...((policy?.enabled ?? row.currentEnabled ?? true) ? s.enabledOn : s.enabledOff) }}>
                                  {(policy?.enabled ?? row.currentEnabled ?? true) ? 'On' : 'Off'}
                                </span>
                              </div>
                            </div>
                          </td>
                          {/* Rec Cap */}
                          <td style={s.tdC}>
                            <span style={{ fontWeight: 600, color: alreadyApplied ? 'rgba(100,200,150,0.9)' : 'rgba(255,255,255,0.9)' }}>
                              {row.recommendedCap ?? '—'}
                            </span>
                          </td>
                          {/* Actions */}
                          <td style={s.tdC}>
                            <div style={s.actionCell}>
                              <button style={simStyles.simBtn} onClick={() => setSimCountry(simCountry === row.countryCode ? null : row.countryCode)}>
                                {simCountry === row.countryCode ? 'Hide' : 'Sim'}
                              </button>
                              <button style={s.editBtn} onClick={() => isExpanded ? closeEditor() : openEditor(row.countryCode)}>
                                {isExpanded ? 'Close' : 'Edit'}
                              </button>
                              {row.recommendedCap !== null && (
                                <button
                                  style={{ ...s.applyBtn, ...(alreadyApplied || actionLoading ? s.btnDisabled : {}) }}
                                  disabled={alreadyApplied || actionLoading}
                                  onClick={() => handleQuickApply(row.countryCode, row.recommendedCap)}
                                  title={alreadyApplied ? 'Already applied' : `Quick apply cap=${row.recommendedCap}`}
                                >
                                  {alreadyApplied ? '✓' : 'Apply'}
                                </button>
                              )}
                              {rowFb && (
                                <span style={{ ...s.fbInline, ...(rowFb === 'success' ? s.fbOk : s.fbErr) }}>
                                  {rowFb === 'success' ? 'Saved!' : 'Failed'}
                                </span>
                              )}
                            </div>
                          </td>
                        </tr>

                        {/* Impact simulation row */}
                        {simCountry === row.countryCode && (() => {
                          const curCap = effectiveCap;
                          const curTrigger = policy?.trigger_pages ?? row.currentTrigger ?? 6;
                          const depth = row.depth ?? 0;
                          const recCap = row.recommendedCap ?? curCap;

                          const cur = simulateRevenue(curCap, curTrigger, depth);
                          const proj = simulateRevenue(recCap, curTrigger, depth);

                          // Prefer real sessions from DB; fall back to estimate
                          const realSessions = (row.sessions30d !== null && row.sessions30d > 0) ? row.sessions30d : null;
                          const estSessions = estimateSessions30d(row.ads30d ?? 0, cur.adsPerSession);
                          const sessions30d = realSessions ?? estSessions;
                          const sessionsIsReal = realSessions !== null;
                          const hasSessions = sessions30d !== null && sessions30d > 0;
                          const avgPerDay = hasSessions ? sessions30d / 30 : null;

                          const curPerDay = avgPerDay !== null ? cur.revenuePerSession * avgPerDay : null;
                          const projPerDay = avgPerDay !== null ? proj.revenuePerSession * avgPerDay : null;
                          const curPerMonth = sessions30d !== null ? cur.revenuePerSession * sessions30d : null;
                          const projPerMonth = sessions30d !== null ? proj.revenuePerSession * sessions30d : null;

                          const d1k = proj.revenuePer1k - cur.revenuePer1k;
                          const dDay = curPerDay !== null && projPerDay !== null ? projPerDay - curPerDay : null;
                          const dMonth = curPerMonth !== null && projPerMonth !== null ? projPerMonth - curPerMonth : null;

                          const deltaPct = cur.revenuePerSession > 0
                            ? ((proj.revenuePerSession - cur.revenuePerSession) / cur.revenuePerSession) * 100
                            : (proj.revenuePerSession > 0 ? 100 : 0);

                          const risk = riskNote(row.frictionRiskLevel);

                          return (
                            <tr style={simStyles.row}>
                              <td colSpan={11} style={simStyles.cell}>
                                <div style={{ display: 'flex', gap: 24, alignItems: 'start', flexWrap: 'wrap' }}>
                                  {/* Metrics table */}
                                  <div style={{ flex: 1, minWidth: 340 }}>
                                    {/* Header */}
                                    <div style={{ ...simStyles.metricRow, borderBottom: '1px solid rgba(255,255,255,0.06)', paddingBottom: 4, marginBottom: 2 }}>
                                      <span style={{ ...simStyles.metricLabel, fontWeight: 600 }}></span>
                                      <span style={{ ...simStyles.metricLabel, fontWeight: 600 }}>Current (cap {curCap})</span>
                                      <span style={{ ...simStyles.metricLabel, fontWeight: 600 }}>If applied (cap {recCap})</span>
                                      <span style={{ ...simStyles.metricLabel, fontWeight: 600 }}>Delta</span>
                                    </div>
                                    {/* Ads/session */}
                                    <div style={simStyles.metricRow}>
                                      <span style={simStyles.metricLabel}>Ads / session</span>
                                      <span style={simStyles.metricVal}>{cur.adsPerSession.toFixed(2)}</span>
                                      <span style={simStyles.metricValBold}>{proj.adsPerSession.toFixed(2)}</span>
                                      <span style={simStyles.delta(deltaPct >= 0)}>
                                        {deltaPct >= 0 ? '↑' : '↓'} {Math.abs(deltaPct).toFixed(1)}%
                                      </span>
                                    </div>
                                    {/* Per 1k sessions */}
                                    <div style={simStyles.metricRow}>
                                      <span style={simStyles.metricLabel}>NOK / 1k sessions</span>
                                      <span style={simStyles.metricVal}>{fmtNok(cur.revenuePer1k)}</span>
                                      <span style={simStyles.metricValBold}>{fmtNok(proj.revenuePer1k)}</span>
                                      <span style={simStyles.delta(d1k >= 0)}>{fmtDelta(d1k)} NOK</span>
                                    </div>
                                    {/* Per day */}
                                    {hasSessions && curPerDay !== null && projPerDay !== null && dDay !== null && (
                                      <div style={simStyles.metricRow}>
                                        <span style={simStyles.metricLabel}>NOK / day</span>
                                        <span style={simStyles.metricVal}>{fmtNok(curPerDay)}</span>
                                        <span style={simStyles.metricValBold}>{fmtNok(projPerDay)}</span>
                                        <span style={simStyles.delta(dDay >= 0)}>{fmtDelta(dDay)} NOK</span>
                                      </div>
                                    )}
                                    {/* Per month */}
                                    {hasSessions && curPerMonth !== null && projPerMonth !== null && dMonth !== null && (
                                      <div style={simStyles.metricRow}>
                                        <span style={simStyles.metricLabel}>NOK / month</span>
                                        <span style={simStyles.metricVal}>{fmtNok(curPerMonth)}</span>
                                        <span style={simStyles.metricValBold}>{fmtNok(projPerMonth)}</span>
                                        <span style={simStyles.delta(dMonth >= 0)}>{fmtDelta(dMonth)} NOK</span>
                                      </div>
                                    )}
                                    {!hasSessions && (
                                      <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.25)', padding: '4px 0' }}>
                                        Day/month estimates need more ad data.
                                      </div>
                                    )}
                                  </div>
                                  {/* Risk + assumptions */}
                                  <div style={{ ...simStyles.col, justifyContent: 'center', minWidth: 120 }}>
                                    <div style={simStyles.riskBox}>
                                      <span style={{ width: 6, height: 6, borderRadius: 3, background: risk.color, flexShrink: 0 }} />
                                      <span style={{ color: risk.color }}>{risk.text}</span>
                                    </div>
                                    {hasSessions && (
                                      <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.25)', marginTop: 4 }}>
                                        {sessionsIsReal ? '' : '~'}{sessions30d?.toLocaleString()} sessions/30d
                                        {sessionsIsReal ? '' : ' (est.)'}
                                      </span>
                                    )}
                                    <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.2)', marginTop: 2 }}>
                                      eCPM {DEFAULT_ECPM_NOK} NOK · fill {(DEFAULT_FILL_RATE * 100).toFixed(0)}%
                                    </span>
                                  </div>
                                </div>
                              </td>
                            </tr>
                          );
                        })()}

                        {/* Editor row */}
                        {isExpanded && editorState && (
                          <tr style={s.editorRow}>
                            <td colSpan={11} style={s.editorCell}>
                              <div style={s.editorContent}>
                                <div style={s.editorField}>
                                  <span style={s.editorLabel}>Ads per Session Cap:</span>
                                  <input type="number" min={0} max={10}
                                    value={editorState.ads_per_session_cap}
                                    onChange={e => setEditorState(p => p ? { ...p, ads_per_session_cap: Math.max(0, Math.min(10, parseInt(e.target.value) || 0)) } : null)}
                                    style={s.editorInput} />
                                </div>
                                <div style={s.editorField}>
                                  <span style={s.editorLabel}>Trigger Pages:</span>
                                  <input type="number" min={1} max={50}
                                    value={editorState.trigger_pages}
                                    onChange={e => setEditorState(p => p ? { ...p, trigger_pages: Math.max(1, Math.min(50, parseInt(e.target.value) || 1)) } : null)}
                                    style={s.editorInput} />
                                </div>
                                <div style={s.editorField}>
                                  <span style={s.editorLabel}>Enabled:</span>
                                  <div style={s.editorToggle} onClick={() => setEditorState(p => p ? { ...p, enabled: !p.enabled } : null)}>
                                    <div style={{ ...s.toggleSwitch, ...(editorState.enabled ? s.toggleOn : s.toggleOff) }}>
                                      <div style={{ ...s.toggleKnob, left: editorState.enabled ? 16 : 2 }} />
                                    </div>
                                    <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.7)' }}>{editorState.enabled ? 'On' : 'Off'}</span>
                                  </div>
                                </div>
                                <div style={s.editorActions}>
                                  <button style={{ ...s.saveBtn, ...(actionLoading ? s.btnDisabled : {}) }} disabled={actionLoading} onClick={handleSave}>
                                    {actionLoading ? 'Saving…' : 'Save'}
                                  </button>
                                  {isOverride && (
                                    <button style={{ ...s.resetBtn, ...(actionLoading ? s.btnDisabled : {}) }} disabled={actionLoading} onClick={handleReset}>
                                      Reset to Default
                                    </button>
                                  )}
                                  <button style={s.cancelBtn} onClick={closeEditor}>Cancel</button>
                                </div>
                              </div>
                            </td>
                          </tr>
                        )}
                      </React.Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
