/**
 * Revenue Driver Analysis
 * 
 * Identifies which variable currently limits revenue the most
 * based on the Revenue Lab formula.
 */

export type RevenueInputs = {
  sessions: number;
  eCPM: number;
  fillRate: number;
  adsPerSessionCap: number;
  triggerShare: number;
};

export interface DriverInsight {
  title: string;
  message: string;
}

/**
 * Analyze which input is the primary bottleneck for revenue.
 * Normalizes each input to a 0-1 scale and identifies the lowest.
 */
export function analyzeRevenueDrivers(input: RevenueInputs): DriverInsight {
  const {
    sessions,
    eCPM,
    fillRate,
    adsPerSessionCap,
    triggerShare,
  } = input;

  // Normalize each driver to a comparable 0-1 scale
  // Sessions: assume 1000/day is "good" (1.0)
  // eCPM: assume 50 NOK is "good" (1.0)
  // fillRate: already 0-1
  // adsPerSessionCap: assume 2 is "good" (1.0)
  // triggerShare: already 0-1
  const drivers = [
    { key: 'sessions', value: Math.min(sessions / 1000, 1) },
    { key: 'eCPM', value: Math.min(eCPM / 50, 1) },
    { key: 'fillRate', value: fillRate },
    { key: 'adsPerSessionCap', value: Math.min(adsPerSessionCap / 2, 1) },
    { key: 'triggerShare', value: triggerShare },
  ];

  const lowest = drivers.reduce((min, d) =>
    d.value < min.value ? d : min
  );

  switch (lowest.key) {
    case 'sessions':
      return {
        title: 'Growth limited by traffic',
        message:
          'Revenue is primarily limited by low session volume. Increasing usage will have the largest impact.',
      };

    case 'eCPM':
      return {
        title: 'Ad pricing is the bottleneck',
        message:
          'Revenue is mostly constrained by low eCPM. Higher-value regions or better ad demand would increase revenue.',
      };

    case 'fillRate':
      return {
        title: 'Inventory underfilled',
        message:
          'Many ad opportunities are not filled. Improving fill rate would significantly increase revenue.',
      };

    case 'adsPerSessionCap':
      return {
        title: 'Ad frequency capped',
        message:
          'Revenue is limited by the ads-per-session cap. Increasing allowed ads would raise revenue.',
      };

    default:
      return {
        title: 'Trigger timing limits revenue',
        message:
          'Few sessions reach ad trigger conditions. Adjusting trigger share could increase impressions.',
      };
  }
}
