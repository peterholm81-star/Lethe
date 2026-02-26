import { useState, useEffect } from 'react';
import { InsightsGlossaryModal } from './components/InsightsGlossaryModal';
import { InsightsContextBar } from './components/InsightsContextBar';
import { InsightsConsistencyChecker } from './components/InsightsConsistencyChecker';
import { InsightsLayout, type PageId } from './layout/InsightsLayout';
import { OverviewPage } from './pages/OverviewPage';
import { EngagementPage } from './pages/EngagementPage';
import { MonetizationPage } from './pages/MonetizationPage';
import { ReportsPage } from './pages/ReportsPage';
import { MoodPage } from './pages/MoodPage';
import { useInsightsFilters } from './contexts/InsightsContext';
import { useInsightsActiveDay } from './hooks/useInsightsActiveDay';
import { supabase } from './lib/supabase';
import './App.css';

export default function App() {
  const { applyFilters, lensLabel, windowLabel } = useInsightsFilters();
  const { activeDay, loading: dayLoading } = useInsightsActiveDay();
  const [isGlossaryOpen, setIsGlossaryOpen] = useState(false);
  const [activePage, setActivePage] = useState<PageId>('overview');

  // Ensure anonymous auth session exists for admin RPC calls
  useEffect(() => {
    let cancelled = false;

    (async () => {
      const { data: sessionData } = await supabase.auth.getSession();

      if (!sessionData?.session && !cancelled) {
        await supabase.auth.signInAnonymously();
      }
    })();

    return () => { cancelled = true; };
  }, []);

  // Set initial activeDay in context once bootstrap is complete
  useEffect(() => {
    if (!dayLoading && activeDay) {
      applyFilters({ activeDay });
    }
  }, [dayLoading, activeDay, applyFilters]);

  // Header shows the current lens and window
  const headerInfo = `${lensLabel} · ${windowLabel}`;

  // Render page content based on active page
  const renderPageContent = () => {
    switch (activePage) {
      case 'overview':
        return <OverviewPage />;
      case 'engagement':
        return <EngagementPage />;
      case 'monetization':
        return <MonetizationPage />;
      case 'reports':
        return <ReportsPage />;
      case 'mood':
        return <MoodPage />;
      default:
        return <OverviewPage />;
    }
  };

  // Determine if we should show filter bar and use grid
  // Reports and Mood pages have their own filters, so hide the global filter bar
  const showFilterBar = activePage !== 'monetization' && activePage !== 'reports' && activePage !== 'mood';
  const useGrid = activePage !== 'monetization' && activePage !== 'reports' && activePage !== 'mood';

  return (
    <>
      <InsightsLayout
        filterBar={showFilterBar ? <InsightsContextBar /> : undefined}
        headerInfo={headerInfo}
        onInfoClick={() => setIsGlossaryOpen(true)}
        activePage={activePage}
        onPageChange={setActivePage}
        noGrid={!useGrid}
      >
        {renderPageContent()}
      </InsightsLayout>

      {/* Glossary Modal */}
      <InsightsGlossaryModal
        isOpen={isGlossaryOpen}
        onClose={() => setIsGlossaryOpen(false)}
      />

      {/* DEV-only: Consistency checker for Pulse vs EngagementFlow sessions */}
      <InsightsConsistencyChecker />
    </>
  );
}
