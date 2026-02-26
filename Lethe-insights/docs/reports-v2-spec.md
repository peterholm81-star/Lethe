# Reports v2 Specification — Map-First Dashboard

**Status:** LOCKED SPEC  
**Version:** 2.0  
**Last Updated:** 2026-02-03

---

## 1. Core Purpose

Reports v2 answers **6 key questions** at a glance:

| # | Question | Answered By |
|---|----------|-------------|
| 1 | How many reports right now? | Signals row: total reports |
| 2 | Where are reports coming from? | World map (heat/markers) |
| 3 | What's being reported? | Breakdown panel: top reasons |
| 4 | Is it getting worse? | Trend chart: reports over time |
| 5 | What needs action? | Inbox: unhandled reports |
| 6 | What did we do? | Actions log: recent moderation |

---

## 2. Layout Sections

```
┌─────────────────────────────────────────────────────────────────┐
│ FILTER BAR                                                       │
│ [60m] [24h] [7d] [30d]  |  Region ▼  Country ▼  City ▼  [Reset] │
├─────────────────────────────────────────────────────────────────┤
│ SIGNALS ROW (6 compact KPIs)                                     │
│ Reports | /1k Reads | Hidden | Severity | Spike | Actions        │
├───────────────────────────────────────┬─────────────────────────┤
│                                       │ RIGHT PANEL             │
│       WORLD MAP (main visual)         │ • Top Countries (5)     │
│       - Heat overlay or markers       │ • Top Cities (5)        │
│       - Hover: tooltip                │ • Top Reasons (5)       │
│       - Click: drilldown              │                         │
│                                       │ [View Breakdown →]      │
├───────────────────────────────────────┴─────────────────────────┤
│ TREND SECTION                                                    │
│ Line/bar chart: reports over time (hourly for <24h, daily else) │
├─────────────────────────────────────────────────────────────────┤
│ INBOX (collapsed by default, expandable)                         │
│ Unhandled reports table with Handle/Hide actions                 │
├─────────────────────────────────────────────────────────────────┤
│ ACTIONS LOG (collapsed by default)                               │
│ Recent moderation actions with timestamps                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Filters

### 3.1 Time Range (required)

| Value | Label | Granularity |
|-------|-------|-------------|
| `60m` | Last 60 min | per-minute or 5-min buckets |
| `24h` | Last 24 hours | hourly buckets |
| `7d` | Last 7 days | daily buckets |
| `30d` | Last 30 days | daily buckets |

**Default:** `24h`

### 3.2 Geo Filters (optional, cascading)

| Filter | Source | Cascades To |
|--------|--------|-------------|
| `region` | `confessions.region` | Clears country, city |
| `country_code` | Derived from city_code | Clears city |
| `city_code` | `confession_reports.city_code` | — |

### 3.3 Reset Rules

- Clicking **Reset** clears all geo filters, keeps time range at `24h`
- Changing `region` → clears `country_code` and `city_code`
- Changing `country_code` → clears `city_code`
- Map click on country → sets `country_code`, clears `city_code`
- Map click on city → sets `city_code`

---

## 4. Map-First UX

### 4.1 Hover Behavior

```
┌──────────────────────┐
│ 🇺🇸 United States    │
│ 142 reports          │
│ Top: SPAM (38%)      │
│ ↑ +23% vs prev       │
└──────────────────────┘
```

- Tooltip appears on hover over country/city marker
- Shows: name, report count, top reason, trend vs previous period
- No click required for quick scan

### 4.2 Click Drilldown

- **Click country** → Filter to that country, zoom map, update all panels
- **Click city** (v2) → Filter to city, show city-level breakdown
- **Click empty area** → Reset geo filter to global view

### 4.3 Live Feel

- Auto-refresh every 60s when `60m` range selected
- Manual refresh button always visible
- Loading states: skeleton for map, spinner for panels
- Stale indicator if data > 2 min old

---

## 5. RPC Contracts

### 5.1 `get_reports_overview_v2`

**Purpose:** Single-row summary for Signals row

```sql
FUNCTION get_reports_overview_v2(
  p_range text,           -- '60m' | '24h' | '7d' | '30d'
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL
)
RETURNS TABLE (
  reports_total bigint,
  reports_unhandled bigint,
  confessions_reported bigint,
  reads_total bigint,
  reports_per_1k_reads numeric,
  hidden_count bigint,
  severity_score bigint,
  is_spike boolean,
  actions_total bigint,
  -- Comparison to previous period
  reports_prev bigint,
  reports_delta bigint,
  reports_pct_change numeric
)
```

### 5.2 `get_reports_map_v2`

**Purpose:** Geo-aggregated data for map visualization

```sql
FUNCTION get_reports_map_v2(
  p_range text,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_granularity text DEFAULT 'country'  -- 'country' | 'city'
)
RETURNS TABLE (
  geo_code text,          -- country_code or city_code
  geo_name text,          -- Display name
  lat numeric,            -- Centroid latitude
  lng numeric,            -- Centroid longitude
  reports_count bigint,
  top_reason text,
  top_reason_pct numeric,
  trend_pct numeric       -- vs previous period
)
```

### 5.3 `get_reports_breakdown_v2`

**Purpose:** Top lists for right panel

```sql
FUNCTION get_reports_breakdown_v2(
  p_range text,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL,
  p_limit int DEFAULT 5
)
RETURNS TABLE (
  category text,          -- 'country' | 'city' | 'reason'
  code text,              -- country_code, city_code, or reason
  name text,              -- Display name
  count bigint,
  pct numeric,
  trend_pct numeric
)
```

### 5.4 `get_reports_trend_v2`

**Purpose:** Time-series for trend chart

```sql
FUNCTION get_reports_trend_v2(
  p_range text,
  p_region text DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_city_code text DEFAULT NULL
)
RETURNS TABLE (
  bucket timestamptz,     -- Time bucket start
  reports_count bigint,
  hidden_count bigint,
  actions_count bigint
)
```

**Bucket size:**
- `60m` → 5-minute buckets (12 points)
- `24h` → 1-hour buckets (24 points)
- `7d` → 1-day buckets (7 points)
- `30d` → 1-day buckets (30 points)

---

## 6. V1 vs V2 Plan

### V1: Country-Level (MVP)

| Feature | Implementation |
|---------|----------------|
| Map markers | Country centroids only |
| Geo data | `confession_reports.city_code` → derive country |
| Centroids | Hardcoded lookup table (~200 countries) |
| Granularity | Country-level aggregation |
| Map library | Static SVG or simple Leaflet |

**Ship V1 when:**
- All 4 RPCs return data
- Map shows country markers with tooltips
- Click drilldown works (filter by country)
- Signals row displays correctly

### V2: City/Hexgrid (Future)

| Feature | Implementation |
|---------|----------------|
| Map markers | City-level + hexgrid clustering |
| Geo data | `place_cache` for city centroids |
| Clustering | H3 hexgrid for dense areas |
| Granularity | City-level or hex-level |
| Map library | Mapbox GL or Deck.gl |

**Ship V2 when:**
- City centroid data available
- Performance tested with 1000+ markers
- Hexgrid clustering implemented
- Smooth zoom transitions

---

## 7. Non-Goals (Out of Scope)

- Real-time WebSocket updates (use polling)
- User-level geo tracking (privacy)
- Custom date range picker (use presets)
- Export to CSV/PDF (defer)
- Heatmap layer (defer to V2)

---

## 8. Open Questions

1. **Country centroids:** Hardcode or fetch from API?
2. **Map library:** Leaflet (simple) vs Mapbox (polished)?
3. **Refresh interval:** 60s fixed or configurable?
4. **Mobile:** Collapse map to list view?

---

## Appendix: Data Sources

| Data | Table | Key Columns |
|------|-------|-------------|
| Reports | `confession_reports` | `city_code`, `reason`, `created_at`, `handled` |
| Confessions | `confessions` | `region`, `city_code`, `is_hidden` |
| Actions | `moderation_actions` | `action_type`, `created_at` |
| Reads | `event_logs` | `event_name='page_fetch'`, `session_hash` |
| City names | `place_cache` | `id`, `name`, `lat`, `lng` |
