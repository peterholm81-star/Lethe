import React from 'react';

// =============================================================================
// TYPES
// =============================================================================

export interface DeltaBadgeProps {
  /** Delta percentage value (e.g., 12.4 for +12.4%) */
  value?: number;
  /** Show label instead of arrow for near-zero values */
  showStableLabel?: boolean;
}

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  container: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '2px',
    fontSize: '11px',
    fontWeight: 500,
    fontVariantNumeric: 'tabular-nums',
    animation: 'deltaFadeIn 200ms ease-out',
  } as React.CSSProperties,

  positive: {
    color: 'rgba(100, 200, 150, 0.9)',
  } as React.CSSProperties,

  negative: {
    color: 'rgba(255, 130, 100, 0.9)',
  } as React.CSSProperties,

  neutral: {
    color: 'rgba(255, 255, 255, 0.4)',
  } as React.CSSProperties,

  arrow: {
    fontSize: '10px',
  } as React.CSSProperties,
};

// Inject keyframes for fade-in animation
const injectKeyframes = () => {
  if (typeof document === 'undefined') return;
  const styleId = 'delta-badge-keyframes';
  if (document.getElementById(styleId)) return;
  
  const style = document.createElement('style');
  style.id = styleId;
  style.textContent = `
    @keyframes deltaFadeIn {
      from { opacity: 0; transform: translateY(-2px); }
      to { opacity: 1; transform: translateY(0); }
    }
  `;
  document.head.appendChild(style);
};

// =============================================================================
// COMPONENT
// =============================================================================

export function DeltaBadge({ value, showStableLabel = true }: DeltaBadgeProps) {
  // Inject animation keyframes once
  React.useEffect(() => {
    injectKeyframes();
  }, []);

  // Don't render if value is undefined
  if (value === undefined) {
    return null;
  }

  // Determine direction and styling
  const isPositive = value > 1;
  const isNegative = value < -1;
  const isNeutral = !isPositive && !isNegative;

  const colorStyle = isPositive 
    ? styles.positive 
    : isNegative 
    ? styles.negative 
    : styles.neutral;

  const arrow = isPositive ? '↑' : isNegative ? '↓' : '';
  const sign = isPositive ? '+' : '';
  const formattedValue = `${sign}${value.toFixed(1)}%`;

  return (
    <span 
      style={{ ...styles.container, ...colorStyle }}
      title="Change compared to previous period"
    >
      {arrow && <span style={styles.arrow}>{arrow}</span>}
      {isNeutral && showStableLabel ? (
        <span>stable</span>
      ) : (
        <span>{formattedValue}</span>
      )}
    </span>
  );
}

// =============================================================================
// HELPER FUNCTION
// =============================================================================

/**
 * Calculate percentage delta between current and previous values.
 * Returns undefined if previous is 0 or not provided.
 */
export function percentDelta(current: number, previous: number | undefined): number | undefined {
  if (previous === undefined || previous === 0) {
    return undefined;
  }
  return ((current - previous) / previous) * 100;
}
