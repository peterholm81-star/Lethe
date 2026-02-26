import { PulseMetrics } from '../components/PulseMetrics';
import { ReadersVsWriters } from '../components/ReadersVsWriters';
import { FrictionCard } from '../components/FrictionCard';
import { ChangeOverTime } from '../components/ChangeOverTime';
import { EngagementFlow } from '../components/EngagementFlow';
import { FullWidthCard } from '../layout/InsightsLayout';

/**
 * Overview Page - Dashboard with all key metrics at a glance
 */
export function OverviewPage() {
  return (
    <>
      {/* Row 1: Pulse + Engagement Flow */}
      <section id="pulse">
        <PulseMetrics />
      </section>

      <section id="engagement">
        <EngagementFlow />
      </section>

      {/* Row 2: Readers vs Writers + Friction */}
      <section id="readers-writers">
        <ReadersVsWriters />
      </section>

      <section id="friction">
        <FrictionCard />
      </section>

      {/* Row 3: Change Over Time (full width) */}
      <FullWidthCard>
        <section id="change-over-time">
          <ChangeOverTime />
        </section>
      </FullWidthCard>
    </>
  );
}
