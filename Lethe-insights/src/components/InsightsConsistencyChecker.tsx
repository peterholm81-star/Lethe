import { usePulseMetrics } from '../hooks/usePulseMetrics';
import { useEngagementFlow } from '../hooks/useEngagementFlow';
import { useInsightsFilters } from '../contexts/InsightsContext';
import { useInsightsConsistencyCheck } from '../hooks/useInsightsConsistencyCheck';

/**
 * DEV-only component that checks consistency between Pulse and EngagementFlow.
 * 
 * This component renders nothing - it only performs the consistency check
 * in development mode and logs warnings if sessions don't match.
 * 
 * In production, this component is a no-op.
 */
export function InsightsConsistencyChecker(): null {
  // Skip entirely in production
  if (!import.meta.env.DEV) {
    return null;
  }

  // Get filters and window from context (same source as components)
  const { filters, window, lensLabel, windowLabel } = useInsightsFilters();

  // Fetch data using same hooks as components
  const { data: pulseData, loading: pulseLoading } = usePulseMetrics(filters, window);
  const { data: engagementData, loading: engagementLoading } = useEngagementFlow(filters, window);

  // Run consistency check
  useInsightsConsistencyCheck({
    pulseData,
    pulseLoading,
    engagementData,
    engagementLoading,
    lensLabel,
    windowLabel,
  });

  // Render nothing
  return null;
}
