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
  showCompare?: boolean;
  sticky?: boolean;
  /** Visual indicator when compare mode is active */
  compareActive?: boolean;
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

  barSticky: {
    display: 'flex',
    flexWrap: 'wrap' as const,
    alignItems: 'center',
    gap: '12px',
    padding: '12px 16px',
    background: 'rgba(12, 12, 18, 0.92)',
    backdropFilter: 'blur(12px)',
    borderRadius: '10px',
    marginBottom: '16px',
    position: 'sticky' as const,
    top: 0,
    zIndex: 50,
    borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
    boxShadow: '0 4px 16px rgba(0, 0, 0, 0.3)',
  } as React.CSSProperties,

  barStickyCompareActive: {
    display: 'flex',
    flexWrap: 'wrap' as const,
    alignItems: 'center',
    gap: '12px',
    padding: '12px 16px',
    background: 'rgba(12, 12, 18, 0.92)',
    backdropFilter: 'blur(12px)',
    borderRadius: '10px',
    marginBottom: '16px',
    position: 'sticky' as const,
    top: 0,
    zIndex: 50,
    borderBottom: '1px solid rgba(80, 200, 150, 0.25)',
    boxShadow: '0 4px 16px rgba(0, 0, 0, 0.3), 0 1px 0 rgba(80, 200, 150, 0.1) inset',
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

  selectDisabled: {
    padding: '6px 10px',
    fontSize: '12px',
    background: 'rgba(255, 255, 255, 0.02)',
    border: '1px solid rgba(255, 255, 255, 0.05)',
    borderRadius: '6px',
    color: 'rgba(255, 255, 255, 0.3)',
    outline: 'none',
    cursor: 'not-allowed',
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

  compareToggle: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    padding: '4px 10px',
    background: 'rgba(255, 255, 255, 0.04)',
    border: '1px solid rgba(255, 255, 255, 0.08)',
    borderRadius: '6px',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  } as React.CSSProperties,

  compareToggleActive: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    padding: '4px 10px',
    background: 'rgba(100, 180, 150, 0.15)',
    border: '1px solid rgba(100, 180, 150, 0.3)',
    borderRadius: '6px',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  } as React.CSSProperties,

  compareCheckbox: {
    width: '14px',
    height: '14px',
    accentColor: 'rgba(100, 180, 150, 1)',
    cursor: 'pointer',
  } as React.CSSProperties,

  compareLabel: {
    fontSize: '11px',
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.7)',
    userSelect: 'none' as const,
  } as React.CSSProperties,

  compareLabelActive: {
    fontSize: '11px',
    fontWeight: 500,
    color: 'rgba(100, 200, 150, 0.9)',
    userSelect: 'none' as const,
  } as React.CSSProperties,

  hint: {
    fontSize: '9px',
    color: 'rgba(255, 255, 255, 0.35)',
    fontStyle: 'italic' as const,
    marginLeft: '4px',
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
  showCompare = false,
  sticky = false,
  compareActive = false,
}: FilterBarCoreProps) {
  const {
    filters,
    setTimeRange,
    setRegion,
    setCountry,
    setCity,
    setCompareToPrevious,
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

  // Check if region dropdown should be disabled (no real options)
  const regionDisabled = availableRegions.length === 0;

  // Determine bar style based on sticky and compare state
  const barStyle = sticky 
    ? (compareActive ? styles.barStickyCompareActive : styles.barSticky) 
    : styles.bar;

  return (
    <div style={barStyle}>
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
        {regionDisabled ? (
          <div style={{ display: 'flex', alignItems: 'center' }}>
            <select
              style={styles.selectDisabled}
              disabled
              value=""
            >
              <option value="">All Regions</option>
            </select>
            <span style={styles.hint}>Data pending</span>
          </div>
        ) : (
          <SearchableDropdown
            options={regionOptions}
            value={filters.region ?? ''}
            onChange={(v) => setRegion(v || null)}
            placeholder="All Regions"
            width={120}
          />
        )}
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

      {/* Compare Toggle */}
      {showCompare && (
        <label style={filters.compareToPrevious ? styles.compareToggleActive : styles.compareToggle}>
          <input
            type="checkbox"
            checked={filters.compareToPrevious}
            onChange={(e) => setCompareToPrevious(e.target.checked)}
            style={styles.compareCheckbox}
          />
          <span style={filters.compareToPrevious ? styles.compareLabelActive : styles.compareLabel}>
            Compare
          </span>
        </label>
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
