import React from 'react';
import { useFiltersCore, type TimeRange } from './useFiltersCore';
import { SearchableDropdown } from '../../components/SearchableDropdown';

// =============================================================================
// TYPES
// =============================================================================

export interface FilterOption {
  value: string;
  label: string;
}

export interface FilterBarCoreProps {
  availableRegions?: FilterOption[];
  availableCountries?: FilterOption[];
  availableCities?: FilterOption[];
  enableCountry?: boolean;
  enableCity?: boolean;
  showReset?: boolean;
}

// =============================================================================
// STYLES (matching existing InsightsContextBar)
// =============================================================================

const styles = {
  bar: {
    display: 'flex',
    flexWrap: 'wrap' as const,
    alignItems: 'center',
    gap: '12px',
    padding: '12px 16px',
    background: 'rgba(255, 255, 255, 0.03)',
    borderRadius: '10px',
    marginBottom: '24px',
  } as React.CSSProperties,

  group: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  } as React.CSSProperties,

  label: {
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.06em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  select: {
    padding: '6px 10px',
    fontSize: '12px',
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '6px',
    color: 'rgba(255, 255, 255, 0.85)',
    outline: 'none',
    cursor: 'pointer',
  } as React.CSSProperties,

  spacer: {
    flex: 1,
    minWidth: '8px',
  } as React.CSSProperties,

  button: {
    padding: '6px 14px',
    fontSize: '11px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.85)',
    background: 'rgba(255, 255, 255, 0.08)',
    border: '1px solid rgba(255, 255, 255, 0.12)',
    borderRadius: '6px',
    cursor: 'pointer',
    transition: 'background 0.15s ease',
  } as React.CSSProperties,
};

// =============================================================================
// TIME RANGE OPTIONS
// =============================================================================

const TIME_RANGE_OPTIONS: { value: TimeRange; label: string }[] = [
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
];

// =============================================================================
// COMPONENT
// =============================================================================

export function FilterBarCore({
  availableRegions = [],
  availableCountries = [],
  availableCities = [],
  enableCountry = true,
  enableCity = true,
  showReset = true,
}: FilterBarCoreProps) {
  const {
    filters,
    setTimeRange,
    setRegion,
    setCountry,
    setCity,
    resetFilters,
  } = useFiltersCore();

  // Convert options for SearchableDropdown
  const regionOptions = [
    { value: '', label: 'All Regions' },
    ...availableRegions,
  ];

  const countryOptions = [
    { value: '', label: 'All Countries' },
    ...availableCountries,
  ];

  const cityOptions = [
    { value: '', label: 'All Cities' },
    ...availableCities,
  ];

  return (
    <div style={styles.bar}>
      {/* Time Range */}
      <div style={styles.group}>
        <span style={styles.label}>Time</span>
        <select
          style={styles.select}
          value={filters.timeRange}
          onChange={(e) => setTimeRange(e.target.value as TimeRange)}
        >
          {TIME_RANGE_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      </div>

      {/* Region */}
      <div style={styles.group}>
        <span style={styles.label}>Region</span>
        <SearchableDropdown
          options={regionOptions}
          value={filters.region ?? ''}
          onChange={(v) => setRegion(v || null)}
          placeholder="All Regions"
          width={120}
        />
      </div>

      {/* Country (optional) */}
      {enableCountry && (
        <div style={styles.group}>
          <span style={styles.label}>Country</span>
          <SearchableDropdown
            options={countryOptions}
            value={filters.country ?? ''}
            onChange={(v) => setCountry(v || null)}
            placeholder="All Countries"
            width={100}
            disabled={!filters.region}
          />
        </div>
      )}

      {/* City (optional) */}
      {enableCity && (
        <div style={styles.group}>
          <span style={styles.label}>City</span>
          <SearchableDropdown
            options={cityOptions}
            value={filters.city ?? ''}
            onChange={(v) => setCity(v || null)}
            placeholder="All Cities"
            width={100}
            disabled={!filters.country}
          />
        </div>
      )}

      {/* Spacer */}
      <div style={styles.spacer} />

      {/* Reset Button */}
      {showReset && (
        <button
          type="button"
          style={styles.button}
          onClick={resetFilters}
        >
          Reset
        </button>
      )}
    </div>
  );
}

// =============================================================================
// EXPORT HOOK FOR EXTERNAL USE
// =============================================================================

export { useFiltersCore } from './useFiltersCore';
export type { FiltersCoreState, TimeRange } from './useFiltersCore';
