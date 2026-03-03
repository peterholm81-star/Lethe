import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';

// =============================================================================
// TYPES — Normalized row used by UI
// =============================================================================

export interface CountryOptRow {
  countryCode: string;
  ads30d: number | null;
  continueRate: number | null;
  dropRate: number | null;
  depth: number | null;
  confidence: 'HIGH' | 'MED' | 'LOW' | null;
  signal: 'INCREASE' | 'DECREASE' | 'HOLD' | null;
  currentCap: number | null;
  currentTrigger: number | null;
  currentEnabled: boolean | null;
  recommendedCap: number | null;
  recommendedTrigger: number | null;
  policySource: 'override' | 'default' | null;
  frictionRiskScore: number | null;
  frictionRiskLevel: 'LOW' | 'MED' | 'HIGH' | 'LOW_VOLUME' | null;
  frictionRiskReason: string | null;
  sessions30d: number | null;
  updatedAt: string | null;
}

export interface UseCountryOptimizationV1Result {
  data: CountryOptRow[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

// =============================================================================
// NORMALIZER — raw DB row -> CountryOptRow
// =============================================================================

// Raw row as it may come from DB (handles slight naming differences)
interface RawRow {
  country_code?: string;
  total_ads_30d?: number;
  continue_rate_30d?: number;
  drop_rate_30d?: number;
  median_fetches_after_ad_30d?: number;
  depth?: number;
  confidence?: string;
  signal?: string;
  recommendation?: string;
  current_cap?: number;
  ads_per_session_cap?: number;
  current_trigger?: number;
  trigger_pages?: number;
  current_enabled?: boolean;
  enabled?: boolean;
  recommended_cap?: number;
  recommended_ads_per_session_cap?: number;
  recommended_trigger?: number;
  recommended_trigger_pages?: number;
  policy_source?: string;
  source?: string;
  friction_risk_score?: number;
  friction_risk_level?: string;
  friction_risk_reason?: string;
  sessions_30d?: number;
  updated_at?: string;
}

function normalize(r: RawRow): CountryOptRow {
  return {
    countryCode: r.country_code ?? '',
    ads30d: r.total_ads_30d ?? null,
    continueRate: r.continue_rate_30d ?? null,
    dropRate: r.drop_rate_30d ?? null,
    depth: r.median_fetches_after_ad_30d ?? r.depth ?? null,
    confidence: (['HIGH', 'MED', 'LOW'].includes(r.confidence ?? '')
      ? r.confidence as 'HIGH' | 'MED' | 'LOW'
      : null),
    signal: (['INCREASE', 'DECREASE', 'HOLD'].includes(r.signal ?? r.recommendation ?? '')
      ? (r.signal ?? r.recommendation) as 'INCREASE' | 'DECREASE' | 'HOLD'
      : null),
    currentCap: r.current_cap ?? r.ads_per_session_cap ?? null,
    currentTrigger: r.current_trigger ?? r.trigger_pages ?? null,
    currentEnabled: r.current_enabled ?? r.enabled ?? null,
    recommendedCap: r.recommended_cap ?? r.recommended_ads_per_session_cap ?? null,
    recommendedTrigger: r.recommended_trigger ?? r.recommended_trigger_pages ?? null,
    policySource: (['override', 'default'].includes(r.policy_source ?? r.source ?? '')
      ? (r.policy_source ?? r.source) as 'override' | 'default'
      : null),
    frictionRiskScore: r.friction_risk_score ?? null,
    frictionRiskLevel: (['LOW', 'MED', 'HIGH', 'LOW_VOLUME'].includes(r.friction_risk_level ?? '')
      ? r.friction_risk_level as 'LOW' | 'MED' | 'HIGH' | 'LOW_VOLUME'
      : null),
    frictionRiskReason: r.friction_risk_reason ?? null,
    sessions30d: r.sessions_30d ?? null,
    updatedAt: r.updated_at ?? null,
  };
}

// =============================================================================
// HOOK
// =============================================================================

/**
 * Unified hook for the country_optimization_v1 Supabase view.
 * Normalizes column names so the UI doesn't care about exact DB naming.
 */
export function useCountryOptimizationV1(): UseCountryOptimizationV1Result {
  const [data, setData] = useState<CountryOptRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const { data: rows, error: queryError } = await supabase
        .from('country_optimization_v1')
        .select('*')
        .order('total_ads_30d', { ascending: false });

      if (queryError) throw queryError;

      const normalized = (rows ?? []).map(r => normalize(r as RawRow));

      if (import.meta.env.DEV) {
        console.log('[country-opt-v1] Fetched rows:', normalized.length);
      }

      setData(normalized);
      setLoading(false);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load optimization data';

      if (message.includes('does not exist') || message.includes('relation')) {
        if (import.meta.env.DEV) {
          console.warn('[country-opt-v1] View not found — showing empty state');
        }
        setData([]);
        setError(null);
      } else {
        if (import.meta.env.DEV) {
          console.error('[country-opt-v1] Error:', err);
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
