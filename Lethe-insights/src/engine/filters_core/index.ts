// Insight Engine - Filters Core Module
// =====================================
// Reusable filter system with URL sync

// Hook and types
export { useFiltersCore } from './useFiltersCore';
export type {
  TimeRange,
  FiltersCoreState,
  FiltersCoreActions,
  FiltersCoreResult,
} from './useFiltersCore';

// Provider (JSX component)
export { FiltersCoreProvider, FiltersCoreContext } from './FiltersCoreProvider';
export type { FiltersCoreProviderProps } from './FiltersCoreProvider';

// UI Component
export { FilterBarCore } from './FilterBarCore';
export type { FilterBarCoreProps, FilterOption } from './FilterBarCore';

// Compatibility adapter for legacy hooks
export { toLegacyFilters } from './compatAdapter';
export type { LegacyFiltersCompat } from './compatAdapter';
