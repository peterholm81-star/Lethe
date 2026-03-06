import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import type { TrendScope, TrendComparisonRow } from './useTrendsV1';

// =============================================================================
// TYPES
// =============================================================================

export interface ComparisonData {
  rows: TrendComparisonRow[];
}

export interface ScopeSummary {
  d7: ComparisonData | null;
  d30: ComparisonData | null;
}

export interface UseTrendsSummaryV1Result {
  loading: boolean;
  error: string | null;
  a: ScopeSummary;
  b: ScopeSummary | null;
}

// =============================================================================
// INTERNALS
// =============================================================================

function scopeToRegion(s: TrendScope): string | null {
  if (s.type === 'region') return s.region;
  return null;
}

function scopeStableKey(s: TrendScope | null): string {
  if (!s) return '';
  if (s.type === 'global') return 'global';
  if (s.type === 'region') return `region:${s.region}`;
  return `country:${s.country}`;
}

function normalizeRows(raw: Record<string, unknown>[]): TrendComparisonRow[] {
  return (raw ?? []).map(r => ({
    scopeKey: String(r.scope_key ?? ''),
    metricKey: String(r.metric_key ?? ''),
    current: Number(r.current_value ?? 0),
    previous: Number(r.previous_value ?? 0),
    deltaAbs: Number(r.delta_abs ?? 0),
    deltaPct: r.delta_pct != null ? Number(r.delta_pct) : null,
  }));
}

async function fetchComparison(
  scope: TrendScope,
  days: number,
  endDate: string,
): Promise<ComparisonData | null> {
  const regionArg = scopeToRegion(scope);
  const rpcScope = scope.type === 'country' ? 'country' : 'global';

  const res = await supabase.rpc('get_trends_comparison_v1', {
    p_scope: rpcScope,
    p_region: regionArg,
    p_days: days,
    p_end_date: endDate,
  });

  if (res.error) throw res.error;

  let rows = normalizeRows(res.data ?? []);

  if (scope.type === 'country') {
    rows = rows.filter(r => r.scopeKey === scope.country.toUpperCase());
  }

  return { rows };
}

async function fetchScopeSummary(
  scope: TrendScope,
  endDate: string,
): Promise<ScopeSummary> {
  const [d7, d30] = await Promise.all([
    fetchComparison(scope, 7, endDate).catch(() => null),
    fetchComparison(scope, 30, endDate).catch(() => null),
  ]);
  return { d7, d30 };
}

// =============================================================================
// HOOK
// =============================================================================

export function useTrendsSummaryV1(
  scopeA: TrendScope,
  scopeB: TrendScope | null = null,
): UseTrendsSummaryV1Result {
  const [a, setA] = useState<ScopeSummary>({ d7: null, d30: null });
  const [b, setB] = useState<ScopeSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const reqId = useRef(0);

  const keyA = useMemo(() => scopeStableKey(scopeA), [
    scopeA.type,
    scopeA.type === 'region' ? scopeA.region : '',
    scopeA.type === 'country' ? scopeA.country : '',
  ]);
  const keyB = useMemo(() => scopeStableKey(scopeB), [
    scopeB?.type,
    scopeB?.type === 'region' ? scopeB.region : '',
    scopeB?.type === 'country' ? scopeB.country : '',
  ]);

  const doFetch = useCallback(async () => {
    const id = ++reqId.current;
    setLoading(true);
    setError(null);

    const endDate = new Date().toISOString().slice(0, 10);

    try {
      const [resA, resB] = await Promise.all([
        fetchScopeSummary(scopeA, endDate),
        scopeB ? fetchScopeSummary(scopeB, endDate) : Promise.resolve(null),
      ]);

      if (id !== reqId.current) return;
      setA(resA);
      setB(resB);
    } catch (err: unknown) {
      if (id !== reqId.current) return;
      const e = err as Record<string, unknown> | null;
      const msg = (e && typeof e.message === 'string') ? e.message : String(err);
      setError(msg);
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [keyA, keyB]);

  useEffect(() => { doFetch(); }, [doFetch]);

  return { loading, error, a, b };
}
