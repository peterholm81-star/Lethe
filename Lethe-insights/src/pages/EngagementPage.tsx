import { EngagementFlow } from '../components/EngagementFlow';
import { ChangeOverTime } from '../components/ChangeOverTime';
import { ReadersVsWriters } from '../components/ReadersVsWriters';
import { FullWidthCard } from '../layout/InsightsLayout';

/**
 * Engagement Page - Detailed engagement metrics and trends
 */
export function EngagementPage() {
  return (
    <>
      {/* Row 1: Engagement Flow (featured, full width) */}
      <FullWidthCard>
        <section id="engagement-detail">
          <EngagementFlow />
        </section>
      </FullWidthCard>

      {/* Row 2: Readers vs Writers */}
      <section id="readers-writers">
        <ReadersVsWriters />
      </section>

      {/* Placeholder for balance */}
      <div />

      {/* Row 3: Change Over Time (full width) */}
      <FullWidthCard>
        <section id="change-over-time">
          <ChangeOverTime />
        </section>
      </FullWidthCard>
    </>
  );
}
