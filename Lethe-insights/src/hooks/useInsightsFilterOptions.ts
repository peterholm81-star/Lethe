import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import {
  buildCountryOptionsArgs,
  buildCityOptionsArgs,
  createLatestOnlyGuard,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';

interface UseFilterOptionsResult {
  options: string[];
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

interface CountryRow {
  country_code: string;
}

interface RegionRow {
  region: string;
}

interface CityRow {
  city_code: string;
}

/**
 * Fetch distinct country_code values from event_logs
 * Optionally filtered by region for cascading filters
 */
export function useCountryOptions(region?: string | null): UseFilterOptionsResult {
  const [options, setOptions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchOptions = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    const args = buildCountryOptionsArgs(region);

    try {
      const { data, error: rpcError } = await supabase.rpc('get_insights_country_options', args);

      if (guardRef.current.warnIfStale(reqId, 'FILTER_OPTIONS')) {
        return;
      }

      if (rpcError) throw rpcError;

      const values = ((data as CountryRow[]) || []).map((row) => row.country_code);
      setOptions(values);
      setLoading(false);

    } catch (err) {
      if (!guardRef.current.isLatest(reqId)) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to fetch country options';
      setError(message);
      setOptions([]);
      setLoading(false);
    }
  }, [region]);

  useEffect(() => {
    fetchOptions();
  }, [fetchOptions]);

  return { options, loading, error, refetch: fetchOptions };
}

/**
 * Fetch distinct region values from event_logs
 */
export function useRegionOptions(): UseFilterOptionsResult {
  const [options, setOptions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchOptions = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    try {
      const { data, error: rpcError } = await supabase.rpc('get_insights_region_options');

      if (guardRef.current.warnIfStale(reqId, 'FILTER_OPTIONS')) {
        return;
      }

      if (rpcError) throw rpcError;

      const values = ((data as RegionRow[]) || []).map((row) => row.region);
      setOptions(values);
      setLoading(false);

    } catch (err) {
      if (!guardRef.current.isLatest(reqId)) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to fetch region options';
      setError(message);
      setOptions([]);
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchOptions();
  }, [fetchOptions]);

  return { options, loading, error, refetch: fetchOptions };
}

/**
 * Fetch distinct city_code values from event_logs
 * Optionally filtered by country_code and/or region
 */
export function useCityOptions(
  countryCode?: string | null,
  region?: string | null
): UseFilterOptionsResult {
  const [options, setOptions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  const fetchOptions = useCallback(async () => {
    const reqId = guardRef.current.nextRequestId();

    setLoading(true);
    setError(null);

    const args = buildCityOptionsArgs(countryCode, region);

    try {
      const { data, error: rpcError } = await supabase.rpc('get_insights_city_options', args);

      if (guardRef.current.warnIfStale(reqId, 'FILTER_OPTIONS')) {
        return;
      }

      if (rpcError) throw rpcError;

      const values = ((data as CityRow[]) || []).map((row) => row.city_code);
      setOptions(values);
      setLoading(false);

    } catch (err) {
      if (!guardRef.current.isLatest(reqId)) {
        return;
      }

      const message = err instanceof Error ? err.message : 'Failed to fetch city options';
      setError(message);
      setOptions([]);
      setLoading(false);
    }
  }, [countryCode, region]);

  useEffect(() => {
    fetchOptions();
  }, [fetchOptions]);

  return { options, loading, error, refetch: fetchOptions };
}
