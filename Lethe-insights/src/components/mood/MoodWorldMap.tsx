import { useState, useMemo, useCallback } from 'react';
import {
  ComposableMap,
  Geographies,
  Geography,
} from 'react-simple-maps';

// =============================================================================
// TYPES
// =============================================================================

export interface RegionData {
  region: string;
  balanceScore: number;
  deltaBalanceScore: number;
  totalConfessions: number;
  positiveShare: number;
  negativeShare: number;
}

interface MoodWorldMapProps {
  regions: RegionData[];
  observedRegion: string | null;
  onSelectRegion: (region: string | null) => void;
  loading?: boolean;
}

// =============================================================================
// GEO JSON URL (Natural Earth)
// =============================================================================

const GEO_URL = 'https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json';

// =============================================================================
// COUNTRY TO REGION MAPPING
// =============================================================================

const COUNTRY_TO_REGION: Record<string, string> = {
  // Europe
  'Albania': 'Europe', 'Andorra': 'Europe', 'Austria': 'Europe', 'Belarus': 'Europe',
  'Belgium': 'Europe', 'Bosnia and Herzegovina': 'Europe', 'Bosnia and Herz.': 'Europe',
  'Bulgaria': 'Europe', 'Croatia': 'Europe', 'Cyprus': 'Europe', 'Czechia': 'Europe',
  'Czech Republic': 'Europe', 'Denmark': 'Europe', 'Estonia': 'Europe', 'Finland': 'Europe',
  'France': 'Europe', 'Germany': 'Europe', 'Greece': 'Europe', 'Hungary': 'Europe',
  'Iceland': 'Europe', 'Ireland': 'Europe', 'Italy': 'Europe', 'Kosovo': 'Europe',
  'Latvia': 'Europe', 'Liechtenstein': 'Europe', 'Lithuania': 'Europe', 'Luxembourg': 'Europe',
  'Malta': 'Europe', 'Moldova': 'Europe', 'Monaco': 'Europe', 'Montenegro': 'Europe',
  'Netherlands': 'Europe', 'North Macedonia': 'Europe', 'N. Macedonia': 'Europe',
  'Norway': 'Europe', 'Poland': 'Europe', 'Portugal': 'Europe', 'Romania': 'Europe',
  'Russia': 'Europe', 'San Marino': 'Europe', 'Serbia': 'Europe', 'Slovakia': 'Europe',
  'Slovenia': 'Europe', 'Spain': 'Europe', 'Sweden': 'Europe', 'Switzerland': 'Europe',
  'Ukraine': 'Europe', 'United Kingdom': 'Europe', 'Vatican City': 'Europe',

  // North America
  'Canada': 'North America', 'United States of America': 'North America',
  'United States': 'North America', 'USA': 'North America',
  'Mexico': 'North America', 'Greenland': 'North America',
  'Guatemala': 'North America', 'Belize': 'North America', 'Honduras': 'North America',
  'El Salvador': 'North America', 'Nicaragua': 'North America', 'Costa Rica': 'North America',
  'Panama': 'North America', 'Cuba': 'North America', 'Jamaica': 'North America',
  'Haiti': 'North America', 'Dominican Republic': 'North America', 'Dominican Rep.': 'North America',
  'Puerto Rico': 'North America', 'Bahamas': 'North America', 'Trinidad and Tobago': 'North America',

  // South America
  'Argentina': 'South America', 'Bolivia': 'South America', 'Brazil': 'South America',
  'Chile': 'South America', 'Colombia': 'South America', 'Ecuador': 'South America',
  'Guyana': 'South America', 'Paraguay': 'South America', 'Peru': 'South America',
  'Suriname': 'South America', 'Uruguay': 'South America', 'Venezuela': 'South America',
  'Fr. S. Antarctic Lands': 'South America', 'Falkland Is.': 'South America',

  // Asia
  'Afghanistan': 'Asia', 'Armenia': 'Asia', 'Azerbaijan': 'Asia', 'Bangladesh': 'Asia',
  'Bhutan': 'Asia', 'Brunei': 'Asia', 'Cambodia': 'Asia', 'China': 'Asia',
  'Georgia': 'Asia', 'India': 'Asia', 'Indonesia': 'Asia', 'Japan': 'Asia',
  'Kazakhstan': 'Asia', 'Kyrgyzstan': 'Asia', 'Laos': 'Asia', 'Malaysia': 'Asia',
  'Maldives': 'Asia', 'Mongolia': 'Asia', 'Myanmar': 'Asia', 'Nepal': 'Asia',
  'North Korea': 'Asia', 'Pakistan': 'Asia', 'Philippines': 'Asia', 'Singapore': 'Asia',
  'South Korea': 'Asia', 'Korea': 'Asia', 'Sri Lanka': 'Asia', 'Taiwan': 'Asia',
  'Tajikistan': 'Asia', 'Thailand': 'Asia', 'Timor-Leste': 'Asia', 'Turkmenistan': 'Asia',
  'Uzbekistan': 'Asia', 'Vietnam': 'Asia',

  // Middle East
  'Bahrain': 'Middle East', 'Iran': 'Middle East', 'Iraq': 'Middle East', 'Israel': 'Middle East',
  'Jordan': 'Middle East', 'Kuwait': 'Middle East', 'Lebanon': 'Middle East', 'Oman': 'Middle East',
  'Palestine': 'Middle East', 'Qatar': 'Middle East', 'Saudi Arabia': 'Middle East',
  'Syria': 'Middle East', 'Turkey': 'Middle East', 'United Arab Emirates': 'Middle East',
  'Yemen': 'Middle East',

  // Africa
  'Algeria': 'Africa', 'Angola': 'Africa', 'Benin': 'Africa', 'Botswana': 'Africa',
  'Burkina Faso': 'Africa', 'Burundi': 'Africa', 'Cameroon': 'Africa', 'Cape Verde': 'Africa',
  'Central African Republic': 'Africa', 'Central African Rep.': 'Africa', 'Chad': 'Africa',
  'Comoros': 'Africa', 'Democratic Republic of the Congo': 'Africa', 'Dem. Rep. Congo': 'Africa',
  'Republic of the Congo': 'Africa', 'Congo': 'Africa', "Côte d'Ivoire": 'Africa',
  'Ivory Coast': 'Africa', 'Djibouti': 'Africa', 'Egypt': 'Africa', 'Equatorial Guinea': 'Africa',
  'Eq. Guinea': 'Africa', 'Eritrea': 'Africa', 'Eswatini': 'Africa', 'Ethiopia': 'Africa',
  'Gabon': 'Africa', 'Gambia': 'Africa', 'Ghana': 'Africa', 'Guinea': 'Africa',
  'Guinea-Bissau': 'Africa', 'Kenya': 'Africa', 'Lesotho': 'Africa', 'Liberia': 'Africa',
  'Libya': 'Africa', 'Madagascar': 'Africa', 'Malawi': 'Africa', 'Mali': 'Africa',
  'Mauritania': 'Africa', 'Mauritius': 'Africa', 'Morocco': 'Africa', 'Mozambique': 'Africa',
  'Namibia': 'Africa', 'Niger': 'Africa', 'Nigeria': 'Africa', 'Rwanda': 'Africa',
  'São Tomé and Príncipe': 'Africa', 'Senegal': 'Africa', 'Seychelles': 'Africa',
  'Sierra Leone': 'Africa', 'Somalia': 'Africa', 'Somaliland': 'Africa', 'South Africa': 'Africa',
  'South Sudan': 'Africa', 'S. Sudan': 'Africa', 'Sudan': 'Africa', 'Tanzania': 'Africa',
  'Togo': 'Africa', 'Tunisia': 'Africa', 'Uganda': 'Africa', 'W. Sahara': 'Africa',
  'Western Sahara': 'Africa', 'Zambia': 'Africa', 'Zimbabwe': 'Africa',

  // Oceania
  'Australia': 'Oceania', 'Fiji': 'Oceania', 'Kiribati': 'Oceania', 'Marshall Islands': 'Oceania',
  'Micronesia': 'Oceania', 'Nauru': 'Oceania', 'New Zealand': 'Oceania', 'Palau': 'Oceania',
  'Papua New Guinea': 'Oceania', 'Samoa': 'Oceania', 'Solomon Islands': 'Oceania',
  'Solomon Is.': 'Oceania', 'Tonga': 'Oceania', 'Tuvalu': 'Oceania', 'Vanuatu': 'Oceania',
  'New Caledonia': 'Oceania',
};

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
  scanOverlay: {
    position: 'absolute' as const,
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    pointerEvents: 'none' as const,
    zIndex: 5,
    background: 'linear-gradient(90deg, transparent 0%, rgba(100, 180, 255, 0.02) 50%, transparent 100%)',
    backgroundSize: '200% 100%',
    animation: 'ambientScan 25s ease-in-out infinite',
  } as React.CSSProperties,
  focusLabel: {
    position: 'absolute' as const,
    top: 14,
    right: 16,
    fontSize: 9,
    fontWeight: 600,
    color: 'rgba(255, 255, 255, 0.5)',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.1em',
    zIndex: 10,
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    background: 'rgba(0, 0, 0, 0.3)',
    padding: '6px 10px',
    borderRadius: 6,
    backdropFilter: 'blur(4px)',
    transition: 'opacity 0.7s ease',
  },
  focusRegionName: {
    color: 'rgba(100, 180, 255, 0.8)',
    fontWeight: 700,
  },
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
    transition: 'opacity 0.3s ease',
  },
  tooltipRegion: {
    fontSize: 14,
    fontWeight: 700,
    color: 'rgba(255, 255, 255, 0.95)',
    marginBottom: 8,
    letterSpacing: '-0.01em',
  },
  tooltipRow: {
    fontSize: 11,
    color: 'rgba(255, 255, 255, 0.5)',
    marginBottom: 4,
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
    fontSize: 13,
  },
  legend: {
    position: 'absolute' as const,
    bottom: 14,
    right: 16,
    display: 'flex',
    gap: 14,
    fontSize: 8,
    color: 'rgba(255, 255, 255, 0.35)',
    background: 'rgba(0, 0, 0, 0.3)',
    padding: '6px 10px',
    borderRadius: 6,
    backdropFilter: 'blur(4px)',
  },
  legendItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 4,
  },
  legendDot: {
    width: 6,
    height: 6,
    borderRadius: 2,
  },
};

// =============================================================================
// HELPERS
// =============================================================================

const AMBIENT_COLOR = 'rgba(35, 38, 48, 0.6)';
const AMBIENT_COLOR_DIM = 'rgba(28, 30, 38, 0.4)';

function getBalanceColor(score: number | undefined, hasData: boolean): string {
  if (!hasData || score === undefined) return AMBIENT_COLOR;
  if (score > 0.1) return 'rgba(80, 180, 120, 0.7)';
  if (score > 0.02) return 'rgba(90, 170, 125, 0.55)';
  if (score < -0.1) return 'rgba(180, 90, 90, 0.7)';
  if (score < -0.02) return 'rgba(170, 100, 95, 0.55)';
  return 'rgba(75, 80, 95, 0.5)';
}

function getDimmedColor(baseColor: string, isAmbient: boolean): string {
  if (isAmbient) return AMBIENT_COLOR_DIM;
  return baseColor.replace(/[\d.]+\)$/, (match) => {
    const opacity = parseFloat(match) * 0.3;
    return `${opacity.toFixed(2)})`;
  });
}

function getHighlightedColor(baseColor: string): string {
  return baseColor.replace(/[\d.]+\)$/, (match) => {
    const opacity = Math.min(1, parseFloat(match) * 1.4);
    return `${opacity.toFixed(2)})`;
  });
}

function getDeltaArrow(delta: number): string {
  if (delta > 0.01) return '↑';
  if (delta < -0.01) return '↓';
  return '→';
}

function getDeltaColor(delta: number): string {
  if (delta > 0.01) return 'rgba(100, 200, 150, 1)';
  if (delta < -0.01) return 'rgba(200, 120, 120, 1)';
  return 'rgba(255, 255, 255, 0.6)';
}

// =============================================================================
// COMPONENT
// =============================================================================

export function MoodWorldMap({
  regions,
  observedRegion,
  onSelectRegion,
  loading = false,
}: MoodWorldMapProps) {
  const [tooltip, setTooltip] = useState<{
    x: number;
    y: number;
    region: string;
    data: RegionData | null;
  } | null>(null);

  const regionDataMap = useMemo(() => {
    const map = new Map<string, RegionData>();
    regions.forEach((r) => map.set(r.region, r));
    return map;
  }, [regions]);

  const getRegionFromCountry = useCallback((countryName: string): string | null => {
    const region = COUNTRY_TO_REGION[countryName];
    if (!region || region === 'Unknown') return null;
    return region;
  }, []);

  const handleMouseEnter = useCallback(
    (event: React.MouseEvent, geo: { properties: { name: string } }) => {
      const countryName = geo.properties.name;
      const regionName = getRegionFromCountry(countryName);
      if (!regionName) return;
      
      const data = regionDataMap.get(regionName) || null;
      const rect = (event.currentTarget as HTMLElement).closest('svg')?.getBoundingClientRect();
      if (rect) {
        setTooltip({
          x: event.clientX - rect.left + 10,
          y: event.clientY - rect.top - 10,
          region: regionName,
          data,
        });
      }
    },
    [getRegionFromCountry, regionDataMap]
  );

  const handleMouseLeave = useCallback(() => {
    setTooltip(null);
  }, []);

  const handleClick = useCallback(
    (geo: { properties: { name: string } }) => {
      const countryName = geo.properties.name;
      const regionName = getRegionFromCountry(countryName);
      if (regionName) {
        onSelectRegion(regionName);
      }
    },
    [getRegionFromCountry, onSelectRegion]
  );

  const handleBackgroundClick = useCallback(() => {
    onSelectRegion(null);
  }, [onSelectRegion]);

  return (
    <div style={styles.container}>
      {/* Keyframes for ambient scan */}
      <style>
        {`
          @keyframes ambientScan {
            0%, 100% { background-position: -100% 0; }
            50% { background-position: 200% 0; }
          }
        `}
      </style>

      {/* Focus label */}
      {observedRegion && (
        <div style={styles.focusLabel}>
          <span>Focus:</span>
          <span style={styles.focusRegionName}>{observedRegion}</span>
        </div>
      )}

      <div style={styles.mapWrapper}>
        {/* Ambient scan overlay */}
        <div style={styles.scanOverlay} />
        
        <ComposableMap
          projection="geoEqualEarth"
          projectionConfig={{
            scale: 200,
            center: [10, 0],
          }}
          style={{ width: '100%', height: '100%' }}
        >
          <rect
            x={-500}
            y={-300}
            width={1500}
            height={1000}
            fill="transparent"
            onClick={handleBackgroundClick}
            style={{ cursor: 'default' }}
          />

          <Geographies geography={GEO_URL}>
            {({ geographies }) =>
              geographies.map((geo) => {
                const countryName = geo.properties.name;
                const regionName = getRegionFromCountry(countryName);
                
                // Skip countries with unknown/missing region
                if (!regionName) {
                  return (
                    <Geography
                      key={geo.rsmKey}
                      geography={geo}
                      style={{
                        default: { fill: 'transparent', stroke: 'transparent', outline: 'none' },
                        hover: { fill: 'transparent', stroke: 'transparent', outline: 'none' },
                        pressed: { fill: 'transparent', stroke: 'transparent', outline: 'none' },
                      }}
                    />
                  );
                }

                const regionData = regionDataMap.get(regionName);
                const hasData = regionData !== undefined;
                const isObserved = observedRegion === regionName;
                const isOtherRegionObserved = observedRegion !== null && observedRegion !== regionName;
                
                const baseColor = getBalanceColor(regionData?.balanceScore, hasData);
                
                // Simple highlight/dim logic - no zoom, no transform
                let fillColor: string;
                if (isObserved) {
                  fillColor = getHighlightedColor(baseColor);
                } else if (isOtherRegionObserved) {
                  fillColor = getDimmedColor(baseColor, !hasData);
                } else {
                  fillColor = baseColor;
                }

                const strokeColor = isObserved
                  ? 'rgba(100, 180, 255, 0.5)'
                  : isOtherRegionObserved
                  ? 'rgba(255, 255, 255, 0.02)'
                  : 'rgba(255, 255, 255, 0.06)';
                const strokeWidth = isObserved ? 1.5 : 0.3;

                return (
                  <Geography
                    key={geo.rsmKey}
                    geography={geo}
                    onMouseEnter={(e) => handleMouseEnter(e, geo)}
                    onMouseLeave={handleMouseLeave}
                    onClick={() => handleClick(geo)}
                    style={{
                      default: {
                        fill: fillColor,
                        stroke: strokeColor,
                        strokeWidth: strokeWidth,
                        outline: 'none',
                        cursor: 'default',
                        transition: 'fill 1.2s ease, stroke 1.2s ease, stroke-width 1.2s ease',
                      },
                      hover: {
                        fill: isObserved ? fillColor : getHighlightedColor(baseColor),
                        stroke: isObserved ? 'rgba(100, 180, 255, 0.6)' : 'rgba(255, 255, 255, 0.25)',
                        strokeWidth: isObserved ? 1.5 : 0.8,
                        outline: 'none',
                        cursor: 'default',
                        transition: 'fill 0.3s ease, stroke 0.3s ease',
                      },
                      pressed: {
                        fill: fillColor,
                        stroke: strokeColor,
                        strokeWidth: strokeWidth,
                        outline: 'none',
                        cursor: 'default',
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
        <div style={styles.legendItem}>
          <div style={{ ...styles.legendDot, background: 'rgba(80, 180, 120, 0.7)' }} />
          <span>Positive</span>
        </div>
        <div style={styles.legendItem}>
          <div style={{ ...styles.legendDot, background: 'rgba(75, 80, 95, 0.5)' }} />
          <span>Neutral</span>
        </div>
        <div style={styles.legendItem}>
          <div style={{ ...styles.legendDot, background: 'rgba(180, 90, 90, 0.7)' }} />
          <span>Negative</span>
        </div>
      </div>

      {/* Tooltip - secondary interaction */}
      {tooltip && (
        <div
          style={{
            ...styles.tooltip,
            left: tooltip.x,
            top: tooltip.y,
          }}
        >
          <div style={styles.tooltipRegion}>{tooltip.region}</div>
          {tooltip.data ? (
            <>
              <div style={styles.tooltipRow}>
                <span>Balance</span>
                <span style={{
                  ...styles.tooltipValue,
                  color: tooltip.data.balanceScore > 0.02
                    ? 'rgba(100, 200, 150, 1)'
                    : tooltip.data.balanceScore < -0.02
                    ? 'rgba(200, 120, 120, 1)'
                    : 'rgba(255, 255, 255, 0.85)',
                }}>
                  {tooltip.data.balanceScore >= 0 ? '+' : ''}
                  {tooltip.data.balanceScore.toFixed(2)}
                </span>
              </div>
              <div style={styles.tooltipRow}>
                <span>Delta</span>
                <span style={{
                  ...styles.tooltipValue,
                  color: getDeltaColor(tooltip.data.deltaBalanceScore),
                }}>
                  {getDeltaArrow(tooltip.data.deltaBalanceScore)}{' '}
                  {Math.abs(tooltip.data.deltaBalanceScore).toFixed(2)}
                </span>
              </div>
              <div style={styles.tooltipRow}>
                <span>Confessions</span>
                <span style={styles.tooltipValue}>
                  {tooltip.data.totalConfessions.toLocaleString()}
                </span>
              </div>
            </>
          ) : (
            <div style={{ ...styles.tooltipRow, justifyContent: 'center' }}>
              <span>No data</span>
            </div>
          )}
        </div>
      )}

      {/* Loading overlay */}
      {loading && (
        <div style={styles.loadingOverlay}>
          Loading map data...
        </div>
      )}
    </div>
  );
}
