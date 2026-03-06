import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import type { TrendScope } from './useTrendsV1';

// =============================================================================
// TYPES
// =============================================================================

export interface YearWheelMonth {
  monthStart: string;
  sessions: number;
  posts: number;
  postsPerSession: number | null;
  moodPos: number;
  moodNeg: number;
  moodBalance: number | null;
}

export interface UseYearWheelV1Result {
  data: YearWheelMonth[];
  loading: boolean;
  error: string | null;
}

// =============================================================================
// INTERNALS
// =============================================================================

function scopeStableKey(s: TrendScope): string {
  if (s.type === 'global') return 'global';
  if (s.type === 'region') return `region:${s.region}`;
  return `country:${s.country}`;
}

function scopeToRpcParams(s: TrendScope): {
  p_scope: string;
  p_region: string | null;
  p_country: string | null;
  p_city: string | null;
} {
  if (s.type === 'region') return { p_scope: 'region', p_region: s.region, p_country: null, p_city: null };
  if (s.type === 'country') return { p_scope: 'country', p_region: null, p_country: s.country, p_city: null };
  return { p_scope: 'global', p_region: null, p_country: null, p_city: null };
}

function normalize(rows: Record<string, unknown>[]): YearWheelMonth[] {
  return (rows ?? []).map(r => ({
    monthStart: String(r.month_start ?? ''),
    sessions: Number(r.sessions ?? 0),
    posts: Number(r.posts ?? 0),
    postsPerSession: r.posts_per_session != null ? Number(r.posts_per_session) : null,
    moodPos: Number(r.mood_pos ?? 0),
    moodNeg: Number(r.mood_neg ?? 0),
    moodBalance: r.mood_balance != null ? Number(r.mood_balance) : null,
  }));
}

// =============================================================================
// HOOK
// =============================================================================

export function useYearWheelV1(scope: TrendScope): UseYearWheelV1Result {
  const [data, setData] = useState<YearWheelMonth[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const reqId = useRef(0);

  const stableKey = useMemo(() => scopeStableKey(scope), [
    scope.type,
    scope.type === 'region' ? scope.region : '',
    scope.type === 'country' ? scope.country : '',
  ]);

  const doFetch = useCallback(async () => {
    const id = ++reqId.current;
    setLoading(true);
    setError(null);

    const endDate = new Date().toISOString().slice(0, 10);

    try {
      const res = await supabase.rpc('get_year_wheel_v1', {
        ...scopeToRpcParams(scope),
        p_days: 365,
        p_end_date: endDate,
      });

      if (id !== reqId.current) return;
      if (res.error) throw res.error;

      setData(normalize(res.data ?? []));
    } catch (err: unknown) {
      if (id !== reqId.current) return;
      const e = err as Record<string, unknown> | null;
      const msg = (e && typeof e.message === 'string') ? e.message : String(err);
      setError(msg);
      setData([]);
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stableKey]);

  useEffect(() => { doFetch(); }, [doFetch]);

  return { data, loading, error };
}
