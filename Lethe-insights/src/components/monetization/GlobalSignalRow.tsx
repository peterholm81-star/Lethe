import type React from 'react';

// =============================================================================
// TYPES
// =============================================================================

export interface GlobalSignalRowProps {
  activeCountries: number;
  /** Top-1 country share, e.g. "15.9%" */
  concentration: string | null;
  /** Top-3 share, e.g. "39.8%" */
  top3Share: string | null;
  /** Impressions per session, e.g. "0.53" */
  adPressure: string | null;
  confidenceLabel: string;
  stabilityLabel: string;
  bottleneck: string;
}

// =============================================================================
// COMPONENT
// =============================================================================

export function GlobalSignalRow({
  activeCountries,
  concentration,
  top3Share,
  adPressure,
  confidenceLabel,
  stabilityLabel,
  bottleneck,
}: GlobalSignalRowProps) {
  return (
    <div style={rowStyles.container}>
      <Chip label="FOOTPRINT" value={String(activeCountries)} />
      {concentration && <Chip label="CONC" value={concentration} />}
      {top3Share && <Chip label="TOP 3" value={top3Share} />}
      {adPressure && <Chip label="AD" value={adPressure} />}
      <Chip
        label="CONF"
        value={`${capitalize(confidenceLabel)} · ${capitalize(stabilityLabel)}`}
        tone={confidenceLabel === 'high' ? 'good' : confidenceLabel === 'low' ? 'muted' : 'neutral'}
      />
      <Chip label="BOTTLENECK" value={bottleneck} tone="warn" />
    </div>
  );
}

// =============================================================================
// CHIP — individual metric chip
// =============================================================================

type ChipTone = 'neutral' | 'good' | 'warn' | 'muted';

function Chip({ label, value, tone = 'neutral' }: { label: string; value: string; tone?: ChipTone }) {
  const valueColor =
    tone === 'good'  ? 'rgba(100, 200, 150, 0.9)' :
    tone === 'warn'  ? 'rgba(255, 180, 120, 0.85)' :
    tone === 'muted' ? 'rgba(255, 255, 255, 0.45)' :
    'rgba(255, 255, 255, 0.8)';

  return (
    <div style={chipStyles.chip}>
      <span style={chipStyles.label}>{label}</span>
      <span style={{ ...chipStyles.value, color: valueColor }}>{value}</span>
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// =============================================================================
// STYLES
// =============================================================================

const rowStyles = {
  container: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    padding: '8px 14px',
    background: 'rgba(15, 15, 22, 0.6)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: '8px',
    flexWrap: 'wrap' as const,
    minHeight: '40px',
  } as React.CSSProperties,
};

const chipStyles = {
  chip: {
    display: 'flex',
    alignItems: 'center',
    gap: '5px',
    padding: '3px 8px',
    borderRadius: '4px',
    background: 'rgba(255, 255, 255, 0.03)',
  } as React.CSSProperties,
  label: {
    fontSize: '9px',
    fontWeight: 600,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.35)',
    whiteSpace: 'nowrap' as const,
  } as React.CSSProperties,
  value: {
    fontSize: '11px',
    fontWeight: 600,
    whiteSpace: 'nowrap' as const,
    fontVariantNumeric: 'tabular-nums' as const,
  } as React.CSSProperties,
};
