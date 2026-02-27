import { useState, useMemo, useCallback } from 'react';
import {
  ComposableMap,
  Geographies,
  Geography,
} from 'react-simple-maps';

// =============================================================================
// TYPES
// =============================================================================

export interface RevenueMapDataItem {
  countryCode: string;
  sessions: number;
  adImpressions: number;
  revenueTotal: number;
  revenuePerSession: number;
}

export interface RevenueMapTotals {
  sessions: number;
  adImpressions: number;
}

interface RevenueMapPhase1Props {
  data: RevenueMapDataItem[];
  loading?: boolean;
  error?: string | null;
  /** Total metrics for computing share % */
  totals?: RevenueMapTotals;
  /** Controlled hover state (optional) */
  hoveredCountryCode?: string | null;
  /** Callback when user hovers a country */
  onHoverCountry?: (countryCode: string | null) => void;
  /** Callback when user clicks a country */
  onClickCountry?: (countryCode: string) => void;
  /** Phase 7: Pinned country code (click-to-lock) */
  pinnedCountryCode?: string | null;
  /** Phase 7: Previous period data for comparison */
  previousData?: RevenueMapDataItem[];
  /** Phase 7: Previous period totals for comparison */
  previousTotals?: RevenueMapTotals;
}

// =============================================================================
// GEO JSON URL (Natural Earth - same as MoodWorldMap)
// =============================================================================

const GEO_URL = 'https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json';

// =============================================================================
// ISO-2 CODE TO COUNTRY NAME MAPPING
// Maps ISO 3166-1 alpha-2 codes to Natural Earth country names
// =============================================================================

const ISO_TO_COUNTRY_NAME: Record<string, string[]> = {
  // Europe
  'NO': ['Norway'],
  'SE': ['Sweden'],
  'DK': ['Denmark'],
  'FI': ['Finland'],
  'IS': ['Iceland'],
  'GB': ['United Kingdom'],
  'IE': ['Ireland'],
  'DE': ['Germany'],
  'FR': ['France'],
  'ES': ['Spain'],
  'PT': ['Portugal'],
  'IT': ['Italy'],
  'NL': ['Netherlands'],
  'BE': ['Belgium'],
  'LU': ['Luxembourg'],
  'CH': ['Switzerland'],
  'AT': ['Austria'],
  'PL': ['Poland'],
  'CZ': ['Czechia', 'Czech Republic'],
  'SK': ['Slovakia'],
  'HU': ['Hungary'],
  'RO': ['Romania'],
  'BG': ['Bulgaria'],
  'GR': ['Greece'],
  'HR': ['Croatia'],
  'SI': ['Slovenia'],
  'RS': ['Serbia'],
  'BA': ['Bosnia and Herzegovina', 'Bosnia and Herz.'],
  'ME': ['Montenegro'],
  'MK': ['North Macedonia', 'N. Macedonia'],
  'AL': ['Albania'],
  'XK': ['Kosovo'],
  'EE': ['Estonia'],
  'LV': ['Latvia'],
  'LT': ['Lithuania'],
  'BY': ['Belarus'],
  'UA': ['Ukraine'],
  'MD': ['Moldova'],
  'RU': ['Russia'],
  
  // North America
  'US': ['United States of America', 'United States', 'USA'],
  'CA': ['Canada'],
  'MX': ['Mexico'],
  'GT': ['Guatemala'],
  'BZ': ['Belize'],
  'HN': ['Honduras'],
  'SV': ['El Salvador'],
  'NI': ['Nicaragua'],
  'CR': ['Costa Rica'],
  'PA': ['Panama'],
  'CU': ['Cuba'],
  'JM': ['Jamaica'],
  'HT': ['Haiti'],
  'DO': ['Dominican Republic', 'Dominican Rep.'],
  'PR': ['Puerto Rico'],
  'BS': ['Bahamas'],
  'TT': ['Trinidad and Tobago'],
  'GL': ['Greenland'],
  
  // South America
  'BR': ['Brazil'],
  'AR': ['Argentina'],
  'CL': ['Chile'],
  'CO': ['Colombia'],
  'PE': ['Peru'],
  'VE': ['Venezuela'],
  'EC': ['Ecuador'],
  'BO': ['Bolivia'],
  'PY': ['Paraguay'],
  'UY': ['Uruguay'],
  'GY': ['Guyana'],
  'SR': ['Suriname'],
  'GF': ['French Guiana'],
  'FK': ['Falkland Is.', 'Falkland Islands'],
  
  // Asia
  'CN': ['China'],
  'JP': ['Japan'],
  'KR': ['South Korea', 'Korea'],
  'KP': ['North Korea'],
  'IN': ['India'],
  'PK': ['Pakistan'],
  'BD': ['Bangladesh'],
  'NP': ['Nepal'],
  'BT': ['Bhutan'],
  'LK': ['Sri Lanka'],
  'MM': ['Myanmar'],
  'TH': ['Thailand'],
  'VN': ['Vietnam'],
  'LA': ['Laos'],
  'KH': ['Cambodia'],
  'MY': ['Malaysia'],
  'SG': ['Singapore'],
  'ID': ['Indonesia'],
  'PH': ['Philippines'],
  'TW': ['Taiwan'],
  'MN': ['Mongolia'],
  'KZ': ['Kazakhstan'],
  'UZ': ['Uzbekistan'],
  'TM': ['Turkmenistan'],
  'KG': ['Kyrgyzstan'],
  'TJ': ['Tajikistan'],
  'AF': ['Afghanistan'],
  'GE': ['Georgia'],
  'AM': ['Armenia'],
  'AZ': ['Azerbaijan'],
  'BN': ['Brunei'],
  'TL': ['Timor-Leste'],
  
  // Middle East
  'TR': ['Turkey'],
  'IR': ['Iran'],
  'IQ': ['Iraq'],
  'SA': ['Saudi Arabia'],
  'AE': ['United Arab Emirates'],
  'IL': ['Israel'],
  'JO': ['Jordan'],
  'LB': ['Lebanon'],
  'SY': ['Syria'],
  'YE': ['Yemen'],
  'OM': ['Oman'],
  'KW': ['Kuwait'],
  'QA': ['Qatar'],
  'BH': ['Bahrain'],
  'PS': ['Palestine'],
  
  // Africa
  'EG': ['Egypt'],
  'LY': ['Libya'],
  'TN': ['Tunisia'],
  'DZ': ['Algeria'],
  'MA': ['Morocco'],
  'MR': ['Mauritania'],
  'ML': ['Mali'],
  'NE': ['Niger'],
  'TD': ['Chad'],
  'SD': ['Sudan'],
  'SS': ['South Sudan', 'S. Sudan'],
  'ET': ['Ethiopia'],
  'ER': ['Eritrea'],
  'DJ': ['Djibouti'],
  'SO': ['Somalia'],
  'KE': ['Kenya'],
  'UG': ['Uganda'],
  'TZ': ['Tanzania'],
  'RW': ['Rwanda'],
  'BI': ['Burundi'],
  'CD': ['Democratic Republic of the Congo', 'Dem. Rep. Congo'],
  'CG': ['Republic of the Congo', 'Congo'],
  'CF': ['Central African Republic', 'Central African Rep.'],
  'CM': ['Cameroon'],
  'GA': ['Gabon'],
  'GQ': ['Equatorial Guinea', 'Eq. Guinea'],
  'AO': ['Angola'],
  'ZM': ['Zambia'],
  'ZW': ['Zimbabwe'],
  'MW': ['Malawi'],
  'MZ': ['Mozambique'],
  'BW': ['Botswana'],
  'NA': ['Namibia'],
  'ZA': ['South Africa'],
  'SZ': ['Eswatini'],
  'LS': ['Lesotho'],
  'MG': ['Madagascar'],
  'SN': ['Senegal'],
  'GM': ['Gambia'],
  'GW': ['Guinea-Bissau'],
  'GN': ['Guinea'],
  'SL': ['Sierra Leone'],
  'LR': ['Liberia'],
  'CI': ["Côte d'Ivoire", 'Ivory Coast'],
  'GH': ['Ghana'],
  'TG': ['Togo'],
  'BJ': ['Benin'],
  'BF': ['Burkina Faso'],
  'NG': ['Nigeria'],
  'EH': ['W. Sahara', 'Western Sahara'],
  
  // Oceania
  'AU': ['Australia'],
  'NZ': ['New Zealand'],
  'PG': ['Papua New Guinea'],
  'FJ': ['Fiji'],
  'SB': ['Solomon Islands', 'Solomon Is.'],
  'VU': ['Vanuatu'],
  'NC': ['New Caledonia'],
};

// Reverse mapping: country name -> ISO code
const COUNTRY_NAME_TO_ISO: Record<string, string> = {};
Object.entries(ISO_TO_COUNTRY_NAME).forEach(([iso, names]) => {
  names.forEach(name => {
    COUNTRY_NAME_TO_ISO[name] = iso;
  });
});

// =============================================================================
// STYLES
// =============================================================================

const styles = {
  container: {
    position: 'relative' as const,
    width: '100%',
    height: '100%',
    display: 'flex',
    flexDirection: 'column' as const,
    minHeight: 0,
    overflow: 'hidden',
  },
  mapWrapper: {
    width: '100%',
    flex: 1,
    minHeight: 0,
    position: 'relative' as const,
  } as React.CSSProperties,
  tooltip: {
    position: 'absolute' as const,
    background: 'linear-gradient(135deg, rgba(25, 25, 35, 0.98) 0%, rgba(18, 18, 25, 0.98) 100%)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: 10,
    padding: '12px 16px',
    pointerEvents: 'none' as const,
    zIndex: 100,
    minWidth: 160,
    boxShadow: '0 8px 24px rgba(0,0,0,0.5)',
    backdropFilter: 'blur(8px)',
    transition: 'opacity 0.2s ease',
  },
  tooltipCountry: {
    fontSize: 13,
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.95)',
    marginBottom: 2,
    letterSpacing: '-0.01em',
  },
  tooltipCode: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.4)',
    marginBottom: 8,
  },
  tooltipRow: {
    fontSize: 11,
    color: 'rgba(255, 255, 255, 0.5)',
    marginBottom: 3,
    display: 'flex',
    justifyContent: 'space-between',
    gap: 16,
  },
  tooltipValue: {
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
  },
  loadingOverlay: {
    position: 'absolute' as const,
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'rgba(10, 10, 15, 0.7)',
    color: 'rgba(255, 255, 255, 0.5)',
    fontSize: 12,
    zIndex: 50,
  },
  errorOverlay: {
    position: 'absolute' as const,
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'rgba(10, 10, 15, 0.5)',
    color: 'rgba(255, 100, 100, 0.8)',
    fontSize: 11,
    zIndex: 50,
    padding: 20,
    textAlign: 'center' as const,
  },
  legend: {
    position: 'absolute' as const,
    bottom: 10,
    left: 12,
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 8,
    color: 'rgba(255, 255, 255, 0.35)',
    background: 'rgba(0, 0, 0, 0.3)',
    padding: '5px 8px',
    borderRadius: 5,
    backdropFilter: 'blur(4px)',
  },
  legendBar: {
    display: 'flex',
    height: 4,
    borderRadius: 2,
    overflow: 'hidden',
  },
  statsOverlay: {
    position: 'absolute' as const,
    bottom: 10,
    right: 12,
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.4)',
    background: 'rgba(0, 0, 0, 0.3)',
    padding: '5px 8px',
    borderRadius: 5,
    backdropFilter: 'blur(4px)',
    display: 'flex',
    gap: 10,
  },
  // ==========================================================================
  // COUNTRY SPOTLIGHT (Phase 5A)
  // ==========================================================================
  spotlight: {
    position: 'absolute' as const,
    top: 10,
    left: 12,
    width: 200,
    background: 'linear-gradient(135deg, rgba(20, 20, 30, 0.95) 0%, rgba(15, 15, 22, 0.98) 100%)',
    border: '1px solid rgba(100, 180, 150, 0.15)',
    borderRadius: 10,
    padding: '12px 14px',
    zIndex: 80,
    boxShadow: '0 8px 24px rgba(0,0,0,0.4), inset 0 1px 0 rgba(100, 180, 150, 0.08)',
    backdropFilter: 'blur(8px)',
  },
  spotlightHint: {
    position: 'absolute' as const,
    top: 10,
    left: 12,
    background: 'rgba(0, 0, 0, 0.3)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: 6,
    padding: '6px 10px',
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.35)',
    backdropFilter: 'blur(4px)',
    zIndex: 70,
  },
  contextLabel: {
    position: 'absolute' as const,
    top: 16,
    left: 16,
    background: 'rgba(15, 15, 22, 0.85)',
    border: '1px solid rgba(255, 255, 255, 0.08)',
    borderRadius: 8,
    padding: '10px 14px',
    backdropFilter: 'blur(12px)',
    pointerEvents: 'none' as const,
    zIndex: 60,
  },
  contextLabelTitle: {
    fontSize: 11,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.85)',
    marginBottom: 2,
    letterSpacing: '-0.01em',
  },
  contextLabelSubtitle: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.45)',
    margin: 0,
  },
  spotlightTitle: {
    fontSize: 13,
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.95)',
    marginBottom: 2,
    letterSpacing: '-0.01em',
  },
  spotlightCode: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.4)',
    marginBottom: 10,
  },
  spotlightPrimary: {
    fontSize: 22,
    fontWeight: 700,
    color: 'rgba(100, 200, 150, 1)',
    fontVariantNumeric: 'tabular-nums',
    marginBottom: 2,
    textShadow: '0 0 20px rgba(100, 200, 150, 0.2)',
  },
  spotlightPrimaryLabel: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.08em',
    marginBottom: 10,
  },
  spotlightStats: {
    display: 'flex',
    gap: 16,
    marginBottom: 10,
  },
  spotlightStat: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 1,
  },
  spotlightStatValue: {
    fontSize: 12,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.85)',
    fontVariantNumeric: 'tabular-nums',
  },
  spotlightStatLabel: {
    fontSize: 8,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  },
  spotlightDivider: {
    height: 1,
    background: 'rgba(255, 255, 255, 0.06)',
    margin: '8px 0',
  },
  spotlightExplain: {
    fontSize: 10,
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.7)',
    lineHeight: 1.4,
    marginBottom: 6,
  },
  spotlightBullets: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 3,
  },
  spotlightBullet: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.45)',
    display: 'flex',
    alignItems: 'flex-start',
    gap: 5,
  },
  spotlightBulletDot: {
    color: 'rgba(100, 180, 150, 0.6)',
    fontSize: 8,
    marginTop: 2,
  },
  // ==========================================================================
  // PHASE 7: PINNED COUNTRY DETAIL PANEL
  // ==========================================================================
  pinnedPanel: {
    position: 'absolute' as const,
    top: 10,
    left: 12,
    width: 220,
    background: 'linear-gradient(135deg, rgba(18, 18, 28, 0.98) 0%, rgba(12, 12, 20, 0.99) 100%)',
    border: '1px solid rgba(100, 200, 150, 0.2)',
    borderRadius: 12,
    padding: '14px 16px',
    zIndex: 90,
    boxShadow: '0 12px 32px rgba(0,0,0,0.5), 0 0 20px rgba(100, 200, 150, 0.08), inset 0 1px 0 rgba(100, 200, 150, 0.1)',
    backdropFilter: 'blur(12px)',
  },
  pinnedHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 10,
  },
  pinnedBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
    fontSize: 9,
    fontWeight: 500,
    color: 'rgba(100, 200, 150, 0.9)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.08em',
  },
  pinnedBadgeDot: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    background: 'rgba(100, 200, 150, 0.8)',
  },
  pinnedClearBtn: {
    background: 'rgba(255, 255, 255, 0.06)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: 4,
    padding: '3px 8px',
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.5)',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
  },
  pinnedTitle: {
    fontSize: 15,
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.95)',
    marginBottom: 2,
    letterSpacing: '-0.01em',
  },
  pinnedCode: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.4)',
    marginBottom: 12,
  },
  pinnedPrimary: {
    fontSize: 28,
    fontWeight: 700,
    color: 'rgba(100, 200, 150, 1)',
    fontVariantNumeric: 'tabular-nums',
    marginBottom: 2,
    textShadow: '0 0 24px rgba(100, 200, 150, 0.25)',
  },
  pinnedPrimaryLabel: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.08em',
    marginBottom: 12,
  },
  pinnedStats: {
    display: 'flex',
    gap: 14,
    marginBottom: 12,
    flexWrap: 'wrap' as const,
  },
  pinnedStat: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 2,
  },
  pinnedStatValue: {
    fontSize: 13,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.9)',
    fontVariantNumeric: 'tabular-nums',
  },
  pinnedStatLabel: {
    fontSize: 8,
    color: 'rgba(255, 255, 255, 0.4)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
  },
  pinnedDelta: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 11,
    marginBottom: 4,
  },
  pinnedDeltaPositive: {
    color: 'rgba(100, 200, 150, 0.9)',
  },
  pinnedDeltaNegative: {
    color: 'rgba(255, 150, 100, 0.9)',
  },
  pinnedDeltaNeutral: {
    color: 'rgba(255, 255, 255, 0.5)',
  },
  pinnedDeltaLabel: {
    fontSize: 9,
    color: 'rgba(255, 255, 255, 0.35)',
    marginBottom: 10,
  },
  pinnedDivider: {
    height: 1,
    background: 'rgba(255, 255, 255, 0.08)',
    margin: '10px 0',
  },
  pinnedExplain: {
    fontSize: 11,
    fontWeight: 500,
    color: 'rgba(255, 255, 255, 0.8)',
    lineHeight: 1.4,
    marginBottom: 8,
  },
  pinnedBullets: {
    margin: 0,
    padding: 0,
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 4,
  },
  pinnedBullet: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.5)',
    display: 'flex',
    alignItems: 'flex-start',
    gap: 6,
    lineHeight: 1.35,
  },
  pinnedBulletDot: {
    color: 'rgba(100, 180, 150, 0.7)',
    fontSize: 8,
    marginTop: 3,
  },
  pinnedNoBaseline: {
    fontSize: 10,
    color: 'rgba(255, 255, 255, 0.35)',
    fontStyle: 'italic' as const,
    marginTop: 8,
  },
};

// =============================================================================
// INTENSITY COLOR SCALE
// From cold (no data) to warm (high intensity)
// =============================================================================

const INTENSITY_COLORS = [
  'rgba(30, 35, 45, 0.5)',      // 0: No data
  'rgba(50, 70, 100, 0.6)',     // 1: Very low
  'rgba(60, 100, 140, 0.65)',   // 2: Low
  'rgba(70, 130, 160, 0.7)',    // 3: Medium-low
  'rgba(90, 160, 170, 0.75)',   // 4: Medium
  'rgba(110, 180, 160, 0.8)',   // 5: Medium-high
  'rgba(130, 200, 150, 0.85)',  // 6: High
  'rgba(150, 220, 140, 0.9)',   // 7: Very high
];

const AMBIENT_COLOR = 'rgba(25, 28, 35, 0.4)';

// =============================================================================
// HELPERS
// =============================================================================

function getIsoFromCountryName(countryName: string): string | null {
  return COUNTRY_NAME_TO_ISO[countryName] || null;
}

function getIntensityColor(intensity: number, maxIntensity: number): string {
  if (intensity === 0 || maxIntensity === 0) return INTENSITY_COLORS[0];
  
  // Normalize to 0-1, then map to color index
  const normalized = Math.min(intensity / maxIntensity, 1);
  const colorIndex = Math.min(
    Math.floor(normalized * (INTENSITY_COLORS.length - 1)) + 1,
    INTENSITY_COLORS.length - 1
  );
  
  return INTENSITY_COLORS[colorIndex];
}

function getHighlightedColor(baseColor: string): string {
  return baseColor.replace(/[\d.]+\)$/, (match) => {
    const opacity = Math.min(1, parseFloat(match) * 1.3);
    return `${opacity.toFixed(2)})`;
  });
}

function formatNumber(value: number): string {
  return value.toLocaleString('en-US');
}

function getCountryName(code: string): string {
  try {
    const displayNames = new Intl.DisplayNames(['en'], { type: 'region' });
    return displayNames.of(code) || code;
  } catch {
    return code;
  }
}

// =============================================================================
// SPOTLIGHT EXPLANATION LOGIC
// =============================================================================

interface SpotlightExplanation {
  headline: string;
  bullets: string[];
}

function generateSpotlightExplanation(
  item: RevenueMapDataItem,
  totalSessions: number
): SpotlightExplanation {
  const sharePercent = totalSessions > 0 
    ? (item.sessions / totalSessions) * 100 
    : 0;
  const impressionsPerSession = item.sessions > 0 
    ? item.adImpressions / item.sessions 
    : 0;

  // Determine headline based on data patterns
  let headline: string;
  
  if (item.adImpressions > 0 && impressionsPerSession > 0.8) {
    headline = 'High ad density relative to sessions.';
  } else if (item.adImpressions > 0 && impressionsPerSession > 0) {
    headline = 'Healthy ad delivery rate.';
  } else if (item.adImpressions === 0 && item.sessions > 0) {
    headline = 'Traffic without ad delivery (tracking pending).';
  } else if (sharePercent > 25) {
    headline = 'Concentrated footprint—single market dominant.';
  } else if (sharePercent > 10) {
    headline = 'Significant contributor to overall activity.';
  } else {
    headline = 'Part of a distributed footprint.';
  }

  // Generate bullets
  const bullets: string[] = [];
  
  // Share bullet
  if (totalSessions > 0) {
    if (sharePercent > 25) {
      bullets.push(`${sharePercent.toFixed(1)}% of total sessions (concentrated)`);
    } else if (sharePercent > 10) {
      bullets.push(`${sharePercent.toFixed(1)}% of total sessions (significant)`);
    } else {
      bullets.push(`${sharePercent.toFixed(1)}% of total sessions`);
    }
  }
  
  // Impressions per session bullet
  if (item.sessions > 0) {
    if (item.adImpressions > 0) {
      const densityLabel = impressionsPerSession > 1 
        ? '(high)' 
        : impressionsPerSession > 0.5 
        ? '(moderate)' 
        : '(low)';
      bullets.push(`${impressionsPerSession.toFixed(2)} impressions/session ${densityLabel}`);
    } else {
      bullets.push('No impressions tracked yet');
    }
  }
  
  // Revenue tracking status
  if (item.revenueTotal > 0) {
    bullets.push(`Revenue: ${item.revenueTotal.toFixed(2)} NOK`);
  } else {
    bullets.push('Revenue tracking not enabled');
  }

  return { headline, bullets };
}

// =============================================================================
// PHASE 7: PINNED PANEL EXPLANATION LOGIC
// =============================================================================

interface PinnedPanelExplanation {
  headline: string;
  bullets: string[];
}

function generatePinnedExplanation(
  item: RevenueMapDataItem,
  totalSessions: number,
  previousItem: RevenueMapDataItem | null,
  previousTotalSessions: number
): PinnedPanelExplanation {
  const sharePercent = totalSessions > 0 
    ? (item.sessions / totalSessions) * 100 
    : 0;
  const impressionsPerSession = item.sessions > 0 
    ? item.adImpressions / item.sessions 
    : 0;

  // Previous period metrics
  const prevSharePercent = previousItem && previousTotalSessions > 0
    ? (previousItem.sessions / previousTotalSessions) * 100
    : null;
  const sessionsDelta = previousItem && previousItem.sessions > 0
    ? ((item.sessions - previousItem.sessions) / previousItem.sessions) * 100
    : null;
  const shareDeltaPP = prevSharePercent !== null
    ? sharePercent - prevSharePercent
    : null;

  // Determine headline based on data patterns
  let headline: string;
  
  if (sharePercent > 25) {
    headline = 'Dominant market — drives core revenue.';
  } else if (sharePercent > 15) {
    headline = 'Key market contributor.';
  } else if (sharePercent > 5) {
    headline = 'Significant regional presence.';
  } else if (impressionsPerSession < 0.3 && item.sessions > 0) {
    headline = 'Low ad density — monetization headroom exists.';
  } else if (sessionsDelta !== null && sessionsDelta > 10 && shareDeltaPP !== null && shareDeltaPP > 0) {
    headline = 'Momentum strengthening.';
  } else if (sessionsDelta !== null && sessionsDelta < -10) {
    headline = 'Demand cooling — monitor closely.';
  } else {
    headline = 'Part of distributed footprint.';
  }

  // Generate bullets
  const bullets: string[] = [];
  
  // Share bullet
  if (sharePercent > 20) {
    bullets.push(`Represents ${sharePercent.toFixed(1)}% of total traffic (concentrated)`);
  } else if (sharePercent > 10) {
    bullets.push(`Contributes ${sharePercent.toFixed(1)}% of total traffic`);
  } else {
    bullets.push(`${sharePercent.toFixed(1)}% share of global sessions`);
  }
  
  // Monetization bullet
  if (impressionsPerSession > 0.8) {
    bullets.push(`High ad engagement: ${impressionsPerSession.toFixed(2)} impressions/session`);
  } else if (impressionsPerSession > 0.3) {
    bullets.push(`Moderate ad density: ${impressionsPerSession.toFixed(2)} impressions/session`);
  } else if (item.adImpressions > 0) {
    bullets.push(`Low ad density: ${impressionsPerSession.toFixed(2)} impressions/session`);
  } else {
    bullets.push('No ad impressions tracked yet');
  }
  
  // Trend bullet (if previous data available)
  if (sessionsDelta !== null && shareDeltaPP !== null) {
    if (sessionsDelta > 5 && shareDeltaPP > 0.5) {
      bullets.push('Growing faster than average — gaining share');
    } else if (sessionsDelta < -5 && shareDeltaPP < -0.5) {
      bullets.push('Declining faster than average — losing share');
    } else if (Math.abs(sessionsDelta) < 5) {
      bullets.push('Stable performance vs previous period');
    }
  }

  return { headline, bullets };
}

// =============================================================================
// COMPONENT
// =============================================================================

export function RevenueMapPhase1({
  data,
  loading = false,
  error = null,
  totals,
  hoveredCountryCode,
  onHoverCountry,
  onClickCountry,
  pinnedCountryCode,
  previousData,
  previousTotals,
}: RevenueMapPhase1Props) {
  // Internal hover state (fallback if not controlled)
  const [internalHoveredCode, setInternalHoveredCode] = useState<string | null>(null);
  
  // Determine effective hovered code (controlled or internal)
  // When pinned, still track hover for highlighting but spotlight stays on pinned
  const effectiveHoveredCode = hoveredCountryCode !== undefined 
    ? hoveredCountryCode 
    : internalHoveredCode;
  
  // The code to display in spotlight/panel: pinned takes priority
  const displayCode = pinnedCountryCode || effectiveHoveredCode;

  // Build lookup: ISO code -> data item
  const dataByCode = useMemo(() => {
    const map = new Map<string, RevenueMapDataItem>();
    data.forEach((item) => {
      const code = item.countryCode.toUpperCase();
      map.set(code, item);
    });
    return map;
  }, [data]);

  // Calculate intensity signal (adImpressions if available, else sessions)
  const intensityLookup = useMemo(() => {
    const lookup = new Map<string, number>();
    data.forEach((item) => {
      const code = item.countryCode.toUpperCase();
      const intensity = item.adImpressions > 0 ? item.adImpressions : item.sessions;
      lookup.set(code, intensity);
    });
    return lookup;
  }, [data]);

  // Find max intensity for color scaling
  const maxIntensity = useMemo(() => {
    let max = 0;
    intensityLookup.forEach((value) => {
      if (value > max) max = value;
    });
    return max;
  }, [intensityLookup]);

  // Total stats (use provided totals or compute from data)
  const totalStats = useMemo(() => {
    if (totals) {
      return { 
        sessions: totals.sessions, 
        impressions: totals.adImpressions, 
        countries: data.length 
      };
    }
    let sessions = 0;
    let impressions = 0;
    data.forEach((item) => {
      sessions += item.sessions;
      impressions += item.adImpressions;
    });
    return { sessions, impressions, countries: data.length };
  }, [data, totals]);

  // Get hovered country data for Spotlight (only used when not pinned)
  const spotlightData = useMemo(() => {
    if (pinnedCountryCode) return null; // Don't show spotlight when pinned
    if (!effectiveHoveredCode) return null;
    return dataByCode.get(effectiveHoveredCode) || null;
  }, [effectiveHoveredCode, dataByCode, pinnedCountryCode]);

  // Generate spotlight explanation
  const spotlightExplanation = useMemo(() => {
    if (!spotlightData) return null;
    return generateSpotlightExplanation(spotlightData, totalStats.sessions);
  }, [spotlightData, totalStats.sessions]);

  // Phase 7: Build lookup for previous period data
  const previousDataByCode = useMemo(() => {
    if (!previousData) return new Map<string, RevenueMapDataItem>();
    const map = new Map<string, RevenueMapDataItem>();
    previousData.forEach((item) => {
      const code = item.countryCode.toUpperCase();
      map.set(code, item);
    });
    return map;
  }, [previousData]);

  // Phase 7: Previous period totals
  const previousTotalStats = useMemo(() => {
    if (previousTotals) {
      return { sessions: previousTotals.sessions, impressions: previousTotals.adImpressions };
    }
    return { sessions: 0, impressions: 0 };
  }, [previousTotals]);

  // Phase 7: Get pinned country data
  const pinnedData = useMemo(() => {
    if (!pinnedCountryCode) return null;
    return dataByCode.get(pinnedCountryCode) || null;
  }, [pinnedCountryCode, dataByCode]);

  // Phase 7: Get previous period data for pinned country
  const pinnedPreviousData = useMemo(() => {
    if (!pinnedCountryCode) return null;
    return previousDataByCode.get(pinnedCountryCode) || null;
  }, [pinnedCountryCode, previousDataByCode]);

  // Phase 7: Generate pinned panel explanation
  const pinnedExplanation = useMemo(() => {
    if (!pinnedData) return null;
    return generatePinnedExplanation(
      pinnedData,
      totalStats.sessions,
      pinnedPreviousData,
      previousTotalStats.sessions
    );
  }, [pinnedData, totalStats.sessions, pinnedPreviousData, previousTotalStats.sessions]);

  // Phase 7: Compute deltas for pinned country
  const pinnedDeltas = useMemo(() => {
    if (!pinnedData || !pinnedPreviousData) return null;
    
    const currentShare = totalStats.sessions > 0 
      ? (pinnedData.sessions / totalStats.sessions) * 100 
      : 0;
    const prevShare = previousTotalStats.sessions > 0 
      ? (pinnedPreviousData.sessions / previousTotalStats.sessions) * 100 
      : 0;
    
    const sessionsDeltaPct = pinnedPreviousData.sessions > 0
      ? ((pinnedData.sessions - pinnedPreviousData.sessions) / pinnedPreviousData.sessions) * 100
      : 0;
    const shareDeltaPP = currentShare - prevShare;
    
    return { sessionsDeltaPct, shareDeltaPP, currentShare };
  }, [pinnedData, pinnedPreviousData, totalStats.sessions, previousTotalStats.sessions]);

  const handleMouseEnter = useCallback(
    (_event: React.MouseEvent, geo: { properties: { name: string } }) => {
      const countryName = geo.properties.name;
      const isoCode = getIsoFromCountryName(countryName);
      
      if (!isoCode) return;
      
      // Update hover state
      if (onHoverCountry) {
        onHoverCountry(isoCode);
      } else {
        setInternalHoveredCode(isoCode);
      }
    },
    [onHoverCountry]
  );

  const handleMouseLeave = useCallback(() => {
    if (onHoverCountry) {
      onHoverCountry(null);
    } else {
      setInternalHoveredCode(null);
    }
  }, [onHoverCountry]);

  const handleClick = useCallback(
    (_event: React.MouseEvent, geo: { properties: { name: string } }) => {
      if (!onClickCountry) return;
      
      const countryName = geo.properties.name;
      const isoCode = getIsoFromCountryName(countryName);
      
      if (isoCode) {
        onClickCountry(isoCode);
      }
    },
    [onClickCountry]
  );

  return (
    <div style={styles.container}>
      <div style={styles.mapWrapper}>
        <ComposableMap
          projection="geoEqualEarth"
          projectionConfig={{
            scale: 180,
            center: [10, 5],
          }}
          style={{ width: '100%', height: '100%' }}
        >
          <Geographies geography={GEO_URL}>
            {({ geographies }) =>
              geographies.map((geo) => {
                const countryName = geo.properties.name;
                const isoCode = getIsoFromCountryName(countryName);
                
                // Get intensity for this country
                const intensity = isoCode ? (intensityLookup.get(isoCode) || 0) : 0;
                const hasData = intensity > 0;
                
                // Determine fill color based on intensity
                const fillColor = hasData
                  ? getIntensityColor(intensity, maxIntensity)
                  : AMBIENT_COLOR;
                
                const strokeColor = hasData
                  ? 'rgba(255, 255, 255, 0.15)'
                  : 'rgba(255, 255, 255, 0.04)';

                // Check if this country is currently hovered or pinned (for highlighting)
                const isHovered = isoCode === effectiveHoveredCode;
                const isPinned = isoCode === pinnedCountryCode;
                const isHighlighted = (isHovered || isPinned) && hasData;

                return (
                  <Geography
                    key={geo.rsmKey}
                    geography={geo}
                    onMouseEnter={(e) => handleMouseEnter(e, geo)}
                    onMouseLeave={handleMouseLeave}
                    onClick={(e) => handleClick(e, geo)}
                    style={{
                      default: {
                        fill: isHighlighted ? getHighlightedColor(fillColor) : fillColor,
                        stroke: isPinned && hasData 
                          ? 'rgba(100, 200, 150, 0.8)' 
                          : isHovered && hasData 
                          ? 'rgba(100, 200, 150, 0.5)' 
                          : strokeColor,
                        strokeWidth: isPinned && hasData ? 1.5 : isHovered && hasData ? 1 : 0.3,
                        outline: 'none',
                        cursor: hasData ? 'pointer' : 'default',
                        transition: 'fill 0.15s ease, stroke 0.15s ease',
                      },
                      hover: {
                        fill: hasData ? getHighlightedColor(fillColor) : fillColor,
                        stroke: hasData ? 'rgba(100, 200, 150, 0.5)' : strokeColor,
                        strokeWidth: hasData ? 1 : 0.3,
                        outline: 'none',
                        cursor: hasData ? 'pointer' : 'default',
                        transition: 'fill 0.15s ease, stroke 0.15s ease',
                      },
                      pressed: {
                        fill: fillColor,
                        stroke: strokeColor,
                        strokeWidth: 0.3,
                        outline: 'none',
                      },
                    }}
                  />
                );
              })
            }
          </Geographies>
        </ComposableMap>
      </div>

      {/* Legend */}
      <div style={styles.legend}>
        <span>Density:</span>
        <div style={styles.legendBar}>
          {INTENSITY_COLORS.slice(1).map((color, i) => (
            <div
              key={i}
              style={{
                width: 12,
                height: '100%',
                background: color,
              }}
            />
          ))}
        </div>
        <span>High</span>
      </div>

      {/* Stats overlay */}
      {!loading && !error && totalStats.countries > 0 && (
        <div style={styles.statsOverlay}>
          <span>{totalStats.countries} countries</span>
          <span>{formatNumber(totalStats.sessions)} sessions</span>
        </div>
      )}

      {/* Phase 7: Pinned Country Detail Panel */}
      {!loading && !error && pinnedData && pinnedExplanation && (
        <div style={styles.pinnedPanel}>
          <div style={styles.pinnedHeader}>
            <div style={styles.pinnedBadge}>
              <div style={styles.pinnedBadgeDot} />
              <span>Pinned</span>
            </div>
            <button
              style={styles.pinnedClearBtn}
              onClick={() => onClickCountry?.(pinnedData.countryCode)}
              onMouseOver={(e) => {
                e.currentTarget.style.background = 'rgba(255, 255, 255, 0.1)';
                e.currentTarget.style.color = 'rgba(255, 255, 255, 0.8)';
              }}
              onMouseOut={(e) => {
                e.currentTarget.style.background = 'rgba(255, 255, 255, 0.06)';
                e.currentTarget.style.color = 'rgba(255, 255, 255, 0.5)';
              }}
            >
              Clear
            </button>
          </div>
          
          <div style={styles.pinnedTitle}>
            {getCountryName(pinnedData.countryCode)}
          </div>
          <div style={styles.pinnedCode}>{pinnedData.countryCode}</div>
          
          <div style={styles.pinnedPrimary}>
            {formatNumber(pinnedData.sessions)}
          </div>
          <div style={styles.pinnedPrimaryLabel}>Sessions</div>
          
          {/* Delta row (if previous data exists) */}
          {pinnedDeltas && (
            <>
              <div style={styles.pinnedDelta}>
                <span style={
                  pinnedDeltas.sessionsDeltaPct > 0 
                    ? styles.pinnedDeltaPositive 
                    : pinnedDeltas.sessionsDeltaPct < 0 
                    ? styles.pinnedDeltaNegative 
                    : styles.pinnedDeltaNeutral
                }>
                  {pinnedDeltas.sessionsDeltaPct > 0 ? '+' : ''}
                  {pinnedDeltas.sessionsDeltaPct.toFixed(1)}% sessions
                </span>
                <span style={
                  pinnedDeltas.shareDeltaPP > 0 
                    ? styles.pinnedDeltaPositive 
                    : pinnedDeltas.shareDeltaPP < 0 
                    ? styles.pinnedDeltaNegative 
                    : styles.pinnedDeltaNeutral
                }>
                  {pinnedDeltas.shareDeltaPP > 0 ? '+' : ''}
                  {pinnedDeltas.shareDeltaPP.toFixed(1)}pp share
                </span>
              </div>
              <div style={styles.pinnedDeltaLabel}>vs previous period</div>
            </>
          )}
          
          <div style={styles.pinnedStats}>
            <div style={styles.pinnedStat}>
              <span style={styles.pinnedStatValue}>
                {totalStats.sessions > 0 
                  ? `${((pinnedData.sessions / totalStats.sessions) * 100).toFixed(1)}%`
                  : '—'}
              </span>
              <span style={styles.pinnedStatLabel}>Share</span>
            </div>
            <div style={styles.pinnedStat}>
              <span style={styles.pinnedStatValue}>
                {formatNumber(pinnedData.adImpressions)}
              </span>
              <span style={styles.pinnedStatLabel}>Impressions</span>
            </div>
            <div style={styles.pinnedStat}>
              <span style={styles.pinnedStatValue}>
                {pinnedData.sessions > 0 
                  ? (pinnedData.adImpressions / pinnedData.sessions).toFixed(2)
                  : '—'}
              </span>
              <span style={styles.pinnedStatLabel}>Imp/Sess</span>
            </div>
          </div>
          
          <div style={styles.pinnedDivider} />
          
          <div style={styles.pinnedExplain}>
            {pinnedExplanation.headline}
          </div>
          
          <ul style={styles.pinnedBullets}>
            {pinnedExplanation.bullets.map((bullet, i) => (
              <li key={i} style={styles.pinnedBullet}>
                <span style={styles.pinnedBulletDot}>•</span>
                <span>{bullet}</span>
              </li>
            ))}
          </ul>
          
          {/* No baseline message if previous data doesn't exist */}
          {!pinnedPreviousData && previousData && previousData.length > 0 && (
            <p style={styles.pinnedNoBaseline}>
              No previous-period baseline for this country.
            </p>
          )}
        </div>
      )}

      {/* Country Spotlight Panel (Phase 5A) - only when not pinned */}
      {!loading && !error && spotlightData && spotlightExplanation && (
        <div style={styles.spotlight}>
          <div style={styles.spotlightTitle}>
            {getCountryName(spotlightData.countryCode)}
          </div>
          <div style={styles.spotlightCode}>{spotlightData.countryCode}</div>
          
          <div style={styles.spotlightPrimary}>
            {formatNumber(spotlightData.sessions)}
          </div>
          <div style={styles.spotlightPrimaryLabel}>Sessions</div>
          
          <div style={styles.spotlightStats}>
            <div style={styles.spotlightStat}>
              <span style={styles.spotlightStatValue}>
                {formatNumber(spotlightData.adImpressions)}
              </span>
              <span style={styles.spotlightStatLabel}>Impressions</span>
            </div>
            <div style={styles.spotlightStat}>
              <span style={styles.spotlightStatValue}>
                {totalStats.sessions > 0 
                  ? `${((spotlightData.sessions / totalStats.sessions) * 100).toFixed(1)}%`
                  : '—'}
              </span>
              <span style={styles.spotlightStatLabel}>Share</span>
            </div>
            <div style={styles.spotlightStat}>
              <span style={styles.spotlightStatValue}>
                {spotlightData.sessions > 0 
                  ? (spotlightData.adImpressions / spotlightData.sessions).toFixed(2)
                  : '—'}
              </span>
              <span style={styles.spotlightStatLabel}>Imp/Sess</span>
            </div>
          </div>
          
          <div style={styles.spotlightDivider} />
          
          <div style={styles.spotlightExplain}>
            {spotlightExplanation.headline}
          </div>
          
          <ul style={styles.spotlightBullets}>
            {spotlightExplanation.bullets.map((bullet, i) => (
              <li key={i} style={styles.spotlightBullet}>
                <span style={styles.spotlightBulletDot}>•</span>
                <span>{bullet}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Contextual label when no country is hovered or pinned */}
      {!loading && !error && !spotlightData && !pinnedData && totalStats.countries > 0 && (
        <div style={styles.contextLabel}>
          <div style={styles.contextLabelTitle}>Geographic Revenue Distribution</div>
          <p style={styles.contextLabelSubtitle}>Click a country to pin details</p>
        </div>
      )}

      {/* Loading overlay */}
      {loading && (
        <div style={styles.loadingOverlay}>
          Loading revenue map…
        </div>
      )}

      {/* Error overlay */}
      {error && !loading && (
        <div style={styles.errorOverlay}>
          {error}
        </div>
      )}
    </div>
  );
}
