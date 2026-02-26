import { useState, useCallback, useEffect, useMemo } from 'react';

// =============================================================================
// TYPES
// =============================================================================

export type TimeRange = '7d' | '30d';

export interface FiltersCoreState {
  timeRange: TimeRange;
  region: string | null;
  country: string | null;
  city: string | null;
}

export interface FiltersCoreActions {
  setTimeRange: (timeRange: TimeRange) => void;
  setRegion: (region: string | null) => void;
  setCountry: (country: string | null) => void;
  setCity: (city: string | null) => void;
  resetFilters: () => void;
}

export interface FiltersCoreResult extends FiltersCoreActions {
  filters: FiltersCoreState;
}

// =============================================================================
// URL PARAMETER HELPERS
// =============================================================================

const PARAM_KEYS = {
  timeRange: 'tr',
  region: 'r',
  country: 'c',
  city: 'ct',
} as const;

function getUrlParams(): URLSearchParams {
  if (typeof window === 'undefined') return new URLSearchParams();
  return new URLSearchParams(window.location.search);
}

function updateUrlParams(filters: FiltersCoreState): void {
  if (typeof window === 'undefined') return;

  const params = new URLSearchParams();

  if (filters.timeRange !== '7d') {
    params.set(PARAM_KEYS.timeRange, filters.timeRange);
  }
  if (filters.region) {
    params.set(PARAM_KEYS.region, filters.region);
  }
  if (filters.country) {
    params.set(PARAM_KEYS.country, filters.country);
  }
  if (filters.city) {
    params.set(PARAM_KEYS.city, filters.city);
  }

  const newUrl = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;

  window.history.replaceState({}, '', newUrl);
}

function parseUrlParams(): Partial<FiltersCoreState> {
  const params = getUrlParams();
  const result: Partial<FiltersCoreState> = {};

  const tr = params.get(PARAM_KEYS.timeRange);
  if (tr === '7d' || tr === '30d') {
    result.timeRange = tr;
  }

  const region = params.get(PARAM_KEYS.region);
  if (region) {
    result.region = region;
  }

  const country = params.get(PARAM_KEYS.country);
  if (country) {
    result.country = country;
  }

  const city = params.get(PARAM_KEYS.city);
  if (city) {
    result.city = city;
  }

  return result;
}

// =============================================================================
// DEFAULT STATE
// =============================================================================

const DEFAULT_FILTERS: FiltersCoreState = {
  timeRange: '7d',
  region: null,
  country: null,
  city: null,
};

// =============================================================================
// HOOK
// =============================================================================

export function useFiltersCore(): FiltersCoreResult {
  // Initialize state from URL or defaults
  const [filters, setFilters] = useState<FiltersCoreState>(() => {
    const urlParams = parseUrlParams();
    return {
      ...DEFAULT_FILTERS,
      ...urlParams,
    };
  });

  // Sync URL on filter changes
  useEffect(() => {
    updateUrlParams(filters);

    // Dev-only logging
    if (process.env.NODE_ENV === 'development') {
      console.log('[FiltersCore] State changed:', filters);
    }
  }, [filters]);

  // Set time range
  const setTimeRange = useCallback((timeRange: TimeRange) => {
    setFilters(prev => ({
      ...prev,
      timeRange,
    }));
  }, []);

  // Set region (cascades: resets country and city)
  const setRegion = useCallback((region: string | null) => {
    setFilters(prev => ({
      ...prev,
      region,
      country: null,
      city: null,
    }));
  }, []);

  // Set country (cascades: resets city)
  const setCountry = useCallback((country: string | null) => {
    setFilters(prev => ({
      ...prev,
      country,
      city: null,
    }));
  }, []);

  // Set city
  const setCity = useCallback((city: string | null) => {
    setFilters(prev => ({
      ...prev,
      city,
    }));
  }, []);

  // Reset all filters to defaults
  const resetFilters = useCallback(() => {
    setFilters(DEFAULT_FILTERS);
  }, []);

  return useMemo(() => ({
    filters,
    setTimeRange,
    setRegion,
    setCountry,
    setCity,
    resetFilters,
  }), [filters, setTimeRange, setRegion, setCountry, setCity, resetFilters]);
}
