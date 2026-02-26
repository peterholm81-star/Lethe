import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import mapboxgl from 'mapbox-gl';
import { useModerationActions, logModerationAction } from '../hooks/useModerationActions';
import type { PendingReportRow } from '../hooks/useReportsPending';
import { useReportsInbox, setReportHandled, setConfessionHidden, type ReportRow } from '../hooks/useReportsInbox';
import { useReportsSla } from '../hooks/useReportsSla';
import { useReportsOutcomes } from '../hooks/useReportsOutcomes';
import { useReportsSpikeExplain } from '../hooks/useReportsSpikeExplain';
import { useReportsPending } from '../hooks/useReportsPending';
import { useReportsEscalated, type EscalatedReportRow } from '../hooks/useReportsEscalated';
import { useAuditLog, type ActionTypeFilter } from '../hooks/useAuditLog';
import { useReportsHotspots } from '../hooks/useReportsHotspots';
import { useReportsGeoCoverage } from '../hooks/useReportsGeoCoverage';
import { useCountryOptions, useCityOptions } from '../hooks/useInsightsFilterOptions';

// =============================================================================
// MAPBOX CONFIG
// =============================================================================

const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN as string | undefined;

// =============================================================================
// TYPES
// =============================================================================

interface OverviewData {
  reportsTotal: number;
  reportsPer1kReads: number | null;
  hiddenTotal: number;
  severityScore: number;
  spikeDetected: boolean;
  actionsTotal: number;
}

interface BreakdownItem {
  key: string;
  count: number;
  pct: number;
}

interface BreakdownData {
  topReasons: BreakdownItem[];
  topLocations: BreakdownItem[];
}

interface TrendPoint {
  ts: string;
  label: string;
  count: number;
}

interface ReportMapMarker {
  city_code: string | null;
  region: string | null;
  lat: number;
  lng: number;
  reports: number;
  hidden: number;
  top_reason: string | null;
}

// =============================================================================
// MOCK DATA (placeholder until RPCs are connected)
// =============================================================================

const MOCK_SIGNALS = {
  reportsTotal: 847,
  reportsUnhandled: 23,
  readsPer1k: 4.2,
  hiddenCount: 156,
  severityScore: 34,
  isSpike: true,
  actionsTotal: 89,
  reportsDelta: 12,
};

const MOCK_TREND = [
  { label: 'Mon', reports: 120, hidden: 15 },
  { label: 'Tue', reports: 145, hidden: 22 },
  { label: 'Wed', reports: 98, hidden: 12 },
  { label: 'Thu', reports: 167, hidden: 28 },
  { label: 'Fri', reports: 134, hidden: 19 },
  { label: 'Sat', reports: 89, hidden: 8 },
  { label: 'Sun', reports: 94, hidden: 11 },
];

// MOCK data removed - using real data from hooks

// =============================================================================
// FILTER OPTIONS
// =============================================================================

const TIME_RANGE_OPTIONS = [
  { value: '60m', label: 'Last 60 min' },
  { value: '24h', label: 'Last 24 hours' },
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
];

const REGION_OPTIONS = [
  { value: '', label: 'All Regions' },
  { value: 'Europe', label: 'Europe' },
  { value: 'North America', label: 'North America' },
  { value: 'Asia', label: 'Asia' },
  { value: 'South America', label: 'South America' },
  { value: 'Oceania', label: 'Oceania' },
  { value: 'Africa', label: 'Africa' },
  { value: 'Middle East', label: 'Middle East' },
  { value: 'Unknown', label: 'Unknown' },
];

// Region -> Map Viewport (hardcoded for v1, no geocoding)
const REGION_VIEWPORTS: Record<string, { center: [number, number]; zoom: number }> = {
  'europe': { center: [10, 52], zoom: 3.2 },
  'north_america': { center: [-98, 39], zoom: 3.0 },
  'asia': { center: [95, 35], zoom: 2.6 },
  'south_america': { center: [-60, -15], zoom: 2.8 },
  'africa': { center: [20, 5], zoom: 2.7 },
  'oceania': { center: [135, -25], zoom: 3.0 },
  'world': { center: [0, 20], zoom: 1.4 },
};

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  // Page container
  page: {
    padding: '24px 32px',
    maxWidth: '1600px',
    margin: '0 auto',
  } as React.CSSProperties,

  // Header
  header: {
    marginBottom: '24px',
  } as React.CSSProperties,

  title: {
    margin: 0,
    fontSize: '28px',
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.95)',
    letterSpacing: '-0.02em',
  } as React.CSSProperties,

  subtitle: {
    margin: '4px 0 0 0',
    fontSize: '14px',
    color: 'rgba(255, 255, 255, 0.45)',
  } as React.CSSProperties,

  // Filter bar
  filterBar: {
    display: 'flex',
    alignItems: 'center',
    gap: '16px',
    padding: '16px 20px',
    background: 'rgba(255, 255, 255, 0.02)',
    borderRadius: '12px',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    marginBottom: '24px',
    flexWrap: 'wrap' as const,
  } as React.CSSProperties,

  filterGroup: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '4px',
  } as React.CSSProperties,

  filterLabel: {
    fontSize: '10px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  filterSelect: {
    padding: '8px 12px',
    fontSize: '13px',
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '6px',
    color: 'rgba(255, 255, 255, 0.9)',
    cursor: 'pointer',
    minWidth: '140px',
  } as React.CSSProperties,

  filterSpacer: {
    flex: 1,
  } as React.CSSProperties,

  refreshBtn: {
    padding: '10px 20px',
    fontSize: '13px',
    fontWeight: 500,
    background: 'rgba(100, 150, 255, 0.15)',
    border: '1px solid rgba(100, 150, 255, 0.3)',
    borderRadius: '6px',
    color: 'rgba(100, 150, 255, 1)',
    cursor: 'pointer',
  } as React.CSSProperties,

  // Section
  section: {
    marginBottom: '24px',
  } as React.CSSProperties,

  sectionTitle: {
    fontSize: '11px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.35)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.08em',
    marginBottom: '12px',
  } as React.CSSProperties,

  // Signals row (KPI cards)
  signalsRow: {
    display: 'grid',
    gridTemplateColumns: 'repeat(6, 1fr)',
    gap: '16px',
  } as React.CSSProperties,

  kpiCard: {
    padding: '16px',
    background: 'rgba(255, 255, 255, 0.03)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '10px',
  } as React.CSSProperties,

  kpiLabel: {
    fontSize: '11px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
    marginBottom: '8px',
  } as React.CSSProperties,

  kpiValue: {
    fontSize: '28px',
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.95)',
    lineHeight: 1,
    marginBottom: '4px',
  } as React.CSSProperties,

  kpiValueSmall: {
    fontSize: '22px',
  } as React.CSSProperties,

  kpiDelta: {
    fontSize: '11px',
    fontWeight: 500,
  } as React.CSSProperties,

  kpiDeltaUp: {
    color: 'rgba(255, 100, 100, 0.9)',
  } as React.CSSProperties,

  kpiDeltaDown: {
    color: 'rgba(100, 200, 150, 0.9)',
  } as React.CSSProperties,

  kpiSpike: {
    display: 'inline-block',
    padding: '4px 10px',
    fontSize: '11px',
    fontWeight: 700,
    background: 'rgba(255, 80, 80, 0.2)',
    color: 'rgba(255, 100, 100, 1)',
    borderRadius: '4px',
    textTransform: 'uppercase' as const,
  } as React.CSSProperties,

  kpiNoSpike: {
    fontSize: '22px',
    color: 'rgba(255, 255, 255, 0.3)',
  } as React.CSSProperties,

  // Map core section
  mapSection: {
    display: 'grid',
    gridTemplateColumns: '1fr 320px',
    gap: '20px',
  } as React.CSSProperties,

  mapCard: {
    background: 'rgba(255, 255, 255, 0.02)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
    overflow: 'hidden',
    minHeight: '400px',
    display: 'flex',
    flexDirection: 'column' as const,
  } as React.CSSProperties,

  mapPlaceholder: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: `
      linear-gradient(rgba(30, 40, 60, 0.8), rgba(20, 30, 50, 0.9)),
      url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1000 500'%3E%3Crect fill='%23142030'/%3E%3Cpath d='M200 200 Q250 150 300 200 T400 200 T500 180 T600 220 T700 200' stroke='%23334455' fill='none' stroke-width='2'/%3E%3Ccircle cx='250' cy='180' r='4' fill='%23446688'/%3E%3Ccircle cx='450' cy='200' r='3' fill='%23446688'/%3E%3Ccircle cx='650' cy='190' r='5' fill='%23668899'/%3E%3C/svg%3E")
    `,
    backgroundSize: 'cover',
    backgroundPosition: 'center',
    position: 'relative' as const,
  } as React.CSSProperties,

  mapPlaceholderText: {
    textAlign: 'center' as const,
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  mapPlaceholderTitle: {
    fontSize: '18px',
    fontWeight: 600,
    marginBottom: '8px',
    color: 'rgba(255, 255, 255, 0.7)',
  } as React.CSSProperties,

  mapPlaceholderSub: {
    fontSize: '12px',
    opacity: 0.6,
  } as React.CSSProperties,

  // Side panel
  sidePanel: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '16px',
  } as React.CSSProperties,

  panelCard: {
    padding: '16px',
    background: 'rgba(255, 255, 255, 0.03)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '10px',
  } as React.CSSProperties,

  panelTitle: {
    fontSize: '12px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.5)',
    marginBottom: '12px',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  panelList: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '8px',
  } as React.CSSProperties,

  panelRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '8px 0',
    borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
  } as React.CSSProperties,

  panelRowLast: {
    borderBottom: 'none',
  } as React.CSSProperties,

  panelRowName: {
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.8)',
    fontWeight: 500,
  } as React.CSSProperties,

  panelRowStats: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  } as React.CSSProperties,

  panelRowCount: {
    fontSize: '13px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
  } as React.CSSProperties,

  panelRowPct: {
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  // Trend section
  trendCard: {
    padding: '20px',
    background: 'rgba(255, 255, 255, 0.02)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
  } as React.CSSProperties,

  trendChart: {
    display: 'flex',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    height: '120px',
    gap: '8px',
    padding: '0 8px',
  } as React.CSSProperties,

  trendBarGroup: {
    display: 'flex',
    flexDirection: 'column' as const,
    alignItems: 'center',
    gap: '6px',
    flex: 1,
  } as React.CSSProperties,

  trendBar: {
    width: '100%',
    maxWidth: '40px',
    borderRadius: '4px 4px 0 0',
    transition: 'height 0.3s ease',
  } as React.CSSProperties,

  trendBarReports: {
    background: 'rgba(100, 150, 255, 0.6)',
  } as React.CSSProperties,

  trendBarHidden: {
    background: 'rgba(255, 100, 100, 0.5)',
  } as React.CSSProperties,

  trendLabel: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
  } as React.CSSProperties,

  trendLegend: {
    display: 'flex',
    justifyContent: 'center',
    gap: '24px',
    marginTop: '16px',
  } as React.CSSProperties,

  trendLegendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  trendLegendDot: {
    width: '10px',
    height: '10px',
    borderRadius: '2px',
  } as React.CSSProperties,

  // Inbox section
  inboxCard: {
    background: 'rgba(255, 255, 255, 0.02)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
    overflow: 'hidden',
  } as React.CSSProperties,

  inboxHeader: {
    padding: '16px 20px',
    borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  } as React.CSSProperties,

  inboxTitle: {
    fontSize: '14px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.8)',
  } as React.CSSProperties,

  inboxBadge: {
    fontSize: '11px',
    fontWeight: 600,
    padding: '4px 10px',
    borderRadius: '12px',
    background: 'rgba(255, 200, 100, 0.15)',
    color: 'rgba(255, 200, 100, 1)',
  } as React.CSSProperties,

  table: {
    width: '100%',
    borderCollapse: 'collapse' as const,
  } as React.CSSProperties,

  th: {
    padding: '12px 16px',
    textAlign: 'left' as const,
    fontSize: '10px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
    borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
  } as React.CSSProperties,

  td: {
    padding: '14px 16px',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.8)',
    borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
  } as React.CSSProperties,

  reasonBadge: {
    display: 'inline-block',
    padding: '4px 8px',
    fontSize: '10px',
    fontWeight: 600,
    borderRadius: '4px',
    background: 'rgba(255, 255, 255, 0.08)',
    color: 'rgba(255, 255, 255, 0.7)',
    textTransform: 'uppercase' as const,
  } as React.CSSProperties,

  severityDot: {
    display: 'inline-block',
    width: '8px',
    height: '8px',
    borderRadius: '50%',
    marginRight: '6px',
  } as React.CSSProperties,

  statusPending: {
    color: 'rgba(255, 200, 100, 0.9)',
  } as React.CSSProperties,

  actionBtn: {
    padding: '6px 12px',
    fontSize: '11px',
    fontWeight: 500,
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '4px',
    color: 'rgba(255, 255, 255, 0.7)',
    cursor: 'pointer',
    marginRight: '6px',
  } as React.CSSProperties,

  // Actions section
  actionsCard: {
    padding: '16px 20px',
    background: 'rgba(255, 255, 255, 0.02)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '12px',
  } as React.CSSProperties,

  actionsList: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '8px',
  } as React.CSSProperties,

  actionsRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '10px 0',
    borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
  } as React.CSSProperties,

  actionsRowLast: {
    borderBottom: 'none',
  } as React.CSSProperties,

  actionsType: {
    fontSize: '12px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.8)',
  } as React.CSSProperties,

  actionsTarget: {
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.4)',
    marginLeft: '8px',
  } as React.CSSProperties,

  actionsTime: {
    fontSize: '11px',
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,
};

// =============================================================================
// HELPER: Format relative time
// =============================================================================

function formatRelativeTime(isoString: string): string {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMinutes = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMinutes < 1) return 'just now';
  if (diffMinutes < 60) return `${diffMinutes}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
}

// =============================================================================
// HELPER: Format SLA duration (minutes to nice display)
// =============================================================================

function formatSlaDuration(minutes: number | null | undefined): string {
  if (minutes == null || isNaN(minutes)) return '—';
  
  // Under 180 minutes: show as Xm
  if (minutes < 180) {
    return `${Math.round(minutes)}m`;
  }
  
  const hours = minutes / 60;
  
  // Under 48 hours: show as Xh (1 decimal max)
  if (hours < 48) {
    return `${hours.toFixed(1).replace(/\.0$/, '')}h`;
  }
  
  // 48+ hours: show as Xd (1 decimal max)
  const days = hours / 24;
  return `${days.toFixed(1).replace(/\.0$/, '')}d`;
}

// =============================================================================
// HELPER: Format hours open (for pending reports)
// =============================================================================

function formatHoursOpen(hours: number | null | undefined): string {
  if (hours == null || isNaN(hours)) return '—';
  
  // Under 24 hours: show as Xh
  if (hours < 24) {
    return `${hours.toFixed(1).replace(/\.0$/, '')}h`;
  }
  
  // 24+ hours: show as Xd
  const days = hours / 24;
  return `${days.toFixed(1).replace(/\.0$/, '')}d`;
}

// =============================================================================
// HELPER: Build location label from parts
// =============================================================================

function buildLocationLabel(region: string | null, countryCode: string | null, cityCode: string | null): string {
  const parts: string[] = [];
  if (cityCode) parts.push(cityCode);
  if (region) parts.push(region);
  if (countryCode && !region) parts.push(countryCode);
  return parts.length > 0 ? parts.join(' · ') : '—';
}

// =============================================================================
// COMPONENT
// =============================================================================

export function ReportsPage() {
  // --- FILTER STATE ---
  const [timeRange, setTimeRange] = useState('24h');
  const [region, setRegion] = useState('');
  const [country, setCountry] = useState('');
  const [city, setCity] = useState('');

  // When region === 'Unknown', force country/city to null (no sub-filter makes sense)
  const isUnknownRegion = region === 'Unknown';
  const effectiveCountry = isUnknownRegion ? '' : country;
  const effectiveCity = isUnknownRegion ? '' : city;

  // --- REPORT DRAWER STATE (shared for Pending + Escalated) ---
  const [selectedPendingReport, setSelectedPendingReport] = useState<PendingReportRow | null>(null);
  const [selectedEscalatedReport, setSelectedEscalatedReport] = useState<EscalatedReportRow | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [drawerActionLoading, setDrawerActionLoading] = useState(false);
  const [drawerSource, setDrawerSource] = useState<'pending' | 'escalated'>('pending');

  // --- OVERVIEW DATA STATE ---
  const [overviewLoading, setOverviewLoading] = useState(false);
  const [overviewError, setOverviewError] = useState<string | null>(null);
  const [overviewData, setOverviewData] = useState<OverviewData | null>(null);

  // --- BREAKDOWN DATA STATE ---
  const [breakdownLoading, setBreakdownLoading] = useState(false);
  const [breakdownError, setBreakdownError] = useState<string | null>(null);
  const [breakdownData, setBreakdownData] = useState<BreakdownData | null>(null);

  // --- TREND DATA STATE ---
  const [trendLoading, setTrendLoading] = useState(false);
  const [trendError, setTrendError] = useState<string | null>(null);
  const [trendData, setTrendData] = useState<TrendPoint[] | null>(null);

  // --- MAP DATA STATE ---
  const [mapLoading, setMapLoading] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);
  const [mapMarkers, setMapMarkers] = useState<ReportMapMarker[]>([]);

  // --- INBOX & ACTIONS HOOKS ---
  const { 
    rows: inboxRows, 
    loading: inboxLoading, 
    error: inboxError,
    refetch: refetchInbox 
  } = useReportsInbox(true, 50);

  // Legacy hook (kept for backward compat - refetchActions used in handleRefresh)
  const { refetch: refetchActions } = useModerationActions(timeRange, region || null, effectiveCity || null, 25);

  // Audit Log (paginated, filterable)
  const {
    entries: auditEntries,
    loading: auditLoading,
    error: auditError,
    refetch: refetchAudit,
    loadMore: loadMoreAudit,
    hasMore: hasMoreAudit,
    actionFilter: auditActionFilter,
    setActionFilter: setAuditActionFilter,
  } = useAuditLog(timeRange, region || null, effectiveCountry || null, effectiveCity || null, 20);

  const {
    data: slaData,
    loading: slaLoading,
    error: slaError,
    refetch: refetchSla
  } = useReportsSla(timeRange, region || null, effectiveCountry || null, effectiveCity || null);

  const {
    outcomes: outcomesData,
    loading: outcomesLoading,
    error: outcomesError,
    refetch: refetchOutcomes
  } = useReportsOutcomes(timeRange, region || null, effectiveCountry || null, effectiveCity || null);

  const {
    spike: spikeData,
    loading: spikeLoading,
    error: spikeError,
    refetch: refetchSpike
  } = useReportsSpikeExplain(timeRange, region || null, effectiveCountry || null, effectiveCity || null);

  // Geo Hotspots (top cities by reports/reads density)
  const {
    hotspots: hotspotsData,
    coverage: hotspotsCoverage,
    loading: hotspotsLoading,
    error: hotspotsError,
    refetch: refetchHotspots
  } = useReportsHotspots(timeRange, region || null, effectiveCountry || null);

  // Geo Coverage (data quality indicator)
  const {
    coverage: geoCoverage,
    loading: geoCoverageLoading,
    error: geoCoverageError,
    refetch: refetchGeoCoverage
  } = useReportsGeoCoverage(timeRange, region || null, effectiveCountry || null, effectiveCity || null);

  // Filter options for Country/City dropdowns (cascading from region/country)
  const { options: countryOptions } = useCountryOptions(region || null);
  const { options: cityOptions } = useCityOptions(effectiveCountry || null, region || null);

  const {
    rows: pendingRows,
    loading: pendingLoading,
    error: pendingError,
    refetch: refetchPending,
    loadMore: loadMorePending,
    hasMore: hasMorePending
  } = useReportsPending(timeRange, region || null, effectiveCountry || null, effectiveCity || null, 15);

  const {
    rows: escalatedRows,
    loading: escalatedLoading,
    error: escalatedError,
    refetch: refetchEscalated,
    loadMore: loadMoreEscalated,
    hasMore: hasMoreEscalated
  } = useReportsEscalated(timeRange, region || null, effectiveCountry || null, effectiveCity || null, 15);

  // --- FETCH GUARDS ---
  const inFlightRef = useRef(false);
  const lastParamsRef = useRef<string>('');
  const breakdownInFlightRef = useRef(false);
  const breakdownLastParamsRef = useRef<string>('');
  const trendInFlightRef = useRef(false);
  const trendLastParamsRef = useRef<string>('');
  const mapInFlightRef = useRef(false);
  const mapLastParamsRef = useRef<string>('');

  // --- MAPBOX REFS ---
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const popupRef = useRef<mapboxgl.Popup | null>(null);
  const mapInitializedRef = useRef(false);
  const lastViewportKeyRef = useRef<string>('');

  // --- FETCH OVERVIEW ---
  const fetchOverview = useCallback(async () => {
    // Build params key for deduplication
    const paramsKey = JSON.stringify({ timeRange, region, effectiveCountry, effectiveCity });
    
    // Skip if same params and already fetched
    if (paramsKey === lastParamsRef.current && overviewData !== null) {
      return;
    }
    
    // Skip if already in-flight
    if (inFlightRef.current) {
      return;
    }

    inFlightRef.current = true;
    lastParamsRef.current = paramsKey;
    setOverviewLoading(true);
    setOverviewError(null);

    try {
      const { data, error } = await supabase.rpc('get_reports_overview_v2', {
        p_range: timeRange,
        p_region: region || null,
        p_country: effectiveCountry || null,
        p_city: effectiveCity || null,
      });

      if (error) {
        console.error('[ReportsPage] get_reports_overview_v2 error:', error);
        setOverviewError(error.message || 'Failed to load overview');
        setOverviewData(null);
      } else if (Array.isArray(data) && data.length > 0) {
        const row = data[0];
        setOverviewData({
          reportsTotal: row.reports_total ?? 0,
          reportsPer1kReads: row.reports_per_1k_reads ?? null,
          hiddenTotal: row.hidden_total ?? 0,
          severityScore: row.severity_score ?? 0,
          spikeDetected: row.spike_detected ?? false,
          actionsTotal: row.actions_total ?? 0,
        });
        setOverviewError(null);
      } else {
        // Empty result - set defaults
        setOverviewData({
          reportsTotal: 0,
          reportsPer1kReads: null,
          hiddenTotal: 0,
          severityScore: 0,
          spikeDetected: false,
          actionsTotal: 0,
        });
      }
    } catch (err) {
      console.error('[ReportsPage] fetchOverview exception:', err);
      setOverviewError('Network error');
      setOverviewData(null);
    } finally {
      setOverviewLoading(false);
      inFlightRef.current = false;
    }
  }, [timeRange, region, effectiveCountry, effectiveCity, overviewData]);

  // --- FETCH BREAKDOWN ---
  const fetchBreakdown = useCallback(async () => {
    // Build params key for deduplication
    const paramsKey = JSON.stringify({ timeRange, region, effectiveCountry, effectiveCity, type: 'breakdown' });
    
    // Skip if same params and already fetched
    if (paramsKey === breakdownLastParamsRef.current && breakdownData !== null) {
      return;
    }
    
    // Skip if already in-flight
    if (breakdownInFlightRef.current) {
      return;
    }

    breakdownInFlightRef.current = true;
    breakdownLastParamsRef.current = paramsKey;
    setBreakdownLoading(true);
    setBreakdownError(null);

    try {
      const { data, error } = await supabase.rpc('get_reports_breakdown_v2', {
        p_range: timeRange,
        p_region: region || null,
        p_country: effectiveCountry || null,
        p_city: effectiveCity || null,
      });

      if (error) {
        console.error('[ReportsPage] get_reports_breakdown_v2 error:', error);
        setBreakdownError(error.message || 'Failed to load breakdown');
        setBreakdownData(null);
      } else if (Array.isArray(data) && data.length > 0) {
        const row = data[0];
        // Parse JSONB arrays from response
        const reasons: BreakdownItem[] = Array.isArray(row.top_reasons) ? row.top_reasons : [];
        const locations: BreakdownItem[] = Array.isArray(row.top_locations) ? row.top_locations : [];
        setBreakdownData({
          topReasons: reasons,
          topLocations: locations,
        });
        setBreakdownError(null);
      } else {
        // Empty result - set empty arrays
        setBreakdownData({
          topReasons: [],
          topLocations: [],
        });
      }
    } catch (err) {
      console.error('[ReportsPage] fetchBreakdown exception:', err);
      setBreakdownError('Network error');
      setBreakdownData(null);
    } finally {
      setBreakdownLoading(false);
      breakdownInFlightRef.current = false;
    }
  }, [timeRange, region, effectiveCountry, effectiveCity, breakdownData]);

  // --- FETCH TREND ---
  const fetchTrend = useCallback(async () => {
    // Build params key for deduplication
    const paramsKey = JSON.stringify({ timeRange, region, effectiveCountry, effectiveCity, type: 'trend' });
    
    // Skip if same params and already fetched
    if (paramsKey === trendLastParamsRef.current && trendData !== null) {
      return;
    }
    
    // Skip if already in-flight
    if (trendInFlightRef.current) {
      return;
    }

    trendInFlightRef.current = true;
    trendLastParamsRef.current = paramsKey;
    setTrendLoading(true);
    setTrendError(null);

    try {
      const { data, error } = await supabase.rpc('get_reports_trend_v2', {
        p_range: timeRange,
        p_region: region || null,
        p_country: effectiveCountry || null,
        p_city: effectiveCity || null,
      });

      if (error) {
        console.error('[ReportsPage] get_reports_trend_v2 error:', error);
        setTrendError(error.message || 'Failed to load trend');
        setTrendData(null);
      } else if (Array.isArray(data) && data.length > 0) {
        const row = data[0];
        // Parse JSONB array from response
        const points: TrendPoint[] = Array.isArray(row.trend) ? row.trend : [];
        setTrendData(points);
        setTrendError(null);
      } else {
        // Empty result - set empty array
        setTrendData([]);
      }
    } catch (err) {
      console.error('[ReportsPage] fetchTrend exception:', err);
      setTrendError('Network error');
      setTrendData(null);
    } finally {
      setTrendLoading(false);
      trendInFlightRef.current = false;
    }
  }, [timeRange, region, effectiveCountry, effectiveCity, trendData]);

  // --- FETCH MAP MARKERS ---
  const fetchMap = useCallback(async () => {
    // Build params key for deduplication
    const paramsKey = JSON.stringify({ timeRange, region, effectiveCountry, effectiveCity, type: 'map' });
    
    // Skip if same params and already fetched (and have data)
    if (paramsKey === mapLastParamsRef.current && mapMarkers.length > 0) {
      return;
    }
    
    // Skip if already in-flight
    if (mapInFlightRef.current) {
      return;
    }

    mapInFlightRef.current = true;
    mapLastParamsRef.current = paramsKey;
    setMapLoading(true);
    setMapError(null);

    try {
      const { data, error } = await supabase.rpc('get_reports_map_v2', {
        p_range: timeRange,
        p_region: region || null,
        p_country: effectiveCountry || null,
        p_city: effectiveCity || null,
      });

      if (error) {
        console.error('[ReportsPage] get_reports_map_v2 error:', error);
        setMapError(error.message || 'Failed to load map data');
        setMapMarkers([]);
      } else if (Array.isArray(data) && data.length > 0) {
        const row = data[0];
        // Parse JSONB array from response
        const markers: ReportMapMarker[] = Array.isArray(row.markers) ? row.markers : [];
        setMapMarkers(markers);
        setMapError(null);
      } else {
        // Empty result - set empty array
        setMapMarkers([]);
      }
    } catch (err) {
      console.error('[ReportsPage] fetchMap exception:', err);
      setMapError('Network error');
      setMapMarkers([]);
    } finally {
      setMapLoading(false);
      mapInFlightRef.current = false;
    }
  }, [timeRange, region, effectiveCountry, effectiveCity, mapMarkers.length]);

  // --- FETCH ON MOUNT AND FILTER CHANGE ---
  useEffect(() => {
    fetchOverview();
    fetchBreakdown();
    fetchTrend();
    fetchMap();
  }, [timeRange, region, effectiveCountry, effectiveCity]); // eslint-disable-line react-hooks/exhaustive-deps

  // --- HANDLERS ---
  const handleRefresh = () => {
    // Reset guards to force refetch
    lastParamsRef.current = '';
    breakdownLastParamsRef.current = '';
    trendLastParamsRef.current = '';
    mapLastParamsRef.current = '';
    fetchOverview();
    fetchBreakdown();
    fetchTrend();
    fetchMap();
    refetchInbox();
    refetchActions();
    refetchSla();
    refetchOutcomes();
    refetchSpike();
    refetchHotspots();
    refetchGeoCoverage();
    refetchPending();
    refetchEscalated();
    refetchAudit();
  };

  // Handle action with logging and refresh
  const handleModerationAction = async (
    action: 'handle' | 'hide',
    row: ReportRow
  ) => {
    if (action === 'handle') {
      const result = await setReportHandled({
        reportId: row.report_id,
        confessionId: row.confession_id,
        reason: row.reason,
        region: row.confession_region,
        cityCode: row.report_city_code || undefined,
      });
      if (result.success) {
        // Refresh all data after successful action
        handleRefresh();
      }
    } else if (action === 'hide') {
      const result = await setConfessionHidden({
        confessionId: row.confession_id,
        reportId: row.report_id,
        reason: row.reason,
        region: row.confession_region,
        cityCode: row.report_city_code || undefined,
        hidden: true,
      });
      if (result.success) {
        // Refresh all data after successful action
        handleRefresh();
      }
    }
  };

  // Handle drawer actions (works for both Pending and Escalated)
  const handleDrawerAction = async (
    actionType: 'HIDE_CONFESSION' | 'DISMISS_REPORT' | 'ESCALATE' | 'MARK_HANDLED'
  ) => {
    // Get the active report (from either pending or escalated)
    const report = selectedPendingReport || selectedEscalatedReport;
    if (!report) return;

    setDrawerActionLoading(true);
    try {
      const result = await logModerationAction({
        actionType,
        reportId: report.report_id,
        confessionId: report.confession_id,
        reason: report.reason,
        region: report.region || undefined,
        cityCode: report.city_code || undefined,
        source: drawerSource === 'escalated' ? 'escalated_drawer' : 'pending_drawer',
      });

      if (result.success) {
        // Close drawer and refresh all data
        closeReportDrawer();
        handleRefresh();
      } else {
        // Show error in console (could add toast later)
        console.error('[DRAWER_ACTION] Failed:', result.error);
        alert(`Action failed: ${result.error}`);
      }
    } catch (err) {
      console.error('[DRAWER_ACTION] Error:', err);
      alert('Action failed. Please try again.');
    } finally {
      setDrawerActionLoading(false);
    }
  };

  // Open pending report drawer
  const openPendingDrawer = (report: PendingReportRow) => {
    setSelectedPendingReport(report);
    setSelectedEscalatedReport(null);
    setDrawerSource('pending');
    setDrawerOpen(true);
  };

  // Open escalated report drawer
  const openEscalatedDrawer = (report: EscalatedReportRow) => {
    setSelectedEscalatedReport(report);
    setSelectedPendingReport(null);
    setDrawerSource('escalated');
    setDrawerOpen(true);
  };

  // Close report drawer (shared)
  const closeReportDrawer = () => {
    setDrawerOpen(false);
    setSelectedPendingReport(null);
    setSelectedEscalatedReport(null);
  };

  const handleRegionChange = (value: string) => {
    setRegion(value);
    setCountry(''); // Clear cascading
    setCity('');
  };

  const handleCountryChange = (value: string) => {
    setCountry(value);
    setCity(''); // Clear cascading
  };

  // --- MAPBOX: Convert markers to GeoJSON ---
  const markersToGeoJSON = (markers: ReportMapMarker[]): GeoJSON.FeatureCollection => ({
    type: 'FeatureCollection',
    features: markers.map((m, idx) => ({
      type: 'Feature' as const,
      id: idx,
      properties: {
        city_code: m.city_code,
        region: m.region,
        reports: m.reports,
        hidden: m.hidden,
        top_reason: m.top_reason,
      },
      geometry: {
        type: 'Point' as const,
        coordinates: [m.lng, m.lat],
      },
    })),
  });

  // --- MAPBOX: Initialize map ONCE on mount (independent of markers) ---
  useEffect(() => {
    // Skip if no token
    if (!MAPBOX_TOKEN) return;
    // Skip if container not ready
    if (!mapContainerRef.current) return;
    // Skip if already initialized
    if (mapInitializedRef.current) return;

    mapInitializedRef.current = true;

    // Set token
    mapboxgl.accessToken = MAPBOX_TOKEN;

    // Initialize map
    const map = new mapboxgl.Map({
      container: mapContainerRef.current,
      style: 'mapbox://styles/mapbox/dark-v11',
      center: [0, 20],
      zoom: 1.2,
      attributionControl: false,
    });

    // Disable scroll zoom for dashboard
    map.scrollZoom.disable();

    // Add navigation controls
    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), 'top-right');

    // Create popup (reusable)
    const popup = new mapboxgl.Popup({
      closeButton: true,
      closeOnClick: true,
      maxWidth: '260px',
    });
    popupRef.current = popup;

    map.on('load', () => {
      // Add source with empty FeatureCollection initially
      map.addSource('report-markers', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] },
      });

      // Add circle layer
      map.addLayer({
        id: 'report-circles',
        type: 'circle',
        source: 'report-markers',
        paint: {
          'circle-radius': [
            'interpolate', ['linear'], ['get', 'reports'],
            1, 6,
            10, 10,
            50, 16,
            100, 22,
          ],
          'circle-color': [
            'interpolate', ['linear'], ['get', 'hidden'],
            0, 'rgba(100, 150, 255, 0.75)',
            1, 'rgba(255, 150, 100, 0.75)',
            5, 'rgba(255, 100, 100, 0.85)',
          ],
          'circle-opacity': 0.75,
          'circle-stroke-width': 1,
          'circle-stroke-color': 'rgba(255, 255, 255, 0.3)',
        },
      });

      // Click handler for popup
      map.on('click', 'report-circles', (e) => {
        if (!e.features || e.features.length === 0) return;
        const feature = e.features[0];
        const coords = (feature.geometry as GeoJSON.Point).coordinates.slice() as [number, number];
        const props = feature.properties;

        const cityCode = props?.city_code || '';
        const regionName = props?.region || '';
        const locationLabel = cityCode && regionName 
          ? `${cityCode}, ${regionName}` 
          : cityCode || regionName || 'Unknown';
        const reports = props?.reports ?? 0;
        const hidden = props?.hidden ?? 0;
        const topReason = props?.top_reason || 'Unknown';

        popup
          .setLngLat(coords)
          .setHTML(`
            <div style="font-family: system-ui, sans-serif; color: #fff;">
              <div style="font-weight: 600; font-size: 14px; margin-bottom: 6px;">${locationLabel}</div>
              <div style="font-size: 12px; color: rgba(255,255,255,0.7);">
                <div>Reports: <strong>${reports}</strong></div>
                <div>Hidden: <strong>${hidden}</strong></div>
                <div>Top reason: <strong>${topReason}</strong></div>
              </div>
            </div>
          `)
          .addTo(map);
      });

      // Change cursor on hover
      map.on('mouseenter', 'report-circles', () => {
        map.getCanvas().style.cursor = 'pointer';
      });
      map.on('mouseleave', 'report-circles', () => {
        map.getCanvas().style.cursor = '';
      });
    });

    mapRef.current = map;

    // Cleanup on unmount
    return () => {
      popup.remove();
      map.remove();
      mapRef.current = null;
      popupRef.current = null;
      mapInitializedRef.current = false;
    };
  }, []); // Empty deps = run once on mount

  // --- MAPBOX: Apply viewport based on markers and region filter ---
  const applyViewportForCurrentState = useCallback(() => {
    const map = mapRef.current;
    if (!map) return;

    // Build key to avoid flyTo spam
    const viewportKey = `${region}|${mapMarkers.length}`;
    if (viewportKey === lastViewportKeyRef.current) return;
    lastViewportKeyRef.current = viewportKey;

    if (mapMarkers.length > 0) {
      // A) Markers exist -> fitBounds to markers
      const bounds = new mapboxgl.LngLatBounds();
      mapMarkers.forEach((m) => bounds.extend([m.lng, m.lat]));
      map.fitBounds(bounds, { padding: 60, maxZoom: 12, duration: 600 });
    } else {
      // B/C) No markers -> fly to region or world view
      const viewport = region
        ? REGION_VIEWPORTS[region] || REGION_VIEWPORTS['world']
        : REGION_VIEWPORTS['world'];
      map.flyTo({
        center: viewport.center,
        zoom: viewport.zoom,
        duration: 600,
      });
    }
  }, [region, mapMarkers]);

  // --- MAPBOX: Update data layer when markers change ---
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    // Wait for style to load before updating source
    const updateSource = () => {
      const source = map.getSource('report-markers') as mapboxgl.GeoJSONSource | undefined;
      if (!source) return;

      // Update data
      source.setData(markersToGeoJSON(mapMarkers));

      // Close popup when data changes
      popupRef.current?.remove();

      // Apply viewport (fitBounds or flyTo region)
      applyViewportForCurrentState();
    };

    if (map.isStyleLoaded()) {
      updateSource();
    } else {
      map.once('load', updateSource);
    }
  }, [mapMarkers, applyViewportForCurrentState]);

  // --- MAPBOX: Also apply viewport when region filter changes (even if markers same) ---
  useEffect(() => {
    // Reset viewport key when region changes so next update will apply viewport
    lastViewportKeyRef.current = '';
  }, [region, timeRange]);

  // Calculate max for trend chart scaling
  const trendChartData = trendData && trendData.length > 0
    ? trendData.map(p => ({ label: p.label, reports: p.count, hidden: 0 }))
    : MOCK_TREND;
  const maxReports = Math.max(...trendChartData.map((d) => d.reports), 1);

  // --- RENDER ---
  return (
    <div style={styles.page}>
      {/* A) Page Header */}
      <header style={styles.header}>
        <h1 style={styles.title}>Reports Intelligence</h1>
        <p style={styles.subtitle}>
          Map-first moderation dashboard • See where reports come from and what needs action
        </p>
      </header>

      {/* B) Filter Bar */}
      <div style={styles.filterBar}>
        <div style={styles.filterGroup}>
          <span style={styles.filterLabel}>Time Range</span>
          <select
            style={styles.filterSelect}
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value)}
          >
            {TIME_RANGE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>

        <div style={styles.filterGroup}>
          <span style={styles.filterLabel}>Region</span>
          <select
            style={styles.filterSelect}
            value={region}
            onChange={(e) => handleRegionChange(e.target.value)}
          >
            {REGION_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>

        <div style={styles.filterGroup}>
          <span style={styles.filterLabel}>Country</span>
          <select
            style={{
              ...styles.filterSelect,
              ...(isUnknownRegion ? { opacity: 0.5, cursor: 'not-allowed' } : {}),
            }}
            value={effectiveCountry}
            onChange={(e) => handleCountryChange(e.target.value)}
            disabled={isUnknownRegion}
          >
            <option value="">All Countries</option>
            {countryOptions.map((cc) => (
              <option key={cc} value={cc}>{cc}</option>
            ))}
          </select>
        </div>

        <div style={styles.filterGroup}>
          <span style={styles.filterLabel}>City</span>
          <select
            style={{
              ...styles.filterSelect,
              ...(isUnknownRegion ? { opacity: 0.5, cursor: 'not-allowed' } : {}),
            }}
            value={effectiveCity}
            onChange={(e) => setCity(e.target.value)}
            disabled={isUnknownRegion}
          >
            <option value="">All Cities</option>
            {cityOptions.map((city) => (
              <option key={city} value={city}>{city}</option>
            ))}
          </select>
        </div>

        <div style={styles.filterSpacer} />

        <button style={styles.refreshBtn} onClick={handleRefresh}>
          Refresh
        </button>
      </div>

      {/* Helper text when Unknown region is selected */}
      {isUnknownRegion && (
        <div style={{
          padding: '8px 16px',
          marginBottom: 12,
          fontSize: 11,
          color: 'rgba(255, 255, 255, 0.5)',
          fontStyle: 'italic',
          background: 'rgba(255, 200, 100, 0.05)',
          borderRadius: 6,
          border: '1px solid rgba(255, 200, 100, 0.15)',
        }}>
          Unknown = reports without region (often missing location data). Country/City filters are disabled.
        </div>
      )}

      {/* B.2) Geo Coverage Bar (v2 - honest backfillable/ungeocodable split) */}
      {!geoCoverageLoading && !geoCoverageError && geoCoverage && (
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 24,
          padding: '10px 16px',
          marginBottom: 20,
          background: 'rgba(255, 255, 255, 0.02)',
          border: '1px solid rgba(255, 255, 255, 0.06)',
          borderRadius: 8,
          fontSize: 11,
        }}>
          {/* Reports Coverage (backfillable only) */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ color: 'rgba(255, 255, 255, 0.5)', fontWeight: 500 }}>
              Reports geo:
            </span>
            {geoCoverage.backfillableReports > 0 ? (
              <>
                <span style={{ 
                  color: geoCoverage.regionPct > 80 
                    ? 'rgba(100, 200, 150, 0.9)' 
                    : geoCoverage.regionPct >= 40 
                      ? 'rgba(255, 200, 100, 0.9)' 
                      : 'rgba(255, 100, 100, 0.9)',
                  fontWeight: 600,
                }}>
                  Region {geoCoverage.regionPct}%
                </span>
                <span style={{ color: 'rgba(255, 255, 255, 0.3)' }}>•</span>
                <span style={{ 
                  color: geoCoverage.cityPct > 80 
                    ? 'rgba(100, 200, 150, 0.9)' 
                    : geoCoverage.cityPct >= 40 
                      ? 'rgba(255, 200, 100, 0.9)' 
                      : 'rgba(255, 100, 100, 0.9)',
                  fontWeight: 600,
                }}>
                  City {geoCoverage.cityPct}%
                </span>
                <span style={{ color: 'rgba(255, 255, 255, 0.3)' }}>•</span>
                <span style={{ 
                  color: geoCoverage.countryPct > 80 
                    ? 'rgba(100, 200, 150, 0.9)' 
                    : geoCoverage.countryPct >= 40 
                      ? 'rgba(255, 200, 100, 0.9)' 
                      : 'rgba(255, 100, 100, 0.9)',
                  fontWeight: 600,
                }}>
                  Country {geoCoverage.countryPct}%
                </span>
                <span style={{ color: 'rgba(255, 255, 255, 0.25)', fontSize: 10 }}>
                  ({geoCoverage.countryCovered}/{geoCoverage.backfillableReports} backfillable)
                </span>
              </>
            ) : (
              <span style={{ color: 'rgba(255, 255, 255, 0.4)' }}>No backfillable reports</span>
            )}
          </div>

          {/* Ungeocodable indicator */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ color: 'rgba(255, 255, 255, 0.4)', fontWeight: 500 }}>
              Ungeocodable:
            </span>
            <span style={{ 
              color: geoCoverage.ungeocodableReports > 0 
                ? 'rgba(255, 150, 100, 0.8)' 
                : 'rgba(100, 200, 150, 0.8)',
              fontWeight: 600,
            }}>
              {geoCoverage.ungeocodableReports}
            </span>
            <span style={{ color: 'rgba(255, 255, 255, 0.25)', fontSize: 10 }}>
              / {geoCoverage.totalReports} total
            </span>
          </div>
        </div>
      )}

      {/* C) Signals Row (6 KPI Cards) */}
      <div style={styles.section}>
        <div style={styles.sectionTitle}>
          Signals • {TIME_RANGE_OPTIONS.find(o => o.value === timeRange)?.label ?? timeRange}
          {overviewLoading && <span style={{ marginLeft: 8, opacity: 0.5 }}>Loading…</span>}
        </div>
        {overviewError && (
          <div style={{ fontSize: 12, color: 'rgba(255, 100, 100, 0.8)', marginBottom: 8 }}>
            Data unavailable: {overviewError}
          </div>
        )}
        <div style={styles.signalsRow}>
          {/* Reports */}
          <div style={styles.kpiCard}>
            <div style={styles.kpiLabel}>Reports</div>
            <div style={styles.kpiValue}>
              {overviewLoading ? '—' : (overviewData?.reportsTotal ?? MOCK_SIGNALS.reportsTotal)}
            </div>
            <div style={styles.kpiDelta}>
              {overviewData ? 'In period' : `Mock: +${MOCK_SIGNALS.reportsDelta}`}
            </div>
          </div>

          {/* Reports / 1k Reads */}
          <div style={styles.kpiCard}>
            <div style={styles.kpiLabel}>Per 1k Reads</div>
            <div style={{ ...styles.kpiValue, ...styles.kpiValueSmall }}>
              {overviewLoading
                ? '—'
                : overviewData?.reportsPer1kReads != null
                  ? overviewData.reportsPer1kReads.toFixed(1)
                  : '—'}
            </div>
            <div style={styles.kpiDelta}>
              {overviewData?.reportsPer1kReads != null ? 'Report rate' : 'No reads data'}
            </div>
          </div>

          {/* Hidden */}
          <div style={styles.kpiCard}>
            <div style={styles.kpiLabel}>Hidden</div>
            <div style={styles.kpiValue}>
              {overviewLoading ? '—' : (overviewData?.hiddenTotal ?? MOCK_SIGNALS.hiddenCount)}
            </div>
            <div style={styles.kpiDelta}>
              {overviewData ? 'Recently hidden' : 'Mock data'}
            </div>
          </div>

          {/* SLA - Time to Action */}
          <div style={styles.kpiCard}>
            <div style={styles.kpiLabel}>
              SLA
              {slaLoading && <span style={{ opacity: 0.5, marginLeft: 4 }}>…</span>}
            </div>
            <div style={styles.kpiValue}>
              {slaLoading 
                ? '—' 
                : slaData && slaData.medianMinutes != null 
                  ? formatSlaDuration(slaData.medianMinutes)
                  : '—'}
            </div>
            <div style={styles.kpiDelta}>
              {slaError ? (
                <span style={{ color: 'rgba(255, 100, 100, 0.7)' }}>Error</span>
              ) : slaLoading ? (
                'Loading…'
              ) : slaData && slaData.medianMinutes != null ? (
                <>Median to action (p90 {formatSlaDuration(slaData.p90Minutes)})</>
              ) : (
                'No actioned reports in period'
              )}
            </div>
            {slaData && slaData.oldestPendingMinutes != null && slaData.oldestPendingMinutes > 0 && (
              <div style={{ 
                marginTop: 6, 
                fontSize: 10, 
                color: slaData.oldestPendingMinutes > 2880 // >48h = orange
                  ? 'rgba(255, 150, 100, 0.8)' 
                  : 'rgba(255, 255, 255, 0.35)',
              }}>
                Oldest pending: {formatSlaDuration(slaData.oldestPendingMinutes)}
              </div>
            )}
          </div>

          {/* Spike with Explanation */}
          <div style={styles.kpiCard}>
            <div style={styles.kpiLabel}>
              Spike
              {spikeLoading && <span style={{ opacity: 0.5, marginLeft: 4 }}>…</span>}
            </div>
            <div>
              {spikeLoading ? (
                <span style={styles.kpiNoSpike}>—</span>
              ) : spikeData?.spikeDetected ? (
                <span style={styles.kpiSpike}>YES</span>
              ) : (
                <span style={styles.kpiNoSpike}>—</span>
              )}
            </div>
            {/* Spike explanation */}
            {spikeError ? (
              <div style={{ fontSize: 10, color: 'rgba(255, 100, 100, 0.6)', marginTop: 2 }}>
                Details unavailable
              </div>
            ) : spikeLoading ? (
              <div style={styles.kpiDelta}>Loading…</div>
            ) : spikeData?.spikeDetected ? (
              <>
                {/* Top reason & location */}
                <div style={{ 
                  fontSize: 10, 
                  color: 'rgba(255, 255, 255, 0.6)', 
                  marginTop: 4,
                  lineHeight: 1.3,
                }}>
                  {spikeData.topReason ?? 'Other'}
                  {spikeData.topRegion && spikeData.topRegion !== 'Unknown' && (
                    <> · {spikeData.topRegion}</>
                  )}
                  {spikeData.topCity && spikeData.topCity !== '—' && (
                    <> · {spikeData.topCity}</>
                  )}
                </div>
                {/* Delta info */}
                <div style={{ 
                  fontSize: 9, 
                  color: 'rgba(255, 255, 255, 0.35)', 
                  marginTop: 2,
                }}>
                  +{spikeData.deltaReports} reports · {spikeData.windowHours}h vs prev {spikeData.windowHours}h
                </div>
              </>
            ) : (
              <div style={styles.kpiDelta}>No spike detected</div>
            )}
          </div>

          {/* Actions */}
          <div style={styles.kpiCard}>
            <div style={styles.kpiLabel}>Actions</div>
            <div style={styles.kpiValue}>
              {overviewLoading ? '—' : (overviewData?.actionsTotal ?? MOCK_SIGNALS.actionsTotal)}
            </div>
            <div style={styles.kpiDelta}>
              {overviewData ? 'In period' : 'Mock data'}
            </div>
          </div>
        </div>
      </div>

      {/* C.1) PENDING REPORTS — Command Center */}
      {(() => {
        // Sort pending rows by hours_open descending (worst first) in UI only
        const sortedPending = [...pendingRows].sort((a, b) => (b.hours_open ?? 0) - (a.hours_open ?? 0));
        const oldestHours = sortedPending.length > 0 ? sortedPending[0].hours_open : null;
        const isEmpty = !pendingLoading && !pendingError && sortedPending.length === 0;
        
        // Compact empty strip when no pending reports
        if (isEmpty) {
          return (
            <div style={{
              ...styles.section,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: 'rgba(100, 200, 150, 0.04)',
              border: '1px solid rgba(100, 200, 150, 0.15)',
              borderRadius: 10,
              padding: '14px 18px',
              marginBottom: 16,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span style={{ 
                  fontSize: 14, 
                  fontWeight: 600, 
                  color: 'rgba(255, 255, 255, 0.8)',
                }}>
                  Pending Reports
                </span>
                <span style={{ 
                  fontSize: 11, 
                  color: 'rgba(100, 200, 150, 0.9)',
                  fontWeight: 500,
                }}>
                  All caught up
                </span>
              </div>
              <span style={{
                fontSize: 11,
                fontWeight: 600,
                color: 'rgba(100, 200, 150, 0.9)',
                background: 'rgba(100, 200, 150, 0.12)',
                padding: '4px 10px',
                borderRadius: 6,
              }}>
                0
              </span>
            </div>
          );
        }
        
        return (
          <div style={{
            ...styles.section,
            background: 'linear-gradient(135deg, rgba(255, 100, 80, 0.03) 0%, rgba(255, 180, 80, 0.02) 100%)',
            border: '1px solid rgba(255, 140, 80, 0.15)',
            borderRadius: 12,
            padding: '20px',
            marginBottom: 24,
          }}>
            {/* Header */}
            <div style={{ marginBottom: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span style={{ 
                    fontSize: 16, 
                    fontWeight: 700, 
                    color: '#fff',
                    letterSpacing: '-0.02em'
                  }}>
                    Pending Reports
                  </span>
                  {pendingLoading && (
                    <span style={{ fontSize: 11, opacity: 0.5 }}>Loading…</span>
                  )}
                </div>
                {/* Summary strip */}
                {!pendingLoading && sortedPending.length > 0 && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <span style={{
                      fontSize: 11,
                      color: 'rgba(255, 255, 255, 0.5)',
                      background: 'rgba(255, 255, 255, 0.05)',
                      padding: '3px 8px',
                      borderRadius: 4,
                    }}>
                      Showing {sortedPending.length}{hasMorePending ? '+' : ''}
                    </span>
                    {oldestHours != null && (
                      <span style={{
                        fontSize: 11,
                        color: oldestHours > 48 ? 'rgba(255, 140, 80, 0.9)' : 'rgba(255, 255, 255, 0.5)',
                        fontWeight: oldestHours > 48 ? 600 : 400,
                      }}>
                        Oldest: ~{formatHoursOpen(oldestHours)}
                      </span>
                    )}
                  </div>
                )}
              </div>
              <div style={{ fontSize: 11, color: 'rgba(255, 180, 120, 0.7)', fontWeight: 500 }}>
                Needs attention now
              </div>
            </div>

            {/* Content */}
            <div style={{
              background: 'rgba(0, 0, 0, 0.2)',
              borderRadius: 8,
              overflow: 'hidden',
            }}>
              {pendingLoading && sortedPending.length === 0 ? (
                // Skeleton loading
                <div style={{ padding: 16 }}>
                  {[1, 2, 3, 4].map(i => (
                    <div key={i} style={{ 
                      display: 'flex', 
                      justifyContent: 'space-between', 
                      alignItems: 'center',
                      padding: '10px 0',
                      borderBottom: i < 4 ? '1px solid rgba(255,255,255,0.04)' : 'none'
                    }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <div style={{ width: 55, height: 20, background: 'rgba(255,255,255,0.06)', borderRadius: 4 }} />
                        <div style={{ width: 70, height: 16, background: 'rgba(255,255,255,0.04)', borderRadius: 3 }} />
                        <div style={{ width: 90, height: 12, background: 'rgba(255,255,255,0.03)', borderRadius: 3 }} />
                      </div>
                      <div style={{ width: 50, height: 20, background: 'rgba(255,255,255,0.05)', borderRadius: 4 }} />
                    </div>
                  ))}
                </div>
              ) : pendingError ? (
                <div style={{ padding: '20px', textAlign: 'center', color: 'rgba(255, 100, 100, 0.8)', fontSize: 13 }}>
                  {pendingError}
                </div>
              ) : (
                <>
                  <div style={{ maxHeight: '280px', overflowY: 'auto' }}>
                    {sortedPending.map((row, idx) => (
                      <div 
                        key={row.report_id}
                        style={{ 
                          display: 'flex', 
                          alignItems: 'center',
                          justifyContent: 'space-between',
                          padding: '10px 14px',
                          borderBottom: idx < sortedPending.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                          cursor: 'pointer',
                          transition: 'background 0.12s ease',
                        }}
                        onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.04)'}
                        onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                        onClick={() => openPendingDrawer(row)}
                      >
                        {/* Left: Status + Reason + Location */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0, flex: 1 }}>
                          {/* Status badge */}
                          <span style={{
                            fontSize: 9,
                            fontWeight: 700,
                            color: 'rgba(255, 180, 80, 0.9)',
                            background: 'rgba(255, 180, 80, 0.12)',
                            padding: '3px 6px',
                            borderRadius: 3,
                            textTransform: 'uppercase',
                            letterSpacing: '0.03em',
                            flexShrink: 0,
                          }}>
                            Pending
                          </span>
                          {/* Reason */}
                          <span style={{
                            fontSize: 12,
                            fontWeight: 600,
                            color: '#fff',
                            flexShrink: 0,
                          }}>
                            {row.reason}
                          </span>
                          {/* Location */}
                          <span style={{
                            fontSize: 11,
                            color: 'rgba(255, 255, 255, 0.4)',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                            whiteSpace: 'nowrap',
                          }}>
                            {buildLocationLabel(row.region, row.country_code, row.city_code)}
                          </span>
                        </div>
                        {/* Right: Open time badge */}
                        <div style={{
                          fontSize: 11,
                          fontWeight: row.hours_open > 48 ? 700 : 500,
                          color: row.hours_open > 48 
                            ? 'rgba(255, 100, 80, 1)' 
                            : row.hours_open > 24 
                              ? 'rgba(255, 180, 80, 0.9)' 
                              : 'rgba(255, 255, 255, 0.5)',
                          background: row.hours_open > 48 
                            ? 'rgba(255, 100, 80, 0.15)' 
                            : row.hours_open > 24 
                              ? 'rgba(255, 180, 80, 0.1)' 
                              : 'rgba(255, 255, 255, 0.05)',
                          padding: '4px 8px',
                          borderRadius: 4,
                          whiteSpace: 'nowrap',
                          marginLeft: 12,
                          flexShrink: 0,
                        }}>
                          {formatHoursOpen(row.hours_open)}
                        </div>
                      </div>
                    ))}
                  </div>
                  {/* Load more */}
                  {hasMorePending && (
                    <div style={{ 
                      padding: '10px 14px', 
                      borderTop: '1px solid rgba(255,255,255,0.06)',
                      textAlign: 'center',
                    }}>
                      <button
                        onClick={() => loadMorePending()}
                        disabled={pendingLoading}
                        style={{
                          background: 'rgba(255, 180, 80, 0.08)',
                          border: '1px solid rgba(255, 180, 80, 0.2)',
                          color: 'rgba(255, 180, 80, 0.9)',
                          padding: '6px 14px',
                          borderRadius: 5,
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: pendingLoading ? 'wait' : 'pointer',
                          transition: 'all 0.12s ease',
                        }}
                        onMouseEnter={(e) => {
                          if (!pendingLoading) e.currentTarget.style.background = 'rgba(255, 180, 80, 0.15)';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.background = 'rgba(255, 180, 80, 0.08)';
                        }}
                      >
                        {pendingLoading ? 'Loading…' : 'Load more'}
                      </button>
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        );
      })()}

      {/* C.1b) ESCALATED QUEUE */}
      {(() => {
        // Sort escalated by hours_open descending (worst first = longest waiting)
        const sortedEscalated = [...escalatedRows].sort((a, b) => (b.hours_open ?? 0) - (a.hours_open ?? 0));
        const oldestHours = sortedEscalated.length > 0 ? sortedEscalated[0].hours_open : null;
        const isEmpty = !escalatedLoading && !escalatedError && sortedEscalated.length === 0;
        
        // Compact empty strip when no escalated reports
        if (isEmpty) {
          return (
            <div style={{
              ...styles.section,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: 'rgba(100, 200, 150, 0.04)',
              border: '1px solid rgba(100, 200, 150, 0.15)',
              borderRadius: 10,
              padding: '14px 18px',
              marginBottom: 16,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span style={{ 
                  fontSize: 14, 
                  fontWeight: 600, 
                  color: 'rgba(255, 255, 255, 0.8)',
                }}>
                  Escalated Queue
                </span>
                <span style={{ 
                  fontSize: 11, 
                  color: 'rgba(100, 200, 150, 0.9)',
                  fontWeight: 500,
                }}>
                  No items to review
                </span>
              </div>
              <span style={{
                fontSize: 11,
                fontWeight: 600,
                color: 'rgba(100, 200, 150, 0.9)',
                background: 'rgba(100, 200, 150, 0.12)',
                padding: '4px 10px',
                borderRadius: 6,
              }}>
                0
              </span>
            </div>
          );
        }
        
        return (
          <div style={{
            ...styles.section,
            background: 'linear-gradient(135deg, rgba(255, 80, 60, 0.04) 0%, rgba(255, 100, 80, 0.02) 100%)',
            border: '1px solid rgba(255, 80, 60, 0.2)',
            borderRadius: 12,
            padding: '20px',
            marginBottom: 24,
          }}>
            {/* Header */}
            <div style={{ marginBottom: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span style={{ 
                    fontSize: 16, 
                    fontWeight: 700, 
                    color: 'rgba(255, 100, 80, 1)',
                    letterSpacing: '-0.02em'
                  }}>
                    Escalated Queue
                  </span>
                  {escalatedLoading && (
                    <span style={{ fontSize: 11, opacity: 0.5 }}>Loading…</span>
                  )}
                </div>
                {/* Summary strip */}
                {!escalatedLoading && sortedEscalated.length > 0 && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <span style={{
                      fontSize: 11,
                      color: 'rgba(255, 255, 255, 0.5)',
                      background: 'rgba(255, 255, 255, 0.05)',
                      padding: '3px 8px',
                      borderRadius: 4,
                    }}>
                      Showing {sortedEscalated.length}{hasMoreEscalated ? '+' : ''}
                    </span>
                    {oldestHours != null && (
                      <span style={{
                        fontSize: 11,
                        color: oldestHours > 72 ? 'rgba(255, 80, 60, 1)' : 'rgba(255, 255, 255, 0.5)',
                        fontWeight: oldestHours > 72 ? 600 : 400,
                      }}>
                        Oldest: ~{formatHoursOpen(oldestHours)}
                      </span>
                    )}
                  </div>
                )}
              </div>
              <div style={{ fontSize: 11, color: 'rgba(255, 100, 80, 0.7)', fontWeight: 500 }}>
                Needs review
              </div>
            </div>

            {/* Content */}
            <div style={{
              background: 'rgba(0, 0, 0, 0.2)',
              borderRadius: 8,
              overflow: 'hidden',
            }}>
              {escalatedLoading && sortedEscalated.length === 0 ? (
                // Skeleton loading
                <div style={{ padding: 16 }}>
                  {[1, 2, 3].map(i => (
                    <div key={i} style={{ 
                      display: 'flex', 
                      justifyContent: 'space-between', 
                      alignItems: 'center',
                      padding: '10px 0',
                      borderBottom: i < 3 ? '1px solid rgba(255,255,255,0.04)' : 'none'
                    }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <div style={{ width: 65, height: 20, background: 'rgba(255,100,80,0.1)', borderRadius: 4 }} />
                        <div style={{ width: 70, height: 16, background: 'rgba(255,255,255,0.04)', borderRadius: 3 }} />
                        <div style={{ width: 90, height: 12, background: 'rgba(255,255,255,0.03)', borderRadius: 3 }} />
                      </div>
                      <div style={{ width: 50, height: 20, background: 'rgba(255,255,255,0.05)', borderRadius: 4 }} />
                    </div>
                  ))}
                </div>
              ) : escalatedError ? (
                <div style={{ padding: '20px', textAlign: 'center', color: 'rgba(255, 100, 100, 0.8)', fontSize: 13 }}>
                  {escalatedError}
                </div>
              ) : (
                <>
                  <div style={{ maxHeight: '240px', overflowY: 'auto' }}>
                    {sortedEscalated.map((row, idx) => (
                      <div 
                        key={row.report_id}
                        style={{ 
                          display: 'flex', 
                          alignItems: 'center',
                          justifyContent: 'space-between',
                          padding: '10px 14px',
                          borderBottom: idx < sortedEscalated.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                          cursor: 'pointer',
                          transition: 'background 0.12s ease',
                        }}
                        onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(255,100,80,0.06)'}
                        onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                        onClick={() => openEscalatedDrawer(row)}
                      >
                        {/* Left: Status + Reason + Location */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0, flex: 1 }}>
                          {/* Status badge */}
                          <span style={{
                            fontSize: 9,
                            fontWeight: 700,
                            color: 'rgba(255, 80, 60, 1)',
                            background: 'rgba(255, 80, 60, 0.15)',
                            padding: '3px 6px',
                            borderRadius: 3,
                            textTransform: 'uppercase',
                            letterSpacing: '0.03em',
                            flexShrink: 0,
                          }}>
                            Escalated
                          </span>
                          {/* Reason */}
                          <span style={{
                            fontSize: 12,
                            fontWeight: 600,
                            color: '#fff',
                            flexShrink: 0,
                          }}>
                            {row.reason}
                          </span>
                          {/* Location */}
                          <span style={{
                            fontSize: 11,
                            color: 'rgba(255, 255, 255, 0.4)',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                            whiteSpace: 'nowrap',
                          }}>
                            {buildLocationLabel(row.region, row.country_code, row.city_code)}
                          </span>
                        </div>
                        {/* Right: Open time badge */}
                        <div style={{
                          fontSize: 11,
                          fontWeight: row.hours_open > 72 ? 700 : 500,
                          color: row.hours_open > 72 
                            ? 'rgba(255, 80, 60, 1)' 
                            : row.hours_open > 48 
                              ? 'rgba(255, 140, 80, 0.9)' 
                              : 'rgba(255, 255, 255, 0.5)',
                          background: row.hours_open > 72 
                            ? 'rgba(255, 80, 60, 0.15)' 
                            : row.hours_open > 48 
                              ? 'rgba(255, 140, 80, 0.1)' 
                              : 'rgba(255, 255, 255, 0.05)',
                          padding: '4px 8px',
                          borderRadius: 4,
                          whiteSpace: 'nowrap',
                          marginLeft: 12,
                          flexShrink: 0,
                        }}>
                          {formatHoursOpen(row.hours_open)}
                        </div>
                      </div>
                    ))}
                  </div>
                  {/* Load more */}
                  {hasMoreEscalated && (
                    <div style={{ 
                      padding: '10px 14px', 
                      borderTop: '1px solid rgba(255,255,255,0.06)',
                      textAlign: 'center',
                    }}>
                      <button
                        onClick={() => loadMoreEscalated()}
                        disabled={escalatedLoading}
                        style={{
                          background: 'rgba(255, 80, 60, 0.08)',
                          border: '1px solid rgba(255, 80, 60, 0.2)',
                          color: 'rgba(255, 100, 80, 0.9)',
                          padding: '6px 14px',
                          borderRadius: 5,
                          fontSize: 11,
                          fontWeight: 600,
                          cursor: escalatedLoading ? 'wait' : 'pointer',
                          transition: 'all 0.12s ease',
                        }}
                        onMouseEnter={(e) => {
                          if (!escalatedLoading) e.currentTarget.style.background = 'rgba(255, 80, 60, 0.15)';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.background = 'rgba(255, 80, 60, 0.08)';
                        }}
                      >
                        {escalatedLoading ? 'Loading…' : 'Load more'}
                      </button>
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        );
      })()}

      {/* C.2) Outcomes Section */}
      <div style={styles.section}>
        <div style={styles.sectionTitle}>
          Outcomes • {TIME_RANGE_OPTIONS.find(o => o.value === timeRange)?.label ?? timeRange}
          {outcomesLoading && <span style={{ marginLeft: 8, opacity: 0.5 }}>Loading…</span>}
        </div>
        {outcomesError && (
          <div style={{ fontSize: 12, color: 'rgba(255, 100, 100, 0.8)', marginBottom: 8 }}>
            Data unavailable: {outcomesError}
          </div>
        )}
        <div style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '12px',
          padding: '16px 20px',
          background: 'rgba(255, 255, 255, 0.02)',
          border: '1px solid rgba(255, 255, 255, 0.06)',
          borderRadius: '12px',
        }}>
          {outcomesLoading ? (
            // Skeleton chips
            <>
              {[1, 2, 3, 4].map((i) => (
                <div key={i} style={{
                  padding: '10px 16px',
                  background: 'rgba(255, 255, 255, 0.04)',
                  borderRadius: '8px',
                  width: 120,
                  height: 40,
                  opacity: 0.5,
                }} />
              ))}
            </>
          ) : outcomesData && outcomesData.actionedReports === 0 ? (
            // Empty state
            <div style={{ 
              width: '100%', 
              textAlign: 'center', 
              padding: '12px 0',
              color: 'rgba(255, 255, 255, 0.4)',
              fontSize: 13,
            }}>
              No actions in this period yet
            </div>
          ) : outcomesData ? (
            // Outcome chips
            <>
              {/* Hidden */}
              <div style={{
                padding: '10px 16px',
                background: 'rgba(255, 100, 100, 0.12)',
                border: '1px solid rgba(255, 100, 100, 0.25)',
                borderRadius: '8px',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}>
                <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255, 130, 130, 0.95)' }}>
                  Hidden
                </span>
                <span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255, 255, 255, 0.9)' }}>
                  {outcomesData.hiddenRatePct}%
                </span>
                <span style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)' }}>
                  ({outcomesData.hiddenReports})
                </span>
              </div>

              {/* Dismissed */}
              <div style={{
                padding: '10px 16px',
                background: 'rgba(255, 200, 100, 0.12)',
                border: '1px solid rgba(255, 200, 100, 0.25)',
                borderRadius: '8px',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}>
                <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255, 210, 130, 0.95)' }}>
                  Dismissed
                </span>
                <span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255, 255, 255, 0.9)' }}>
                  {outcomesData.dismissedRatePct}%
                </span>
                <span style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)' }}>
                  ({outcomesData.dismissedReports})
                </span>
              </div>

              {/* Escalated */}
              <div style={{
                padding: '10px 16px',
                background: 'rgba(200, 100, 255, 0.12)',
                border: '1px solid rgba(200, 100, 255, 0.25)',
                borderRadius: '8px',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}>
                <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(210, 130, 255, 0.95)' }}>
                  Escalated
                </span>
                <span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255, 255, 255, 0.9)' }}>
                  {outcomesData.escalatedRatePct}%
                </span>
                <span style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)' }}>
                  ({outcomesData.escalatedReports})
                </span>
              </div>

              {/* Handled */}
              <div style={{
                padding: '10px 16px',
                background: 'rgba(100, 200, 150, 0.12)',
                border: '1px solid rgba(100, 200, 150, 0.25)',
                borderRadius: '8px',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}>
                <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(130, 210, 170, 0.95)' }}>
                  Handled
                </span>
                <span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255, 255, 255, 0.9)' }}>
                  {outcomesData.handledRatePct}%
                </span>
                <span style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)' }}>
                  ({outcomesData.handledReports})
                </span>
              </div>
            </>
          ) : null}
        </div>
        {/* Footer info */}
        {outcomesData && outcomesData.actionedReports > 0 && (
          <div style={{ 
            marginTop: 8, 
            fontSize: 11, 
            color: 'rgba(255, 255, 255, 0.35)',
            textAlign: 'center',
          }}>
            Based on latest action per report · Actioned reports: {outcomesData.actionedReports}
          </div>
        )}
      </div>

      {/* C.2) Geo Hotspots Section */}
      <div style={styles.section}>
        <div style={{ marginBottom: 12 }}>
          <div style={styles.sectionTitle}>Hotspots</div>
          <div style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)' }}>
            Top cities by report density {region ? `in ${region}` : ''}
          </div>
        </div>

        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', 
          gap: 16 
        }}>
          {/* Left Card: Top Cities */}
          <div style={{
            background: 'rgba(255, 255, 255, 0.02)',
            border: '1px solid rgba(255, 255, 255, 0.06)',
            borderRadius: 10,
            overflow: 'hidden',
          }}>
            <div style={{
              padding: '12px 14px',
              borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
              background: 'rgba(255, 255, 255, 0.02)',
            }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: 'rgba(255, 255, 255, 0.8)' }}>
                Top Cities
              </div>
              <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginTop: 2 }}>
                Click to filter by city
              </div>
            </div>

            <div style={{ maxHeight: 280, overflowY: 'auto' }}>
              {/* Loading */}
              {hotspotsLoading && (
                <div style={{ padding: 16 }}>
                  {[1, 2, 3, 4, 5].map((i) => (
                    <div key={i} style={{ 
                      display: 'flex', 
                      justifyContent: 'space-between', 
                      padding: '8px 0',
                      borderBottom: i < 5 ? '1px solid rgba(255,255,255,0.04)' : 'none'
                    }}>
                      <div style={{ width: 60, height: 12, background: 'rgba(255,255,255,0.06)', borderRadius: 3 }} />
                      <div style={{ width: 40, height: 12, background: 'rgba(255,255,255,0.04)', borderRadius: 3 }} />
                    </div>
                  ))}
                </div>
              )}

              {/* Error */}
              {!hotspotsLoading && hotspotsError && (
                <div style={{ padding: '24px 16px', textAlign: 'center', color: 'rgba(255, 100, 100, 0.7)', fontSize: 12 }}>
                  {hotspotsError}
                </div>
              )}

              {/* Empty */}
              {!hotspotsLoading && !hotspotsError && hotspotsData.length === 0 && (
                <div style={{ padding: '24px 16px', textAlign: 'center' }}>
                  <div style={{ fontSize: 12, color: 'rgba(255, 255, 255, 0.4)' }}>
                    No hotspots in this period
                  </div>
                </div>
              )}

              {/* Cities list */}
              {!hotspotsLoading && !hotspotsError && hotspotsData.length > 0 && (
                <div style={{ padding: '4px 0' }}>
                  {hotspotsData.map((hotspot, i) => (
                    <div
                      key={hotspot.city_code}
                      onClick={() => {
                        if (hotspot.city_code && hotspot.city_code !== 'Unknown') {
                          setCity(hotspot.city_code);
                        }
                      }}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        padding: '10px 14px',
                        borderBottom: i < hotspotsData.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                        cursor: hotspot.city_code !== 'Unknown' ? 'pointer' : 'default',
                        transition: 'background 0.12s ease',
                      }}
                      onMouseEnter={(e) => {
                        if (hotspot.city_code !== 'Unknown') {
                          e.currentTarget.style.background = 'rgba(255,255,255,0.03)';
                        }
                      }}
                      onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                    >
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ 
                          display: 'flex', 
                          alignItems: 'center', 
                          gap: 8,
                          marginBottom: 2,
                        }}>
                          <span style={{ 
                            fontSize: 12, 
                            fontWeight: 600, 
                            color: 'rgba(255, 255, 255, 0.85)' 
                          }}>
                            {hotspot.city_label}
                          </span>
                          {hotspot.top_reason && (
                            <span style={{
                              fontSize: 9,
                              padding: '2px 5px',
                              background: 'rgba(255, 100, 100, 0.15)',
                              color: 'rgba(255, 150, 150, 0.9)',
                              borderRadius: 4,
                              fontWeight: 500,
                            }}>
                              {hotspot.top_reason}
                            </span>
                          )}
                        </div>
                        <div style={{ 
                          fontSize: 10, 
                          color: 'rgba(255, 255, 255, 0.35)' 
                        }}>
                          {hotspot.region || '—'}
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <div style={{ 
                          fontSize: 13, 
                          fontWeight: 600, 
                          color: hotspot.reports_per_1k != null && hotspot.reports_per_1k > 10 
                            ? 'rgba(255, 130, 100, 0.95)' 
                            : 'rgba(255, 255, 255, 0.8)'
                        }}>
                          {hotspot.reports_per_1k != null 
                            ? `${hotspot.reports_per_1k}/1k`
                            : `${hotspot.reports_count} rep`}
                        </div>
                        <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.35)' }}>
                          {hotspot.reads_count != null 
                            ? `${hotspot.reports_count} / ${hotspot.reads_count}`
                            : `reports`}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Data Quality Line */}
            {hotspotsCoverage && hotspotsCoverage.totalReports > 0 && (
              <div style={{
                padding: '10px 14px',
                borderTop: '1px solid rgba(255, 255, 255, 0.06)',
                background: 'rgba(255, 255, 255, 0.01)',
              }}>
                <div style={{ 
                  fontSize: 10, 
                  color: 'rgba(255, 255, 255, 0.35)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 4,
                }}>
                  <span style={{ opacity: 0.6 }}>📊</span>
                  <span>
                    Missing city: {hotspotsCoverage.unknownReportsPct}% of reports
                    {hotspotsCoverage.totalReads > 0 && (
                      <> • {hotspotsCoverage.unknownReadsPct}% of reads</>
                    )}
                  </span>
                </div>
              </div>
            )}
          </div>

          {/* Right Card: Top Reasons (for selected geo) */}
          <div style={{
            background: 'rgba(255, 255, 255, 0.02)',
            border: '1px solid rgba(255, 255, 255, 0.06)',
            borderRadius: 10,
            overflow: 'hidden',
          }}>
            <div style={{
              padding: '12px 14px',
              borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
              background: 'rgba(255, 255, 255, 0.02)',
            }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: 'rgba(255, 255, 255, 0.8)' }}>
                Top Reasons
              </div>
              <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginTop: 2 }}>
                {city ? `In ${city}` : region ? `In ${region}` : 'Global'}
              </div>
            </div>

            <div style={{ maxHeight: 280, overflowY: 'auto' }}>
              {/* Loading */}
              {breakdownLoading && (
                <div style={{ padding: 16 }}>
                  {[1, 2, 3, 4].map((i) => (
                    <div key={i} style={{ 
                      display: 'flex', 
                      justifyContent: 'space-between', 
                      padding: '8px 0',
                      borderBottom: i < 4 ? '1px solid rgba(255,255,255,0.04)' : 'none'
                    }}>
                      <div style={{ width: 80, height: 12, background: 'rgba(255,255,255,0.06)', borderRadius: 3 }} />
                      <div style={{ width: 30, height: 12, background: 'rgba(255,255,255,0.04)', borderRadius: 3 }} />
                    </div>
                  ))}
                </div>
              )}

              {/* Error */}
              {!breakdownLoading && breakdownError && (
                <div style={{ padding: '24px 16px', textAlign: 'center', color: 'rgba(255, 100, 100, 0.7)', fontSize: 12 }}>
                  {breakdownError}
                </div>
              )}

              {/* Empty */}
              {!breakdownLoading && !breakdownError && (breakdownData?.topReasons?.length ?? 0) === 0 && (
                <div style={{ padding: '24px 16px', textAlign: 'center' }}>
                  <div style={{ fontSize: 12, color: 'rgba(255, 255, 255, 0.4)' }}>
                    No reports in this period
                  </div>
                </div>
              )}

              {/* Reasons list (reuse existing breakdown data) */}
              {!breakdownLoading && !breakdownError && (breakdownData?.topReasons?.length ?? 0) > 0 && (
                <div style={{ padding: '4px 0' }}>
                  {breakdownData!.topReasons.map((reason: BreakdownItem, i: number) => {
                    const reasonColors: Record<string, string> = {
                      'Spam': 'rgba(255, 100, 100, 0.9)',
                      'Identifying': 'rgba(255, 180, 80, 0.9)',
                      'Harmful': 'rgba(200, 100, 255, 0.9)',
                      'Illegal': 'rgba(255, 80, 80, 0.95)',
                      'Other': 'rgba(150, 150, 150, 0.7)',
                    };
                    const color = reasonColors[reason.key] || 'rgba(255, 255, 255, 0.7)';
                    return (
                      <div
                        key={reason.key}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'space-between',
                          padding: '10px 14px',
                          borderBottom: i < breakdownData!.topReasons.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                        }}
                      >
                        <div style={{ 
                          display: 'flex', 
                          alignItems: 'center', 
                          gap: 10,
                          flex: 1,
                        }}>
                          <span style={{
                            fontSize: 11,
                            padding: '3px 8px',
                            background: `${color}15`,
                            color: color,
                            borderRadius: 4,
                            fontWeight: 600,
                          }}>
                            {reason.key}
                          </span>
                          {/* Progress bar */}
                          <div style={{ 
                            flex: 1, 
                            height: 4, 
                            background: 'rgba(255,255,255,0.05)',
                            borderRadius: 2,
                            overflow: 'hidden',
                          }}>
                            <div style={{
                              width: `${Math.min(reason.pct, 100)}%`,
                              height: '100%',
                              background: color,
                              borderRadius: 2,
                            }} />
                          </div>
                        </div>
                        <div style={{ 
                          fontSize: 12, 
                          fontWeight: 600, 
                          color: 'rgba(255, 255, 255, 0.7)',
                          marginLeft: 12,
                          minWidth: 45,
                          textAlign: 'right',
                        }}>
                          {reason.pct}%
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* D) Map Core + Side Panel */}
      <div style={styles.section}>
        <div style={styles.sectionTitle}>Where it's happening</div>
        <div style={styles.mapSection}>
          {/* World Map with Markers */}
          <div style={styles.mapCard}>
            {/* No token warning */}
            {!MAPBOX_TOKEN ? (
              <div style={styles.mapPlaceholder}>
                <div style={styles.mapPlaceholderText}>
                  <div style={styles.mapPlaceholderTitle}>Map unavailable</div>
                  <div style={{ ...styles.mapPlaceholderSub, color: 'rgba(255, 200, 100, 0.7)' }}>
                    Missing token (VITE_MAPBOX_TOKEN)
                  </div>
                </div>
              </div>
            ) : (
              /* Mapbox container - always rendered when token exists */
              <div style={{ position: 'relative', width: '100%', height: '100%' }}>
                {/* The actual map canvas */}
                <div
                  ref={mapContainerRef}
                  style={{
                    width: '100%',
                    height: '100%',
                    borderRadius: '12px',
                    overflow: 'hidden',
                  }}
                />

                {/* Loading overlay */}
                {mapLoading && (
                  <div style={{
                    position: 'absolute',
                    inset: 0,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    background: 'rgba(0, 0, 0, 0.5)',
                    borderRadius: '12px',
                    zIndex: 10,
                  }}>
                    <div style={{ textAlign: 'center' }}>
                      <div style={{ fontSize: 16, fontWeight: 500, color: 'rgba(255, 255, 255, 0.8)' }}>
                        Loading map data…
                      </div>
                    </div>
                  </div>
                )}

                {/* Error overlay */}
                {!mapLoading && mapError && (
                  <div style={{
                    position: 'absolute',
                    inset: 0,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    background: 'rgba(0, 0, 0, 0.6)',
                    borderRadius: '12px',
                    zIndex: 10,
                  }}>
                    <div style={{ textAlign: 'center' }}>
                      <div style={{ fontSize: 16, fontWeight: 500, color: 'rgba(255, 100, 100, 0.9)' }}>
                        Map data unavailable
                      </div>
                      <div style={{ fontSize: 12, color: 'rgba(255, 255, 255, 0.5)', marginTop: 4 }}>
                        {mapError}
                      </div>
                    </div>
                  </div>
                )}

                {/* No activity overlay (map still visible behind) */}
                {!mapLoading && !mapError && mapMarkers.length === 0 && (
                  <div style={{
                    position: 'absolute',
                    inset: 0,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    background: 'rgba(0, 0, 0, 0.4)',
                    borderRadius: '12px',
                    zIndex: 10,
                    pointerEvents: 'none',
                  }}>
                    <div style={{ textAlign: 'center' }}>
                      <div style={{ fontSize: 18, fontWeight: 600, color: 'rgba(255, 255, 255, 0.85)' }}>
                        No report activity
                      </div>
                      <div style={{ fontSize: 13, color: 'rgba(255, 255, 255, 0.5)', marginTop: 4 }}>
                        No reports in this period/filter
                      </div>
                    </div>
                  </div>
                )}

                {/* Marker count badge when we have data */}
                {!mapLoading && !mapError && mapMarkers.length > 0 && (
                  <div style={{
                    position: 'absolute',
                    top: 12,
                    left: 12,
                    padding: '6px 12px',
                    background: 'rgba(0, 0, 0, 0.6)',
                    borderRadius: '6px',
                    fontSize: 12,
                    fontWeight: 500,
                    color: 'rgba(255, 255, 255, 0.85)',
                    zIndex: 10,
                    pointerEvents: 'none',
                  }}>
                    {mapMarkers.length} location{mapMarkers.length !== 1 ? 's' : ''}
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Right Panel */}
          <div style={styles.sidePanel}>
            {/* Top Locations (Regions or Cities based on filter) */}
            <div style={styles.panelCard}>
              <div style={styles.panelTitle}>
                Top {region ? 'Cities' : 'Regions'}
                {breakdownLoading && <span style={{ marginLeft: 6, opacity: 0.5, fontSize: 10 }}>Loading…</span>}
              </div>
              {breakdownError && (
                <div style={{ fontSize: 11, color: 'rgba(255, 100, 100, 0.7)', marginBottom: 8 }}>
                  Data unavailable
                </div>
              )}
              <div style={styles.panelList}>
                {breakdownLoading ? (
                  <div style={{ fontSize: 12, color: 'rgba(255, 255, 255, 0.4)', padding: '12px 0' }}>
                    Loading…
                  </div>
                ) : breakdownError ? null : (breakdownData?.topLocations?.length ?? 0) === 0 ? (
                  <div style={{ fontSize: 12, color: 'rgba(255, 255, 255, 0.4)', padding: '12px 0' }}>
                    No location data in this period
                  </div>
                ) : (
                  breakdownData!.topLocations.map((item, i, arr) => (
                    <div
                      key={item.key}
                      style={{
                        ...styles.panelRow,
                        ...(i === arr.length - 1 ? styles.panelRowLast : {}),
                      }}
                    >
                      <span style={styles.panelRowName}>{item.key}</span>
                      <div style={styles.panelRowStats}>
                        <span style={styles.panelRowCount}>{item.count}</span>
                        <span style={styles.panelRowPct}>{item.pct}%</span>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* E) Trend Section */}
      <div style={styles.section}>
        <div style={styles.sectionTitle}>
          Trend • {TIME_RANGE_OPTIONS.find(o => o.value === timeRange)?.label ?? timeRange}
          {trendLoading && <span style={{ marginLeft: 8, opacity: 0.5 }}>Loading…</span>}
        </div>
        {trendError && (
          <div style={{ fontSize: 12, color: 'rgba(255, 100, 100, 0.8)', marginBottom: 8 }}>
            Data unavailable
          </div>
        )}
        <div style={styles.trendCard}>
          {trendData && trendData.length === 0 && !trendLoading ? (
            <div style={{ padding: 32, textAlign: 'center', color: 'rgba(255,255,255,0.4)' }}>
              No data in this period
            </div>
          ) : (
            <>
              <div style={styles.trendChart}>
                {trendChartData.map((d, i) => (
                  <div key={`${d.label}-${i}`} style={styles.trendBarGroup}>
                    <div style={{ display: 'flex', alignItems: 'flex-end', gap: '2px', height: '100px' }}>
                      <div
                        style={{
                          ...styles.trendBar,
                          ...styles.trendBarReports,
                          height: `${(d.reports / maxReports) * 100}%`,
                          width: '16px',
                        }}
                        title={`${d.label}: ${d.reports} reports`}
                      />
                      {d.hidden > 0 && (
                        <div
                          style={{
                            ...styles.trendBar,
                            ...styles.trendBarHidden,
                            height: `${(d.hidden / maxReports) * 100}%`,
                            width: '12px',
                          }}
                        />
                      )}
                    </div>
                    <span style={styles.trendLabel}>{d.label}</span>
                  </div>
                ))}
              </div>
              <div style={styles.trendLegend}>
                <div style={styles.trendLegendItem}>
                  <div style={{ ...styles.trendLegendDot, ...styles.trendBarReports }} />
                  Reports
                </div>
                {trendChartData.some(d => d.hidden > 0) && (
                  <div style={styles.trendLegendItem}>
                    <div style={{ ...styles.trendLegendDot, ...styles.trendBarHidden }} />
                    Hidden
                  </div>
                )}
                {!trendData && !trendLoading && !trendError && (
                  <span style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.3)', marginLeft: 12 }}>Mock data</span>
                )}
              </div>
            </>
          )}
        </div>
      </div>

      {/* F) Full Inbox Section */}
      <div style={styles.section}>
        <div style={styles.sectionTitle}>
          Full Inbox
          {inboxLoading && <span style={{ marginLeft: 8, opacity: 0.5, fontSize: 12 }}>Loading…</span>}
        </div>
        <div style={styles.inboxCard}>
          <div style={styles.inboxHeader}>
            <span style={styles.inboxTitle}>All Unhandled Reports</span>
            <span style={styles.inboxBadge}>
              {inboxLoading ? '…' : inboxRows.length} total
            </span>
          </div>
          {inboxError ? (
            <div style={{ padding: '20px', textAlign: 'center', color: 'rgba(255, 100, 100, 0.8)' }}>
              {inboxError}
            </div>
          ) : inboxRows.length === 0 && !inboxLoading ? (
            <div style={{ padding: '20px', textAlign: 'center', color: 'rgba(255, 255, 255, 0.5)' }}>
              No unhandled reports
            </div>
          ) : (
            <table style={styles.table}>
              <thead>
                <tr>
                  <th style={styles.th}>ID</th>
                  <th style={styles.th}>Reason</th>
                  <th style={styles.th}>Region</th>
                  <th style={styles.th}>Confession</th>
                  <th style={styles.th}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {inboxRows.slice(0, 10).map((row) => (
                  <tr key={row.report_id}>
                    <td style={styles.td}>{row.report_id.slice(0, 8)}…</td>
                    <td style={styles.td}>
                      <span style={styles.reasonBadge}>{row.reason}</span>
                    </td>
                    <td style={styles.td}>{row.confession_region || '—'}</td>
                    <td style={styles.td}>
                      <span style={{ 
                        fontSize: 11, 
                        color: row.confession_is_hidden ? 'rgba(255, 100, 100, 0.7)' : 'rgba(255, 255, 255, 0.6)'
                      }}>
                        {row.confession_text?.slice(0, 40)}…
                        {row.confession_is_hidden && ' (hidden)'}
                      </span>
                    </td>
                    <td style={styles.td}>
                      <button 
                        style={styles.actionBtn}
                        onClick={() => handleModerationAction('handle', row)}
                      >
                        Handle
                      </button>
                      <button 
                        style={styles.actionBtn}
                        onClick={() => handleModerationAction('hide', row)}
                        disabled={row.confession_is_hidden}
                      >
                        {row.confession_is_hidden ? 'Hidden' : 'Hide'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* G) Audit Log Section */}
      <div style={styles.section}>
        {/* Header */}
        <div style={{ marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={styles.sectionTitle}>Audit Log</span>
              {auditLoading && auditEntries.length === 0 && (
                <span style={{ fontSize: 11, opacity: 0.5 }}>Loading…</span>
              )}
              {!auditLoading && (
                <span style={{ 
                  fontSize: 10, 
                  color: 'rgba(255, 255, 255, 0.4)', 
                  fontWeight: 500,
                }}>
                  {auditEntries.length}{hasMoreAudit ? '+' : ''} entries
                </span>
              )}
            </div>
          </div>
          <div style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)' }}>
            Latest moderation actions
          </div>
        </div>

        {/* Filter Chips */}
        <div style={{ 
          display: 'flex', 
          flexWrap: 'wrap', 
          gap: 8, 
          marginBottom: 16 
        }}>
          {(['all', 'hidden', 'dismissed', 'escalated', 'handled'] as ActionTypeFilter[]).map((filter) => {
            const isActive = auditActionFilter === filter;
            const labels: Record<ActionTypeFilter, string> = {
              'all': 'All',
              'hidden': 'Hidden',
              'dismissed': 'Dismissed',
              'escalated': 'Escalated',
              'handled': 'Handled',
            };
            const colors: Record<ActionTypeFilter, string> = {
              'all': 'rgba(255, 255, 255, 0.8)',
              'hidden': 'rgba(255, 100, 100, 0.9)',
              'dismissed': 'rgba(255, 255, 255, 0.7)',
              'escalated': 'rgba(255, 180, 80, 0.9)',
              'handled': 'rgba(100, 200, 150, 0.9)',
            };
            return (
              <button
                key={filter}
                onClick={() => setAuditActionFilter(filter)}
                style={{
                  background: isActive ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.03)',
                  border: isActive ? '1px solid rgba(255, 255, 255, 0.2)' : '1px solid rgba(255, 255, 255, 0.08)',
                  borderRadius: 6,
                  padding: '6px 12px',
                  fontSize: 11,
                  fontWeight: isActive ? 600 : 500,
                  color: isActive ? colors[filter] : 'rgba(255, 255, 255, 0.5)',
                  cursor: 'pointer',
                  transition: 'all 0.15s ease',
                }}
              >
                {labels[filter]}
              </button>
            );
          })}
        </div>

        {/* Table Container */}
        <div style={{
          background: 'rgba(255, 255, 255, 0.02)',
          border: '1px solid rgba(255, 255, 255, 0.06)',
          borderRadius: 8,
          overflow: 'hidden',
        }}>
          {/* Error state */}
          {auditError && (
            <div style={{ padding: '20px', textAlign: 'center', color: 'rgba(255, 100, 100, 0.7)', fontSize: 12 }}>
              {auditError}
            </div>
          )}

          {/* Loading state (initial) */}
          {auditLoading && auditEntries.length === 0 && !auditError && (
            <div style={{ padding: 16 }}>
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} style={{ 
                  display: 'flex', 
                  gap: 16, 
                  padding: '10px 0',
                  borderBottom: i < 5 ? '1px solid rgba(255,255,255,0.04)' : 'none'
                }}>
                  <div style={{ width: 60, height: 12, background: 'rgba(255,255,255,0.06)', borderRadius: 3 }} />
                  <div style={{ width: 80, height: 12, background: 'rgba(255,255,255,0.08)', borderRadius: 3 }} />
                  <div style={{ width: 70, height: 12, background: 'rgba(255,255,255,0.05)', borderRadius: 3 }} />
                  <div style={{ width: 90, height: 12, background: 'rgba(255,255,255,0.04)', borderRadius: 3 }} />
                </div>
              ))}
            </div>
          )}

          {/* Empty state */}
          {!auditLoading && !auditError && auditEntries.length === 0 && (
            <div style={{ padding: '32px 20px', textAlign: 'center' }}>
              <div style={{ fontSize: 13, color: 'rgba(255, 255, 255, 0.5)', marginBottom: 4 }}>
                No actions found
              </div>
              <div style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.3)' }}>
                {auditActionFilter !== 'all' 
                  ? 'Try a different filter or time range' 
                  : 'Take moderation actions to build an audit trail'}
              </div>
            </div>
          )}

          {/* Table */}
          {!auditError && auditEntries.length > 0 && (
            <>
              {/* Table Header */}
              <div style={{
                display: 'grid',
                gridTemplateColumns: '90px 100px 1fr 120px',
                gap: 12,
                padding: '10px 14px',
                background: 'rgba(255, 255, 255, 0.03)',
                borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
                fontSize: 10,
                fontWeight: 600,
                color: 'rgba(255, 255, 255, 0.4)',
                textTransform: 'uppercase',
                letterSpacing: '0.05em',
              }}>
                <div>Time</div>
                <div>Action</div>
                <div>Details</div>
                <div style={{ textAlign: 'right' }}>Location</div>
              </div>

              {/* Table Body (scrollable) */}
              <div style={{ maxHeight: 420, overflowY: 'auto' }}>
                {auditEntries.map((entry, i) => {
                  // Canonical action colors and labels
                  const actionColors: Record<string, string> = {
                    'hidden': 'rgba(255, 100, 100, 0.9)',
                    'dismissed': 'rgba(255, 255, 255, 0.6)',
                    'escalated': 'rgba(255, 180, 80, 0.9)',
                    'handled': 'rgba(100, 200, 150, 0.9)',
                    'other': 'rgba(200, 200, 200, 0.7)',
                  };
                  const actionLabels: Record<string, string> = {
                    'hidden': 'Hidden',
                    'dismissed': 'Dismissed',
                    'escalated': 'Escalated',
                    'handled': 'Handled',
                    'other': 'Other',
                  };
                  const location = buildLocationLabel(entry.region, entry.country_code, entry.city_code);

                  return (
                    <div
                      key={entry.id}
                      style={{
                        display: 'grid',
                        gridTemplateColumns: '90px 100px 1fr 120px',
                        gap: 12,
                        padding: '10px 14px',
                        borderBottom: i < auditEntries.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                        fontSize: 12,
                        alignItems: 'center',
                        transition: 'background 0.12s ease',
                        cursor: (entry.region || entry.city_code) ? 'pointer' : 'default',
                      }}
                      onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.02)'}
                      onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                      onClick={() => {
                        if (entry.region) {
                          setRegion(entry.region);
                          setCountry('');
                          setCity('');
                        } else if (entry.city_code) {
                          setCity(entry.city_code);
                        }
                      }}
                    >
                      {/* Time */}
                      <div style={{ color: 'rgba(255, 255, 255, 0.4)', fontSize: 11 }}>
                        {formatRelativeTime(entry.created_at)}
                      </div>
                      {/* Action */}
                      <div>
                        <span style={{
                          fontSize: 10,
                          fontWeight: 600,
                          color: actionColors[entry.action_type] || 'rgba(255, 255, 255, 0.6)',
                          background: `${actionColors[entry.action_type] || 'rgba(255, 255, 255, 0.6)'}15`,
                          padding: '3px 6px',
                          borderRadius: 4,
                        }}>
                          {actionLabels[entry.action_type] || entry.action_type}
                        </span>
                      </div>
                      {/* Details (reason + ID) */}
                      <div style={{ 
                        color: 'rgba(255, 255, 255, 0.6)', 
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                      }}>
                        {entry.reason || '—'}
                        {entry.report_id && (
                          <span style={{ 
                            marginLeft: 8, 
                            fontSize: 10, 
                            color: 'rgba(255, 255, 255, 0.25)',
                            fontFamily: 'monospace',
                          }}>
                            #{entry.report_id.slice(0, 6)}
                          </span>
                        )}
                      </div>
                      {/* Location */}
                      <div style={{ 
                        color: 'rgba(255, 255, 255, 0.4)', 
                        textAlign: 'right',
                        fontSize: 11,
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                      }}>
                        {location}
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Load More */}
              {hasMoreAudit && (
                <div style={{ 
                  padding: '12px 14px', 
                  borderTop: '1px solid rgba(255,255,255,0.06)',
                  textAlign: 'center',
                }}>
                  <button
                    onClick={() => loadMoreAudit()}
                    disabled={auditLoading}
                    style={{
                      background: 'rgba(255, 255, 255, 0.05)',
                      border: '1px solid rgba(255, 255, 255, 0.1)',
                      color: 'rgba(255, 255, 255, 0.7)',
                      padding: '8px 16px',
                      borderRadius: 6,
                      fontSize: 11,
                      fontWeight: 500,
                      cursor: auditLoading ? 'wait' : 'pointer',
                      transition: 'all 0.12s ease',
                    }}
                    onMouseEnter={(e) => {
                      if (!auditLoading) e.currentTarget.style.background = 'rgba(255, 255, 255, 0.08)';
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.background = 'rgba(255, 255, 255, 0.05)';
                    }}
                  >
                    {auditLoading ? 'Loading…' : 'Load more'}
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* REPORT ACTION DRAWER (shared for Pending + Escalated) */}
      {drawerOpen && (selectedPendingReport || selectedEscalatedReport) && (() => {
        // Get the active report
        const activeReport = selectedPendingReport || selectedEscalatedReport;
        if (!activeReport) return null;
        const isEscalated = drawerSource === 'escalated';
        
        return (
          <>
            {/* Backdrop */}
            <div
              onClick={closeReportDrawer}
              style={{
                position: 'fixed',
                inset: 0,
                background: 'rgba(0, 0, 0, 0.6)',
                zIndex: 999,
                cursor: 'pointer',
              }}
            />
            {/* Drawer */}
            <div
              style={{
                position: 'fixed',
                top: 0,
                right: 0,
                bottom: 0,
                width: 380,
                maxWidth: '100vw',
                background: '#1a1a1f',
                borderLeft: isEscalated 
                  ? '1px solid rgba(255, 100, 80, 0.3)' 
                  : '1px solid rgba(255, 255, 255, 0.1)',
                zIndex: 1000,
                display: 'flex',
                flexDirection: 'column',
                boxShadow: '-8px 0 32px rgba(0, 0, 0, 0.4)',
              }}
            >
              {/* Header */}
              <div style={{
                padding: '20px 24px',
                borderBottom: '1px solid rgba(255, 255, 255, 0.08)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                background: isEscalated ? 'rgba(255, 80, 60, 0.05)' : 'transparent',
              }}>
                <div>
                  <div style={{ 
                    fontSize: 16, 
                    fontWeight: 700, 
                    color: isEscalated ? 'rgba(255, 120, 100, 1)' : '#fff', 
                    marginBottom: 4,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 8,
                  }}>
                    {isEscalated ? 'Escalated Report' : 'Pending Report'}
                    {isEscalated && (
                      <span style={{
                        fontSize: 9,
                        fontWeight: 700,
                        background: 'rgba(255, 80, 60, 0.2)',
                        color: 'rgba(255, 100, 80, 1)',
                        padding: '2px 6px',
                        borderRadius: 3,
                        textTransform: 'uppercase',
                      }}>
                        ESCALATED
                      </span>
                    )}
                  </div>
                  <div style={{ fontSize: 11, color: 'rgba(255, 255, 255, 0.4)', fontFamily: 'monospace' }}>
                    #{activeReport.report_id.slice(0, 12)}
                  </div>
                </div>
                <button
                  onClick={closeReportDrawer}
                  style={{
                    background: 'rgba(255, 255, 255, 0.05)',
                    border: 'none',
                    borderRadius: 6,
                    color: 'rgba(255, 255, 255, 0.6)',
                    width: 32,
                    height: 32,
                    cursor: 'pointer',
                    fontSize: 18,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  ×
                </button>
              </div>

              {/* Content */}
              <div style={{ flex: 1, overflowY: 'auto', padding: '20px 24px' }}>
                {/* Reason */}
                <div style={{ marginBottom: 20 }}>
                  <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                    Reason
                  </div>
                  <div style={{
                    fontSize: 14,
                    fontWeight: 600,
                    color: '#fff',
                    background: isEscalated ? 'rgba(255, 80, 60, 0.1)' : 'rgba(255, 180, 80, 0.1)',
                    border: isEscalated ? '1px solid rgba(255, 80, 60, 0.2)' : '1px solid rgba(255, 180, 80, 0.2)',
                    borderRadius: 6,
                    padding: '10px 14px',
                  }}>
                    {activeReport.reason}
                  </div>
                </div>

                {/* Location */}
                <div style={{ marginBottom: 20 }}>
                  <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                    Location
                  </div>
                  <div style={{
                    fontSize: 13,
                    color: 'rgba(255, 255, 255, 0.7)',
                    background: 'rgba(255, 255, 255, 0.03)',
                    borderRadius: 6,
                    padding: '10px 14px',
                  }}>
                    {buildLocationLabel(
                      activeReport.region,
                      activeReport.country_code,
                      activeReport.city_code
                    )}
                  </div>
                </div>

                {/* Age */}
                <div style={{ marginBottom: 20 }}>
                  <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                    Open for
                  </div>
                  <div style={{
                    fontSize: 14,
                    fontWeight: 600,
                    color: activeReport.hours_open > 48 
                      ? 'rgba(255, 100, 80, 1)' 
                      : activeReport.hours_open > 24 
                        ? 'rgba(255, 180, 80, 0.9)' 
                        : 'rgba(255, 255, 255, 0.7)',
                    background: activeReport.hours_open > 48 
                      ? 'rgba(255, 100, 80, 0.12)' 
                      : activeReport.hours_open > 24 
                        ? 'rgba(255, 180, 80, 0.08)' 
                        : 'rgba(255, 255, 255, 0.03)',
                    borderRadius: 6,
                    padding: '10px 14px',
                  }}>
                    {formatHoursOpen(activeReport.hours_open)}
                  </div>
                </div>

                {/* Created at */}
                {activeReport.created_at && (
                  <div style={{ marginBottom: 20 }}>
                    <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                      Reported at
                    </div>
                    <div style={{
                      fontSize: 12,
                      color: 'rgba(255, 255, 255, 0.5)',
                      background: 'rgba(255, 255, 255, 0.03)',
                      borderRadius: 6,
                      padding: '10px 14px',
                    }}>
                      {new Date(activeReport.created_at).toLocaleString()}
                    </div>
                  </div>
                )}
              </div>

            {/* Action Buttons */}
            <div style={{
              padding: '20px 24px',
              borderTop: '1px solid rgba(255, 255, 255, 0.08)',
              background: 'rgba(0, 0, 0, 0.2)',
            }}>
              <div style={{ fontSize: 10, color: 'rgba(255, 255, 255, 0.4)', marginBottom: 12, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                Take Action
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                {/* Hide */}
                <button
                  onClick={() => handleDrawerAction('HIDE_CONFESSION')}
                  disabled={drawerActionLoading}
                  style={{
                    background: 'rgba(255, 80, 80, 0.12)',
                    border: '1px solid rgba(255, 80, 80, 0.3)',
                    borderRadius: 8,
                    padding: '12px 16px',
                    color: 'rgba(255, 100, 100, 0.95)',
                    fontWeight: 600,
                    fontSize: 12,
                    cursor: drawerActionLoading ? 'wait' : 'pointer',
                    opacity: drawerActionLoading ? 0.5 : 1,
                    transition: 'all 0.15s ease',
                  }}
                >
                  {drawerActionLoading ? '…' : 'Hide'}
                </button>
                {/* Dismiss */}
                <button
                  onClick={() => handleDrawerAction('DISMISS_REPORT')}
                  disabled={drawerActionLoading}
                  style={{
                    background: 'rgba(255, 255, 255, 0.05)',
                    border: '1px solid rgba(255, 255, 255, 0.15)',
                    borderRadius: 8,
                    padding: '12px 16px',
                    color: 'rgba(255, 255, 255, 0.8)',
                    fontWeight: 600,
                    fontSize: 12,
                    cursor: drawerActionLoading ? 'wait' : 'pointer',
                    opacity: drawerActionLoading ? 0.5 : 1,
                    transition: 'all 0.15s ease',
                  }}
                >
                  {drawerActionLoading ? '…' : 'Dismiss'}
                </button>
                {/* Escalate */}
                <button
                  onClick={() => handleDrawerAction('ESCALATE')}
                  disabled={drawerActionLoading}
                  style={{
                    background: 'rgba(255, 180, 80, 0.12)',
                    border: '1px solid rgba(255, 180, 80, 0.3)',
                    borderRadius: 8,
                    padding: '12px 16px',
                    color: 'rgba(255, 180, 80, 0.95)',
                    fontWeight: 600,
                    fontSize: 12,
                    cursor: drawerActionLoading ? 'wait' : 'pointer',
                    opacity: drawerActionLoading ? 0.5 : 1,
                    transition: 'all 0.15s ease',
                  }}
                >
                  {drawerActionLoading ? '…' : 'Escalate'}
                </button>
                {/* Handled */}
                <button
                  onClick={() => handleDrawerAction('MARK_HANDLED')}
                  disabled={drawerActionLoading}
                  style={{
                    background: 'rgba(100, 200, 150, 0.12)',
                    border: '1px solid rgba(100, 200, 150, 0.3)',
                    borderRadius: 8,
                    padding: '12px 16px',
                    color: 'rgba(100, 200, 150, 0.95)',
                    fontWeight: 600,
                    fontSize: 12,
                    cursor: drawerActionLoading ? 'wait' : 'pointer',
                    opacity: drawerActionLoading ? 0.5 : 1,
                    transition: 'all 0.15s ease',
                  }}
                >
                  {drawerActionLoading ? '…' : 'Handled'}
                </button>
              </div>
              <div style={{ 
                marginTop: 12, 
                fontSize: 10, 
                color: 'rgba(255, 255, 255, 0.3)', 
                textAlign: 'center' 
              }}>
                Action will be logged and report updated
              </div>
            </div>
          </div>
        </>
        );
      })()}
    </div>
  );
}
