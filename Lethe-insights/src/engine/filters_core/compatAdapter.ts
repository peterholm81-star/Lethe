/**
 * Compatibility Adapter for Insight Engine Filters
 * 
 * Converts the new FiltersCoreState format to the legacy InsightsFilters/InsightsWindow
 * format used by existing hooks like useEngagementFlow.
 * 
 * This allows gradual migration without breaking existing data hooks.
 */

import type { FiltersCoreState, TimeRange } from './useFiltersCore';
import type { InsightsFilters, InsightsWindow, InsightsDays } from '../../contexts/InsightsContext';

// =============================================================================
// HELPERS
// =============================================================================

function getTodayUtc(): string {
  return new Date().toISOString().split('T')[0];
}

function timeRangeToDays(timeRange: TimeRange): InsightsDays {
  switch (timeRange) {
    case '7d': return 7;
    case '30d': return 30;
    case '90d': return 90;
    case '180d': return 180;
    case '365d': return 365;
    default: return 7;
  }
}

function buildWindowFromTimeRange(timeRange: TimeRange): InsightsWindow {
  const activeDay = getTodayUtc();
  const days = timeRangeToDays(timeRange);

  // Parse activeDay as UTC date
  const activeDateUtc = new Date(activeDay + 'T00:00:00.000Z');
  
  // Start: activeDay - (days - 1) days at 00:00:00Z
  const startDate = new Date(activeDateUtc);
  startDate.setUTCDate(startDate.getUTCDate() - (days - 1));
  
  // End: activeDay + 1 day at 00:00:00Z (exclusive)
  const endDate = new Date(activeDateUtc);
  endDate.setUTCDate(endDate.getUTCDate() + 1);
  
  return {
    activeDay,
    days,
    startUtcIso: startDate.toISOString(),
    endUtcIso: endDate.toISOString(),
  };
}

// =============================================================================
// ADAPTER
// =============================================================================

export interface LegacyFiltersCompat {
  filters: InsightsFilters;
  window: InsightsWindow;
  lensLabel: string;
  windowLabel: string;
}

/**
 * Convert FiltersCoreState to legacy InsightsFilters + InsightsWindow format
 */
export function toLegacyFilters(coreFilters: FiltersCoreState): LegacyFiltersCompat {
  const days = timeRangeToDays(coreFilters.timeRange);
  const window = buildWindowFromTimeRange(coreFilters.timeRange);

  const filters: InsightsFilters = {
    country_code: coreFilters.country,
    region: coreFilters.region,
    city_code: coreFilters.city,
    mode: null, // New system doesn't use mode
    days: days,
    activeDay: window.activeDay,
  };

  // Build lens label
  let lensLabel = 'World';
  if (coreFilters.city) {
    lensLabel = coreFilters.city;
  } else if (coreFilters.country) {
    lensLabel = coreFilters.country;
  } else if (coreFilters.region) {
    lensLabel = coreFilters.region;
  }

  // Build window label
  const dayCount = timeRangeToDays(coreFilters.timeRange);
  const windowLabel = `Last ${dayCount} days`;

  return {
    filters,
    window,
    lensLabel,
    windowLabel,
  };
}
