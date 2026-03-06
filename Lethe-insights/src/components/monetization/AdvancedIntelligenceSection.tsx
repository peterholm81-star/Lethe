import { useState, type ReactNode, type CSSProperties } from 'react';

// =============================================================================
// TYPES
// =============================================================================

export interface AdvancedIntelligenceSectionProps {
  children: ReactNode;
  /** Number of items inside (shown as badge in header) */
  itemCount?: number;
  /** Optional element rendered in the header row (e.g. InfoHint) */
  headerRight?: ReactNode;
}

// =============================================================================
// COMPONENT
// =============================================================================

export function AdvancedIntelligenceSection({ children, itemCount, headerRight }: AdvancedIntelligenceSectionProps) {
  const [open, setOpen] = useState(false);

  return (
    <div style={sectionStyles.container}>
      <div
        style={sectionStyles.header}
        onClick={() => setOpen(v => !v)}
      >
        <div style={sectionStyles.headerLeft}>
          <span style={{ ...sectionStyles.chevron, transform: open ? 'rotate(90deg)' : 'rotate(0deg)' }}>
            ▶
          </span>
          <span style={sectionStyles.title}>Advanced Intelligence</span>
          {itemCount != null && itemCount > 0 && (
            <span style={sectionStyles.badge}>{itemCount}</span>
          )}
          {headerRight && (
            <span onClick={e => e.stopPropagation()}>{headerRight}</span>
          )}
        </div>
        <span style={sectionStyles.toggle}>{open ? 'Collapse' : 'Expand'}</span>
      </div>
      {open && (
        <div style={sectionStyles.body}>
          {children}
        </div>
      )}
    </div>
  );
}

// =============================================================================
// SUB-SECTION — reusable titled block inside the section
// =============================================================================

export function IntelSubSection({ title, children, headerRight }: { title: string; children: ReactNode; headerRight?: ReactNode }) {
  return (
    <div style={subStyles.block}>
      <div style={subStyles.labelRow}>
        <div style={subStyles.label}>{title}</div>
        {headerRight}
      </div>
      {children}
    </div>
  );
}

// =============================================================================
// STYLES
// =============================================================================

const sectionStyles: Record<string, CSSProperties> = {
  container: {
    background: 'rgba(12, 12, 18, 0.7)',
    border: '1px solid rgba(255, 255, 255, 0.05)',
    borderRadius: '10px',
    overflow: 'hidden',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '10px 16px',
    cursor: 'pointer',
    userSelect: 'none',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  chevron: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.35)',
    transition: 'transform 150ms ease',
    width: '12px',
    textAlign: 'center',
  },
  title: {
    fontSize: '11px',
    fontWeight: 600,
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: 'rgba(255, 255, 255, 0.5)',
  },
  badge: {
    fontSize: '9px',
    fontWeight: 600,
    padding: '1px 5px',
    borderRadius: '4px',
    background: 'rgba(255, 255, 255, 0.06)',
    color: 'rgba(255, 255, 255, 0.4)',
  },
  toggle: {
    fontSize: '10px',
    color: 'rgba(255, 255, 255, 0.3)',
  },
  body: {
    padding: '4px 16px 16px',
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
    borderTop: '1px solid rgba(255, 255, 255, 0.04)',
  },
};

const subStyles: Record<string, CSSProperties> = {
  block: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  labelRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    paddingBottom: '4px',
    borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
  },
  label: {
    fontSize: '10px',
    fontWeight: 600,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: 'rgba(255, 255, 255, 0.35)',
  },
};
