import { ReactNode } from 'react';

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  // Root container - desktop only, minimum 1200px
  // Use height: 100vh to constrain to viewport, overflow: hidden to prevent root scroll
  root: {
    minWidth: '1200px',
    height: '100vh',
    display: 'flex',
    overflow: 'hidden' as const,
  } as React.CSSProperties,

  // Sidebar - fixed width, scrolls independently
  sidebar: {
    width: '240px',
    flexShrink: 0,
    background: 'rgba(255, 255, 255, 0.02)',
    borderRight: '1px solid rgba(255, 255, 255, 0.06)',
    display: 'flex',
    flexDirection: 'column' as const,
    height: '100%',
    overflowY: 'auto' as const,
  } as React.CSSProperties,

  sidebarHeader: {
    padding: '24px 20px 20px',
    borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
  } as React.CSSProperties,

  sidebarLogo: {
    margin: 0,
    fontSize: '18px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
    letterSpacing: '-0.01em',
  } as React.CSSProperties,

  sidebarNav: {
    flex: 1,
    padding: '16px 12px',
  } as React.CSSProperties,

  navSection: {
    marginBottom: '8px',
  } as React.CSSProperties,

  navSectionLabel: {
    padding: '8px 12px 6px',
    fontSize: '10px',
    fontWeight: 500,
    letterSpacing: '0.1em',
    textTransform: 'uppercase' as const,
    color: 'rgba(255, 255, 255, 0.3)',
  } as React.CSSProperties,

  navItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    padding: '10px 12px',
    borderRadius: '8px',
    fontSize: '13px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.6)',
    textDecoration: 'none',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
    border: 'none',
    background: 'transparent',
    width: '100%',
    textAlign: 'left' as const,
  } as React.CSSProperties,

  navItemActive: {
    background: 'rgba(255, 255, 255, 0.08)',
    color: 'rgba(255, 255, 255, 0.95)',
    fontWeight: 500,
  } as React.CSSProperties,

  navItemDisabled: {
    color: 'rgba(255, 255, 255, 0.25)',
    cursor: 'default',
  } as React.CSSProperties,

  navItemSoon: {
    marginLeft: 'auto',
    fontSize: '9px',
    fontWeight: 400,
    color: 'rgba(255, 255, 255, 0.25)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  } as React.CSSProperties,

  // Main area - takes remaining width, contains scrollable content
  main: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column' as const,
    minWidth: 0,
    minHeight: 0, // Required for flex child to allow shrinking/overflow
    height: '100%',
    overflow: 'hidden' as const, // Let children handle scroll
  } as React.CSSProperties,

  // Header
  header: {
    padding: '20px 32px 16px',
    borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
    background: 'rgba(26, 26, 26, 0.5)',
    backdropFilter: 'blur(8px)',
  } as React.CSSProperties,

  headerRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  } as React.CSSProperties,

  headerTitle: {
    margin: 0,
    fontSize: '20px',
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
    letterSpacing: '-0.01em',
  } as React.CSSProperties,

  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  } as React.CSSProperties,

  viewingLabel: {
    fontSize: '12px',
    color: 'rgba(255, 255, 255, 0.5)',
  } as React.CSSProperties,

  viewingLabelStrong: {
    color: 'rgba(255, 255, 255, 0.7)',
  } as React.CSSProperties,

  infoButton: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: '32px',
    height: '32px',
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '8px',
    color: 'rgba(255, 255, 255, 0.5)',
    fontSize: '16px',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  } as React.CSSProperties,

  // Filter bar (sticky)
  filterBar: {
    position: 'sticky' as const,
    top: 0,
    zIndex: 50,
    padding: '16px 32px',
    background: 'rgba(26, 26, 26, 0.85)',
    backdropFilter: 'blur(12px)',
    borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
  } as React.CSSProperties,

  // Content area - scrollable
  content: {
    flex: 1,
    minHeight: 0, // Required for flex child to allow overflow
    padding: '24px 32px 48px',
    overflowY: 'auto' as const,
  } as React.CSSProperties,

  contentGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, 1fr)',
    gap: '24px',
  } as React.CSSProperties,

  // Content without grid (for custom pages like Reports) - scrollable
  // NOTE: Pages using this with sticky children (e.g. MonetizationPage) should use
  // top values relative to THIS scroll container, not the full viewport.
  contentPlain: {
    flex: 1,
    minHeight: 0, // Required for flex child to allow overflow
    overflowY: 'auto' as const,
  } as React.CSSProperties,
};

// =============================================================================
// NAV ITEMS
// =============================================================================

export type PageId = 'overview' | 'engagement' | 'monetization' | 'reports' | 'reliability' | 'trends' | 'mood';

interface NavItem {
  id: PageId | 'intent';
  label: string;
  title: string;
  active: boolean;
  section?: 'analytics' | 'moderation';
}

const navItems: NavItem[] = [
  // Analytics section
  { id: 'overview', label: 'Overview', title: 'Overview', active: true, section: 'analytics' },
  { id: 'engagement', label: 'Engagement', title: 'Engagement', active: true, section: 'analytics' },
  { id: 'monetization', label: 'Monetization', title: 'Revenue Lab', active: true, section: 'analytics' },
  { id: 'mood', label: 'Mood', title: 'Mood Metrics', active: true, section: 'analytics' },
  { id: 'intent', label: 'Intent', title: 'Intent', active: false, section: 'analytics' },
  { id: 'reliability', label: 'Reliability', title: 'Reliability', active: false, section: 'analytics' },
  { id: 'trends', label: 'Trends', title: 'Trends', active: true, section: 'analytics' },
  // Moderation section
  { id: 'reports', label: 'Reports', title: 'Reports Inbox', active: true, section: 'moderation' },
];

// =============================================================================
// COMPONENTS
// =============================================================================

interface InsightsLayoutProps {
  children: ReactNode;
  filterBar?: ReactNode;
  headerInfo: string;
  onInfoClick?: () => void;
  activePage?: PageId;
  onPageChange?: (pageId: PageId) => void;
  /** If true, don't wrap children in grid */
  noGrid?: boolean;
}

export function InsightsLayout({
  children,
  filterBar,
  headerInfo,
  onInfoClick,
  activePage = 'overview',
  onPageChange,
  noGrid = false,
}: InsightsLayoutProps) {
  const activeNavItem = navItems.find(item => item.id === activePage) || navItems[0];

  const handleNavClick = (item: NavItem) => {
    if (item.active && onPageChange && item.id !== 'intent') {
      onPageChange(item.id as PageId);
    }
  };

  // Group nav items by section
  const analyticsItems = navItems.filter(item => item.section === 'analytics');
  const moderationItems = navItems.filter(item => item.section === 'moderation');

  return (
    <div style={styles.root}>
      {/* Sidebar */}
      <aside style={styles.sidebar}>
        <div style={styles.sidebarHeader}>
          <h1 style={styles.sidebarLogo}>Lethe Insights</h1>
        </div>
        <nav style={styles.sidebarNav}>
          {/* Analytics Section */}
          <div style={styles.navSection}>
            <div style={styles.navSectionLabel}>Analytics</div>
            {analyticsItems.map((item) => (
              <button
                key={item.id}
                onClick={() => handleNavClick(item)}
                style={{
                  ...styles.navItem,
                  ...(item.id === activePage ? styles.navItemActive : {}),
                  ...(!item.active ? styles.navItemDisabled : {}),
                }}
                disabled={!item.active}
              >
                {item.label}
                {!item.active && <span style={styles.navItemSoon}>Soon</span>}
              </button>
            ))}
          </div>
          {/* Moderation Section */}
          <div style={{ ...styles.navSection, marginTop: '16px' }}>
            <div style={styles.navSectionLabel}>Moderation</div>
            {moderationItems.map((item) => (
              <button
                key={item.id}
                onClick={() => handleNavClick(item)}
                style={{
                  ...styles.navItem,
                  ...(item.id === activePage ? styles.navItemActive : {}),
                  ...(!item.active ? styles.navItemDisabled : {}),
                }}
                disabled={!item.active}
              >
                {item.label}
                {!item.active && <span style={styles.navItemSoon}>Soon</span>}
              </button>
            ))}
          </div>
        </nav>
      </aside>

      {/* Main Area */}
      <main style={styles.main}>
        {/* Header */}
        <header style={styles.header}>
          <div style={styles.headerRow}>
            <h2 style={styles.headerTitle}>{activeNavItem.title}</h2>
            <div style={styles.headerRight}>
              <span style={styles.viewingLabel}>
                Viewing: <span style={styles.viewingLabelStrong}>{headerInfo}</span>
              </span>
              {onInfoClick && (
                <button
                  style={styles.infoButton}
                  onClick={onInfoClick}
                  aria-label="Open glossary"
                  title="Insights Glossary"
                >
                  ⓘ
                </button>
              )}
            </div>
          </div>
        </header>

        {/* Sticky Filter Bar (optional) */}
        {filterBar && <div style={styles.filterBar}>{filterBar}</div>}

        {/* Content */}
        {noGrid ? (
          <div style={styles.contentPlain}>{children}</div>
        ) : (
          <div style={styles.content}>
            <div style={styles.contentGrid}>{children}</div>
          </div>
        )}
      </main>
    </div>
  );
}

// Grid wrapper for full-width cards (e.g. charts)
export function FullWidthCard({ children }: { children: ReactNode }) {
  return <div style={{ gridColumn: '1 / -1' }}>{children}</div>;
}
