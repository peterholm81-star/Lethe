import { ReactNode } from 'react';

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  card: {
    padding: '20px',
    background: 'rgba(255, 255, 255, 0.05)',
    border: '1px solid rgba(255, 255, 255, 0.09)',
    borderRadius: '14px',
  } as React.CSSProperties,

  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    marginBottom: '16px',
  } as React.CSSProperties,

  title: {
    margin: 0,
    fontSize: '12px',
    fontWeight: 550,
    letterSpacing: '0.12em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.85)',
  } as React.CSSProperties,

  subtitle: {
    fontSize: '12px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.35)',
  } as React.CSSProperties,

  body: {
    // Body has no default styles - content decides
  } as React.CSSProperties,
};

// =============================================================================
// CARD HEADER
// =============================================================================

interface CardHeaderProps {
  title: string;
  subtitle?: string;
  right?: ReactNode;
}

export function CardHeader({ title, subtitle, right }: CardHeaderProps) {
  return (
    <div style={styles.header}>
      <div>
        <h2 style={styles.title}>{title}</h2>
        {subtitle && <p style={{ ...styles.subtitle, marginTop: '4px' }}>{subtitle}</p>}
      </div>
      {right && <span style={styles.subtitle}>{right}</span>}
    </div>
  );
}

// =============================================================================
// CARD BODY
// =============================================================================

interface CardBodyProps {
  children: ReactNode;
}

export function CardBody({ children }: CardBodyProps) {
  return <div style={styles.body}>{children}</div>;
}

// =============================================================================
// CARD
// =============================================================================

interface CardProps {
  children: ReactNode;
  className?: string;
  style?: React.CSSProperties;
}

export function Card({ children, className, style }: CardProps) {
  return (
    <div className={className} style={{ ...styles.card, ...style }}>
      {children}
    </div>
  );
}

// Convenience export for common pattern
Card.Header = CardHeader;
Card.Body = CardBody;

export default Card;
