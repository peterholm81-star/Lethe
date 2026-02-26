import { useState, useEffect } from 'react';
import { useInsightsFilters, type InsightsMode, type InsightsDays } from '../contexts/InsightsContext';
import { SearchableDropdown } from './SearchableDropdown';
import { useCountryOptions, useRegionOptions, useCityOptions } from '../hooks/useInsightsFilterOptions';

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

  dateInput: {
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

  buttonPrimary: {
    padding: '6px 14px',
    fontSize: '11px',
    fontWeight: 500,
    color: '#000',
    background: 'rgba(255, 255, 255, 0.85)',
    border: 'none',
    borderRadius: '6px',
    cursor: 'pointer',
    transition: 'background 0.15s ease',
  } as React.CSSProperties,
};

/**
 * Get today's date as YYYY-MM-DD in UTC
 */
function getTodayUtc(): string {
  return new Date().toISOString().split('T')[0];
}

export function InsightsContextBar() {
  const { filters, applyFilters, resetFilters } = useInsightsFilters();

  // Local draft state (applied on Apply click)
  const [draft, setDraft] = useState({
    country_code: filters.country_code ?? '',
    region: filters.region ?? '',
    city_code: filters.city_code ?? '',
    mode: filters.mode ?? '',
    days: filters.days,
    activeDay: filters.activeDay,
  });

  // Fetch filter options from database with cascading dependencies
  const { options: regionOptions, loading: regionLoading } = useRegionOptions();
  const { options: countryOptions, loading: countryLoading } = useCountryOptions(
    draft.region || null
  );
  const { options: cityOptions, loading: cityLoading } = useCityOptions(
    draft.country_code || null,
    draft.region || null
  );

  // Sync draft with filters when filters change externally
  useEffect(() => {
    setDraft({
      country_code: filters.country_code ?? '',
      region: filters.region ?? '',
      city_code: filters.city_code ?? '',
      mode: filters.mode ?? '',
      days: filters.days,
      activeDay: filters.activeDay,
    });
  }, [filters]);

  const handleApply = () => {
    applyFilters({
      country_code: draft.country_code.trim() || null,
      region: draft.region.trim() || null,
      city_code: draft.city_code.trim() || null,
      mode: (draft.mode || null) as InsightsMode,
      days: draft.days,
      activeDay: draft.activeDay,
    });
  };

  const handleReset = () => {
    const today = getTodayUtc();
    setDraft({
      country_code: '',
      region: '',
      city_code: '',
      mode: '',
      days: 7,
      activeDay: today,
    });
    resetFilters();
  };

  // Cascading filter handlers
  const handleRegionChange = (value: string) => {
    setDraft(d => ({
      ...d,
      region: value,
      country_code: '',
      city_code: '',
    }));
  };

  const handleCountryChange = (value: string) => {
    setDraft(d => ({
      ...d,
      country_code: value,
      city_code: '',
    }));
  };

  const handleCityChange = (value: string) => {
    setDraft(d => ({ ...d, city_code: value }));
  };

  const isCityDisabled = !draft.country_code;

  return (
    <form
      autoComplete="off"
      onSubmit={(e) => e.preventDefault()}
      style={styles.bar}
    >
      {/* Region */}
      <div style={styles.group}>
        <label htmlFor="insights-lens-region" style={styles.label}>Region</label>
        <SearchableDropdown
          inputId="insights-lens-region"
          value={draft.region}
          onChange={handleRegionChange}
          options={regionOptions}
          loading={regionLoading}
          placeholder="All regions"
          width="110px"
        />
      </div>

      {/* Country */}
      <div style={styles.group}>
        <label htmlFor="insights-lens-country" style={styles.label}>Country</label>
        <SearchableDropdown
          inputId="insights-lens-country"
          value={draft.country_code}
          onChange={handleCountryChange}
          options={countryOptions}
          loading={countryLoading}
          placeholder="All"
          width="60px"
        />
      </div>

      {/* City */}
      <div style={styles.group}>
        <label htmlFor="insights-lens-city" style={styles.label}>City</label>
        <SearchableDropdown
          inputId="insights-lens-city"
          value={draft.city_code}
          onChange={handleCityChange}
          options={cityOptions}
          loading={cityLoading}
          placeholder="All"
          width="60px"
          disabled={isCityDisabled}
          disabledPlaceholder="Select country"
        />
      </div>

      {/* Mode */}
      <div style={styles.group}>
        <label htmlFor="insights-mode" style={styles.label}>Mode</label>
        <select
          id="insights-mode"
          name="insights-mode"
          style={styles.select}
          value={draft.mode}
          onChange={(e) => setDraft(d => ({ ...d, mode: e.target.value }))}
        >
          <option value="">All</option>
          <option value="world">World</option>
          <option value="near">Near me</option>
          <option value="somewhere">Somewhere</option>
        </select>
      </div>

      {/* Days */}
      <div style={styles.group}>
        <label htmlFor="insights-days" style={styles.label}>Days</label>
        <select
          id="insights-days"
          name="insights-days"
          style={styles.select}
          value={draft.days}
          onChange={(e) => setDraft(d => ({ ...d, days: Number(e.target.value) as InsightsDays }))}
        >
          <option value={1}>1</option>
          <option value={7}>7</option>
          <option value={30}>30</option>
        </select>
      </div>

      {/* Active Day */}
      <div style={styles.group}>
        <label htmlFor="insights-date" style={styles.label}>Date</label>
        <input
          id="insights-date"
          name="insights-date"
          type="date"
          style={styles.dateInput}
          value={draft.activeDay}
          onChange={(e) => setDraft(d => ({ ...d, activeDay: e.target.value }))}
        />
      </div>

      {/* Spacer */}
      <div style={styles.spacer} />

      {/* Buttons - type="button" prevents form submission */}
      <button type="button" style={styles.buttonPrimary} onClick={handleApply}>
        Apply
      </button>
      <button type="button" style={styles.button} onClick={handleReset}>
        Reset
      </button>
    </form>
  );
}
