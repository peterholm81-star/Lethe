import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { supabase } from '../lib/supabase';

// =============================================================================
// TYPES
// =============================================================================

export interface TrendComparisonRow {
  scopeKey: string;
  metricKey: string;
  current: number;
  previous: number;
  deltaAbs: number;
  deltaPct: number | null;
}

export interface TrendlinePoint {
  day: string;
  metricKey: string;
  value: number;
}

export interface TrendScopeData {
  global: TrendComparisonRow[];
  countries: TrendComparisonRow[];
  trendline: TrendlinePoint[];
}

export type TrendScope = {
  type: 'global';
} | {
  type: 'region';
  region: string;
} | {
  type: 'country';
  country: string;
};

export interface UseTrendsV1Result {
  a: TrendScopeData;
  b: TrendScopeData | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

function scopeKey(s: TrendScope | null): string {
  if (!s) return '';
  if (s.type === 'global') return 'global';
  if (s.type === 'region') return `region:${s.region}`;
  return `country:${s.country}`;
}

// =============================================================================
// INTERNALS
// =============================================================================

function scopeToRegion(s: TrendScope): string | null {
  if (s.type === 'region') return s.region;
  return null;
}

function normalizeRows(rows: Record<string, unknown>[]): TrendComparisonRow[] {
  return (rows ?? []).map(r => ({
    scopeKey: String(r.scope_key ?? ''),
    metricKey: String(r.metric_key ?? ''),
    current: Number(r.current_value ?? 0),
    previous: Number(r.previous_value ?? 0),
    deltaAbs: Number(r.delta_abs ?? 0),
    deltaPct: r.delta_pct != null ? Number(r.delta_pct) : null,
  }));
}

function normalizeTrendline(rows: Record<string, unknown>[]): TrendlinePoint[] {
  return (rows ?? []).map(r => ({
    day: String(r.day ?? ''),
    metricKey: String(r.metric_key ?? ''),
    value: Number(r.value ?? 0),
  }));
}

async function fetchScope(
  days: number,
  endDate: string,
  scope: TrendScope,
): Promise<TrendScopeData> {
  const regionArg = scopeToRegion(scope);

  const [globalRes, countryRes, trendRes] = await Promise.all([
    supabase.rpc('get_trends_comparison_v1', {
      p_scope: scope.type === 'country' ? 'country' : 'global',
      p_region: regionArg,
      p_days: days,
      p_end_date: endDate,
    }),
    supabase.rpc('get_trends_comparison_v1', {
      p_scope: 'country',
      p_region: regionArg,
      p_days: days,
      p_end_date: endDate,
    }),
    supabase.rpc('get_trends_trendline_v1', {
      p_region: regionArg,
      p_days: days,
      p_end_date: endDate,
    }),
  ]);

  if (globalRes.error) throw globalRes.error;
  if (countryRes.error) throw countryRes.error;
  if (trendRes.error) throw trendRes.error;

  let global = normalizeRows(globalRes.data ?? []);
  const countries = normalizeRows(countryRes.data ?? []);

  // For single-country scope, pull that country's rows as "global" summary
  if (scope.type === 'country') {
    global = countries.filter(r => r.scopeKey === scope.country.toUpperCase());
  }

  return {
    global,
    countries,
    trendline: normalizeTrendline(trendRes.data ?? []),
  };
}

// =============================================================================
// HOOK
// =============================================================================

export function useTrendsV1(
  days: number = 7,
  scopeA: TrendScope = { type: 'global' },
  scopeB: TrendScope | null = null,
): UseTrendsV1Result {
  const [a, setA] = useState<TrendScopeData>({ global: [], countries: [], trendline: [] });
  const [b, setB] = useState<TrendScopeData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const reqId = useRef(0);

  // Stable dependency strings so useCallback doesn't fire on every render
  const keyA = useMemo(() => scopeKey(scopeA), [scopeA.type, scopeA.type === 'region' ? scopeA.region : '', scopeA.type === 'country' ? scopeA.country : '']);
  const keyB = useMemo(() => scopeKey(scopeB), [scopeB?.type, scopeB?.type === 'region' ? scopeB.region : '', scopeB?.type === 'country' ? scopeB.country : '']);

  const doFetch = useCallback(async () => {
    const id = ++reqId.current;
    setLoading(true);
    setError(null);

    const endDate = new Date().toISOString().slice(0, 10);

    try {
      const promises: [Promise<TrendScopeData>, Promise<TrendScopeData | null>] = [
        fetchScope(days, endDate, scopeA),
        scopeB ? fetchScope(days, endDate, scopeB) : Promise.resolve(null),
      ];

      const [resA, resB] = await Promise.all(promises);

      if (id !== reqId.current) return;

      setA(resA);
      setB(resB);
    } catch (err: unknown) {
      if (id !== reqId.current) return;
      const e = err as Record<string, unknown> | null;
      const msg = (e && typeof e.message === 'string') ? e.message : String(err);
      setError(msg);
      setA({ global: [], countries: [], trendline: [] });
      setB(null);
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [days, keyA, keyB]);

  useEffect(() => { doFetch(); }, [doFetch]);

  return { a, b, loading, error, refetch: doFetch };
}
