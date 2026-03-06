import { createContext, useContext, useState, useCallback, useMemo, type ReactNode } from 'react';

// =============================================================================
// TYPES
// =============================================================================

export type InsightsMode = 'world' | 'near' | 'somewhere' | null;
export type InsightsDays = 1 | 7 | 30 | 90 | 180 | 365;

export interface InsightsFilters {
  country_code: string | null;
  region: string | null;
  city_code: string | null;
  mode: InsightsMode;
  days: InsightsDays;
  activeDay: string; // YYYY-MM-DD
}

/**
 * InsightsWindow: The single source of truth for time range across all Insights.
 * 
 * - activeDay: The day we're "standing on" (YYYY-MM-DD)
 * - days: Number of days to include (1, 7, or 30)
 * - startUtcIso: Start of window (00:00:00Z of activeDay - (days-1))
 * - endUtcIso: End of window (00:00:00Z of activeDay + 1, exclusive)
 * 
 * Example: activeDay=2026-02-04, days=7
 *   → startUtcIso = 2026-01-29T00:00:00.000Z
 *   → endUtcIso   = 2026-02-05T00:00:00.000Z (exclusive)
 *   → Covers 7 full days: Jan 29, 30, 31, Feb 1, 2, 3, 4
 */
export interface InsightsWindow {
  activeDay: string;
  days: InsightsDays;
  startUtcIso: string;
  endUtcIso: string;
}

// =============================================================================
// HELPERS
// =============================================================================

/**
 * Get today's date as YYYY-MM-DD in UTC
 */
function getTodayUtc(): string {
  return new Date().toISOString().split('T')[0];
}

/**
 * Build an InsightsWindow from activeDay and days
 */
export function buildWindow(activeDay: string, days: InsightsDays): InsightsWindow {
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

/**
 * Format window for display in UI
 * Examples:
 *   days=1: "2026-02-04"
 *   days=7: "7 days ending 2026-02-04"
 *   days=30: "30 days ending 2026-02-04"
 */
export function formatWindow(window: InsightsWindow): string {
  if (window.days === 1) {
    return window.activeDay;
  }
  return `${window.days} days ending ${window.activeDay}`;
}

/**
 * Format lens (geo filters) for display
 */
export function formatLens(filters: InsightsFilters): string {
  const parts = [
    filters.region,
    filters.country_code,
    filters.city_code,
    filters.mode,
  ].filter(Boolean);
  
  return parts.length > 0 ? parts.join(' · ') : 'Global';
}

// =============================================================================
// CONTEXT
// =============================================================================

interface InsightsContextValue {
  filters: InsightsFilters;
  window: InsightsWindow;
  applyFilters: (newFilters: Partial<InsightsFilters>) => void;
  resetFilters: () => void;
  /** Formatted lens string for UI */
  lensLabel: string;
  /** Formatted window string for UI */
  windowLabel: string;
}

const DEFAULT_FILTERS: InsightsFilters = {
  country_code: null,
  region: null,
  city_code: null,
  mode: null,
  days: 7,
  activeDay: getTodayUtc(),
};

const InsightsContext = createContext<InsightsContextValue | null>(null);

export function InsightsProvider({ children }: { children: ReactNode }) {
  const [filters, setFilters] = useState<InsightsFilters>(DEFAULT_FILTERS);

  // Compute window from filters
  const window = useMemo(
    () => buildWindow(filters.activeDay, filters.days),
    [filters.activeDay, filters.days]
  );

  // Compute labels
  const lensLabel = useMemo(() => formatLens(filters), [filters]);
  const windowLabel = useMemo(() => formatWindow(window), [window]);

  const applyFilters = useCallback((newFilters: Partial<InsightsFilters>) => {
    setFilters(prev => ({ ...prev, ...newFilters }));
  }, []);

  const resetFilters = useCallback(() => {
    setFilters({ ...DEFAULT_FILTERS, activeDay: getTodayUtc() });
  }, []);

  return (
    <InsightsContext.Provider value={{ 
      filters, 
      window, 
      applyFilters, 
      resetFilters,
      lensLabel,
      windowLabel,
    }}>
      {children}
    </InsightsContext.Provider>
  );
}

export function useInsightsFilters(): InsightsContextValue {
  const ctx = useContext(InsightsContext);
  if (!ctx) {
    throw new Error('useInsightsFilters must be used within InsightsProvider');
  }
  return ctx;
}
