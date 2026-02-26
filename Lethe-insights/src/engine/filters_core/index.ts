// Insight Engine - Filters Core Module
// =====================================
// Reusable filter system with URL sync

export { useFiltersCore } from './useFiltersCore';
export type {
  TimeRange,
  FiltersCoreState,
  FiltersCoreActions,
  FiltersCoreResult,
} from './useFiltersCore';

export { FilterBarCore } from './FilterBarCore';
export type { FilterBarCoreProps, FilterOption } from './FilterBarCore';

// Compatibility adapter for legacy hooks
export { toLegacyFilters } from './compatAdapter';
export type { LegacyFiltersCompat } from './compatAdapter';
