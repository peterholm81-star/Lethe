import { useState, useEffect, useRef } from 'react';
import { supabase } from '../lib/supabase';
import {
  buildPulseArgsLegacy,
  createLatestOnlyGuard,
  unwrapRpcRow,
  type LatestOnlyGuard,
} from '../insights/insightsRpc';

export interface InsightsActiveDayResult {
  activeDay: string; // YYYY-MM-DD
  source: 'today' | 'latest';
  loading: boolean;
}

interface PulseRow {
  sessions_today?: number;
  readers_today?: number;
  posts_today?: number;
}

interface LatestDayRow {
  day_bucket?: string;
}

/**
 * Get today's date as YYYY-MM-DD in UTC
 */
function getTodayUtc(): string {
  return new Date().toISOString().split('T')[0];
}

/**
 * Hook to determine the active day for Insights.
 * - First tries "today" (UTC)
 * - If today has no data (0/0/0), falls back to the latest day with data
 * 
 * This is used only for INITIAL bootstrap. Once set, activeDay is managed
 * by InsightsContext and can be changed by the user.
 */
export function useInsightsActiveDay(): InsightsActiveDayResult {
  const [activeDay, setActiveDay] = useState<string>(() => getTodayUtc());
  const [source, setSource] = useState<'today' | 'latest'>('today');
  const [loading, setLoading] = useState(true);

  const guardRef = useRef<LatestOnlyGuard>(createLatestOnlyGuard());

  useEffect(() => {
    async function determineActiveDay() {
      const reqId = guardRef.current.nextRequestId();
      setLoading(true);
      
      const todayUtc = getTodayUtc();

      try {
        // Check if today has data using legacy single-day RPC
        const args = buildPulseArgsLegacy(todayUtc);
        const { data: pulseData, error: pulseError } = await supabase.rpc(
          'get_pulse_metrics',
          args
        );

        if (guardRef.current.warnIfStale(reqId, 'ACTIVE_DAY')) {
          return;
        }

        if (!pulseError) {
          const row = unwrapRpcRow<PulseRow>(pulseData);
          const hasData = row && (
            (Number(row.sessions_today) || 0) > 0 ||
            (Number(row.readers_today) || 0) > 0 ||
            (Number(row.posts_today) || 0) > 0
          );

          if (hasData) {
            setActiveDay(todayUtc);
            setSource('today');
            setLoading(false);
            return;
          }
        }

        // Today has no data, get latest day with data
        const { data: latestData, error: latestError } = await supabase.rpc(
          'get_latest_metrics_day',
          {
            p_city: 'WORLD',
            p_region: 'WORLD',
          }
        );

        if (guardRef.current.warnIfStale(reqId, 'ACTIVE_DAY')) {
          return;
        }

        if (!latestError) {
          const latestRow = unwrapRpcRow<LatestDayRow>(latestData);
          const latestDay = latestRow?.day_bucket;

          if (latestDay) {
            setActiveDay(latestDay);
            setSource('latest');
          } else {
            setActiveDay(todayUtc);
            setSource('today');
          }
        } else {
          setActiveDay(todayUtc);
          setSource('today');
        }
      } catch {
        if (!guardRef.current.isLatest(reqId)) {
          return;
        }
        setActiveDay(getTodayUtc());
        setSource('today');
      } finally {
        if (guardRef.current.isLatest(reqId)) {
          setLoading(false);
        }
      }
    }

    determineActiveDay();
  }, []);

  return { activeDay, source, loading };
}
