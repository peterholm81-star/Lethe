import { useState, useCallback, useEffect, useMemo, createContext, type ReactNode } from 'react';
import type { TimeRange, FiltersCoreState, FiltersCoreResult } from './useFiltersCore';

// =============================================================================
// DEBUG FLAG
// =============================================================================

/** Enable verbose FiltersCore logging (set to true to debug filter state changes) */
const DEBUG = false;

// =============================================================================
// URL PARAMETER HELPERS
// =============================================================================

const PARAM_KEYS = {
  timeRange: 'tr',
  region: 'r',
  country: 'c',
  city: 'ct',
  compare: 'cmp',
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
  if (filters.compareToPrevious) {
    params.set(PARAM_KEYS.compare, '1');
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

  const cmp = params.get(PARAM_KEYS.compare);
  if (cmp === '1') {
    result.compareToPrevious = true;
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
  compareToPrevious: false,
};

// =============================================================================
// CONTEXT
// =============================================================================

export const FiltersCoreContext = createContext<FiltersCoreResult | null>(null);

// =============================================================================
// PROVIDER PROPS
// =============================================================================

export interface FiltersCoreProviderProps {
  children: ReactNode;
}

// =============================================================================
// PROVIDER COMPONENT
// =============================================================================

export function FiltersCoreProvider({ children }: FiltersCoreProviderProps) {
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

    if (DEBUG && import.meta.env.DEV) {
      console.log('[FiltersCore] State changed:', filters);
    }
  }, [filters]);

  // Set time range
  const setTimeRange = useCallback((timeRange: TimeRange) => {
    if (DEBUG && import.meta.env.DEV) {
      console.log('[FiltersCore] setTimeRange:', timeRange);
    }
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

  // Set compare to previous
  const setCompareToPrevious = useCallback((compare: boolean) => {
    if (DEBUG && import.meta.env.DEV) {
      console.log('[FiltersCore] setCompareToPrevious:', compare);
    }
    setFilters(prev => ({
      ...prev,
      compareToPrevious: compare,
    }));
  }, []);

  // Reset all filters to defaults
  const resetFilters = useCallback(() => {
    setFilters(DEFAULT_FILTERS);
  }, []);

  const value = useMemo(() => ({
    filters,
    setTimeRange,
    setRegion,
    setCountry,
    setCity,
    setCompareToPrevious,
    resetFilters,
  }), [filters, setTimeRange, setRegion, setCountry, setCity, setCompareToPrevious, resetFilters]);

  return (
    <FiltersCoreContext.Provider value={value}>
      {children}
    </FiltersCoreContext.Provider>
  );
}
