import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';

// =============================================================================
// TYPES
// =============================================================================

export interface CountryOptActionSummaryRow {
  totalCountries: number;
  actionableCountries: number;
  incCount: number;
  decCount: number;
  holdCount: number;
  lowVolumeCount: number;
  highRiskCount: number;
  medRiskCount: number;
  topActions: string;
  actionBullets: string[];
  updatedAt: string | null;
}

export interface UseCountryOptActionSummaryResult {
  data: CountryOptActionSummaryRow | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// Raw row from DB
interface RawRow {
  total_countries?: number;
  actionable_countries?: number;
  inc_count?: number;
  dec_count?: number;
  hold_count?: number;
  low_volume_count?: number;
  high_risk_count?: number;
  med_risk_count?: number;
  top_actions?: string;
  action_bullets?: string[];
  updated_at?: string;
}

function normalize(r: RawRow): CountryOptActionSummaryRow {
  return {
    totalCountries: r.total_countries ?? 0,
    actionableCountries: r.actionable_countries ?? 0,
    incCount: r.inc_count ?? 0,
    decCount: r.dec_count ?? 0,
    holdCount: r.hold_count ?? 0,
    lowVolumeCount: r.low_volume_count ?? 0,
    highRiskCount: r.high_risk_count ?? 0,
    medRiskCount: r.med_risk_count ?? 0,
    topActions: r.top_actions ?? 'No data yet.',
    actionBullets: Array.isArray(r.action_bullets) ? r.action_bullets : [],
    updatedAt: r.updated_at ?? null,
  };
}

// =============================================================================
// HOOK
// =============================================================================

export function useCountryOptimizationActionSummary(): UseCountryOptActionSummaryResult {
  const [data, setData] = useState<CountryOptActionSummaryRow | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const { data: rows, error: queryError } = await supabase
        .from('country_optimization_action_summary_30d')
        .select('*')
        .limit(1);

      if (queryError) throw queryError;

      const row = rows?.[0] as RawRow | undefined;
      setData(row ? normalize(row) : null);
      setLoading(false);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load action summary';

      if (message.includes('does not exist') || message.includes('relation')) {
        if (import.meta.env.DEV) {
          console.warn('[action-summary] View not found — showing empty state');
        }
        setData(null);
        setError(null);
      } else {
        if (import.meta.env.DEV) {
          console.error('[action-summary] Error:', err);
        }
        setError(message);
      }

      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data, loading, error, refetch: fetchData };
}
