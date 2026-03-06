import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import type { TrendScope } from './useTrendsV1';

// =============================================================================
// TYPES
// =============================================================================

export interface MoverRow {
  tag: string;
  current7d: number;
  baseline28d: number;
  deltaPct: number | null;
  status: 'rising' | 'falling' | 'emerging';
}

export interface UseTrendsMoversV1Result {
  rowsA: MoverRow[];
  rowsB: MoverRow[] | null;
  loading: boolean;
  error: string | null;
}

// =============================================================================
// INTERNALS
// =============================================================================

function scopeStableKey(s: TrendScope | null): string {
  if (!s) return '';
  if (s.type === 'global') return 'global';
  if (s.type === 'region') return `region:${s.region}`;
  return `country:${s.country}`;
}

function scopeToRpc(s: TrendScope) {
  if (s.type === 'region') return { p_scope: 'region', p_region: s.region, p_country: null, p_city: null };
  if (s.type === 'country') return { p_scope: 'country', p_region: null, p_country: s.country, p_city: null };
  return { p_scope: 'global', p_region: null, p_country: null, p_city: null };
}

function normalize(rows: Record<string, unknown>[]): MoverRow[] {
  return (rows ?? []).map(r => ({
    tag: String(r.tag ?? ''),
    current7d: Number(r.current_7d ?? 0),
    baseline28d: Number(r.baseline_28d ?? 0),
    deltaPct: r.delta_pct != null ? Number(r.delta_pct) : null,
    status: (['rising', 'falling', 'emerging'].includes(String(r.status))
      ? String(r.status)
      : 'falling') as MoverRow['status'],
  }));
}

async function fetchScope(scope: TrendScope, endDate: string): Promise<MoverRow[]> {
  const res = await supabase.rpc('get_trends_movers_v1', {
    ...scopeToRpc(scope),
    p_end_date: endDate,
  });
  if (res.error) throw res.error;
  return normalize(res.data ?? []);
}

// =============================================================================
// HOOK
// =============================================================================

export function useTrendsMoversV1(
  scopeA: TrendScope,
  scopeB: TrendScope | null = null,
): UseTrendsMoversV1Result {
  const [rowsA, setRowsA] = useState<MoverRow[]>([]);
  const [rowsB, setRowsB] = useState<MoverRow[] | null>(null);
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
      const [a, b] = await Promise.all([
        fetchScope(scopeA, endDate),
        scopeB ? fetchScope(scopeB, endDate) : Promise.resolve(null),
      ]);

      if (id !== reqId.current) return;
      setRowsA(a);
      setRowsB(b);
    } catch (err: unknown) {
      if (id !== reqId.current) return;
      const e = err as Record<string, unknown> | null;
      const msg = (e && typeof e.message === 'string') ? e.message : String(err);
      setError(msg);
      setRowsA([]);
      setRowsB(null);
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [keyA, keyB]);

  useEffect(() => { doFetch(); }, [doFetch]);

  return { rowsA, rowsB, loading, error };
}
