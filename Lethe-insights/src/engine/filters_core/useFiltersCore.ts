import { useContext } from 'react';
import { FiltersCoreContext } from './FiltersCoreProvider';

// =============================================================================
// TYPES
// =============================================================================

export type TimeRange = '7d' | '30d' | '90d' | '180d' | '365d';

export interface FiltersCoreState {
  timeRange: TimeRange;
  region: string | null;
  country: string | null;
  city: string | null;
  compareToPrevious: boolean;
}

export interface FiltersCoreActions {
  setTimeRange: (timeRange: TimeRange) => void;
  setRegion: (region: string | null) => void;
  setCountry: (country: string | null) => void;
  setCity: (city: string | null) => void;
  setCompareToPrevious: (compare: boolean) => void;
  resetFilters: () => void;
}

export interface FiltersCoreResult extends FiltersCoreActions {
  filters: FiltersCoreState;
}

// =============================================================================
// HOOK
// =============================================================================

export function useFiltersCore(): FiltersCoreResult {
  const context = useContext(FiltersCoreContext);
  
  if (!context) {
    throw new Error(
      'useFiltersCore must be used within a FiltersCoreProvider. ' +
      'Wrap your app or layout with <FiltersCoreProvider>.'
    );
  }
  
  return context;
}
