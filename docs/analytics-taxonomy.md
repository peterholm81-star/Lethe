# Lethe Analytics Event Taxonomy

**Phase E.2 — Taxonomy Contract Lock**  
Last updated: May 2026

---

## Purpose

This document is the authoritative contract for all analytics events emitted by the Lethe app and consumed by Lethe Insights.

It exists to prevent:
- Event names drifting between frontend and SQL migrations
- Insights RPCs being built against events that are never emitted in production
- Accidental tracking expansion or privacy violations

**Rule:** Any new event name must be added here before it is emitted in code or queried in SQL.

---

## Privacy Constraints (Non-negotiable)

- No user identity. No device fingerprinting. No cross-session linking.
- No IP geo. Geo is derived only from voluntarily-shared GPS coordinates during confession submission.
- No `confession_id` on event_logs. Events and content are intentionally unlinked.
- No background tracking. `session_hash` rotates every 24 hours; clearing localStorage ends it.
- Browse-only sessions (no post) remain geo-null forever. This is correct and intended.
- `event_logs` inserts are fire-and-forget. A failure must never block app usage.

---

## Canonical Production Events

These 6 events are **currently emitted** by the app. All Insights RPCs should be built against these.

### `session_start`

| Field | Value |
|---|---|
| Emitted from | `App.tsx` on component mount (`useEffect([], [])`) |
| Geo | **Never.** Fires before any user action. |
| `mode` | Not set |
| `reason_bucket` | Not set |
| Purpose | Count unique sessions. Basis for DAU/MAU proxies. |
| Insights RPCs | `get_change_over_time_v1`, `get_engagement_flow_v1`, `get_pulse_metrics`, `get_sessions_by_country_range`, `get_latest_metrics_day`, `get_trends_*`, `get_year_wheel_v1`, `get_emotion_fingerprint_v1`, `get_revenue_by_country_v1` |

---

### `feed_view`

| Field | Value |
|---|---|
| Emitted from | `App.tsx` on tab change or `deviceLocation`/`somewherePlace` state change |
| Geo | Included if `geoContextRef.current` is set (i.e., user posted with GPS in this session) |
| `mode` | `'world'` \| `'somewhere'` \| `'near'` |
| Purpose | Count reader sessions. Represents intent to read, not pagination. |
| Insights RPCs | `get_pulse_metrics`, `get_readers_writers_v1`, `get_engagement_flow_v1`, `get_reports_overview_v2`, `get_reports_hotspots_v1`, `get_trends_trendline_v1`, `get_trends_comparison_v1`, `get_year_wheel_v1` — always as `IN ('feed_view', 'page_fetch')` |

**Note:** `feed_view` re-fires when `deviceLocation` or `somewherePlace` changes (not only on tab switch). This is intentional: switching location context is a meaningful reader event.

---

### `page_fetch`

| Field | Value |
|---|---|
| Emitted from | `App.tsx` inside `loadWorld`, `loadPlace`, `loadNearMe` — pagination only |
| Guard | `!reset && result.confessions.length > 0` (never on initial load, never on empty/failed fetch) |
| Geo | Included if `geoContextRef.current` is set |
| `mode` | `'world'` \| `'somewhere'` \| `'near'` (hardcoded per callback, not from `tab` state) |
| Purpose | Count pagination depth. Together with `feed_view` forms the "reader" signal in Insights. |
| Insights RPCs | All RPCs using `event_name IN ('feed_view', 'page_fetch')` |

**Critical distinction:**
- `feed_view` = opening a feed or switching context
- `page_fetch` = loading more content in the same context
- Initial feed load emits **only** `feed_view`. Subsequent "load more" taps emit **only** `page_fetch`.

---

### `post_attempt`

| Field | Value |
|---|---|
| Emitted from | `App.tsx` at start of `handleSubmit`, before the RPC call |
| Geo | Included from `geoContextRef.current` (prior-post geo, may be null) |
| `mode` | `'world'` \| `'somewhere'` \| `'near'` |
| Purpose | Count total posting intent, including rejected attempts. Numerator for friction ratio. |
| Insights RPCs | `get_engagement_flow_v1`, `get_friction_v1` |

---

### `post_success`

| Field | Value |
|---|---|
| Emitted from | `App.tsx` immediately after successful `insertConfession` RPC response |
| Geo | **Direct from `result.geo`** — the server-resolved geo for this specific post. This is the geo source event for the session. |
| `mode` | `'world'` \| `'somewhere'` \| `'near'` |
| Purpose | Count successful posts. Writer metric. Source of geo context for session. |
| Insights RPCs | `get_change_over_time_v1`, `get_engagement_flow_v1`, `get_pulse_metrics`, `get_readers_writers_v1`, `get_friction_v1`, `get_trends_*`, `get_year_wheel_v1` |

**Geo note:** `post_success` is the **only** event where geo comes directly from the RPC result (not from `geoContextRef`). After this event fires, `geoContextRef.current` is updated if `city_code` is non-null, and all subsequent events in the session carry that geo context.

---

### `post_reject`

| Field | Value |
|---|---|
| Emitted from | `App.tsx` on validation failure (pre-RPC) or RPC error response |
| Geo | Included from `geoContextRef.current` (prior-post geo, may be null) |
| `mode` | `'world'` \| `'somewhere'` \| `'near'` |
| `reason_bucket` | `'validation'` \| `'rate_limit'` \| `'network'` |
| Purpose | Count rejection reasons. Denominator for friction ratio. |
| Insights RPCs | `get_friction_v1` |

**`reason_bucket` mapping:**
- `'validation'` → `CONTENT_BLOCKED`, `EMPTY_TEXT`, `TEXT_TOO_LONG`
- `'rate_limit'` → `RATE_LIMIT`, `BURST_LIMIT`
- `'network'` → all other RPC errors

---

## Geo Enrichment Rules

```
Geo fields: city_code, region, country_code

Source:          Server-side nearest-city lookup (Haversine, max 100 km)
                 against public.geo_cities (25 world cities, migration 060)

Populated:       Only when user submits a confession with GPS coordinates
                 AND the nearest city is within 100 km

NULL when:       - User has no GPS / denied location permission
                 - Nearest city is > 100 km away
                 - geo lookup throws any exception (fails safe to NULL)

Session caching: After post_success with non-null city_code, geoContextRef.current
                 is set and included in all subsequent logEvent calls in that session.
                 Cleared on page reload. Never persisted to localStorage.

Browse-only:     Sessions with no post action remain geo-null. This is correct.
                 Insights RPCs must handle NULL geo gracefully (WHERE city_code IS NOT NULL).
```

---

## Common Metadata Fields

| Field | Type | Present on |
|---|---|---|
| `event_name` | TEXT NOT NULL | All events |
| `day_bucket` | DATE NOT NULL | All events (client-local date) |
| `time_bucket` | INT (0-23) | All events (client-local hour) |
| `session_hash` | TEXT | All events (24h localStorage UUID, rotates with session) |
| `mode` | TEXT | `feed_view`, `page_fetch`, `post_attempt`, `post_success`, `post_reject` |
| `city_code` | TEXT \| NULL | All except `session_start` (only when geo context exists) |
| `region` | TEXT \| NULL | All except `session_start` (only when geo context exists) |
| `country_code` | TEXT \| NULL | All except `session_start` (only when geo context exists) |
| `reason_bucket` | TEXT \| NULL | `post_reject` only |
| `language_detected` | TEXT \| NULL | Schema column exists; **never set** (reserved) |
| `emotion_bucket` | TEXT \| NULL | Schema column exists; **never set** (reserved) |

---

## Deferred / Future Events

These event names are **referenced in Insights RPCs and the dev seed** but are **not yet emitted** by the app. All counts for these events are 0 in production.

### `ad_shown`

- **Intent:** Fired when an ad card is displayed to the user.
- **Current state:** `markAdShown()` in `session.ts` updates in-memory state but emits nothing to `event_logs`.
- **Blocked by:** Ad display is managed in `App.tsx` via `adInserted` state flag; no `logEvent` call alongside `markAdShown()`.
- **Impact of gap:** `get_revenue_by_country_v1` and `get_engagement_flow_v1` show 0 ad impressions in production.
- **Implementation path:** Add `logEvent('ad_shown', { mode: tab, ...(geoContextRef.current ?? {}) })` in the `useEffect` that fires `markAdShown()`.
- **Type must be added to `AnalyticsEventName`** before implementation.

### `continue_after_ad`

- **Intent:** Fired when user continues using the app after an ad is shown (engagement signal).
- **Current state:** Never emitted.
- **Blocked by:** No hook for post-ad user action exists.
- **Impact of gap:** Ad engagement funnel in `get_engagement_flow_v1` is empty in production.
- **Implementation path:** Requires detecting the first user interaction after ad display. Deferred.

### `drop_after_ad`

- **Intent:** Fired when user exits or stops interacting after an ad is shown (churn signal).
- **Current state:** Never emitted.
- **Blocked by:** Requires session-end detection (not currently instrumented).
- **Impact of gap:** Ad drop rate in `get_engagement_flow_v1` is empty in production.
- **Implementation path:** Could be approximated via `visibilitychange` + session timeout, but requires careful privacy review. Deferred.

---

## Trusted vs Experimental Metrics

### Trusted (reliable in production)

| Metric | Source events |
|---|---|
| Session count | `session_start` |
| Reader sessions | `feed_view` + `page_fetch` |
| Post attempts | `post_attempt` |
| Successful posts | `post_success` |
| Rejection breakdown | `post_reject` by `reason_bucket` |
| Writer/reader ratio | `post_success` / `feed_view`+`page_fetch` |
| Post friction rate | `post_reject` / `post_attempt` |
| Geo distribution (posts) | `post_success` where `city_code IS NOT NULL` |
| Geo distribution (reads) | `feed_view` / `page_fetch` where `city_code IS NOT NULL` |

### Not trusted in production (deferred events)

| Metric | Depends on | Status |
|---|---|---|
| Ad impressions | `ad_shown` | Always 0 |
| Ad engagement rate | `continue_after_ad` | Always 0 |
| Ad drop rate | `drop_after_ad` | Always 0 |
| Revenue by country | `ad_shown` + `session_start` | Ad side always 0 |

### Reserved / not yet populated

| Field | Status |
|---|---|
| `language_detected` | Schema exists; never set; reserved for future language-detection feature |
| `emotion_bucket` | Schema exists; never set; reserved for future mood-tagging feature |

---

## TypeScript Enforcement

`AnalyticsEventName` is a TypeScript union type exported from `src/analytics.ts`. The `logEvent` function's first parameter is typed as `AnalyticsEventName`, not `string`. TypeScript will reject any callsite passing an unknown event name.

To add a new event:
1. Add it to `AnalyticsEventName` in `src/analytics.ts`
2. Document it in this file
3. If Insights will query it, add it to the relevant RPC with awareness that production data will be 0 until the event is emitted

---

## Session Hash vs Session ID

Two parallel session concepts exist in the codebase:

| | `analytics.ts` session_hash | `state/session.ts` sessionId |
|---|---|---|
| Key | `lethe_session_hash` (localStorage) | In-memory only |
| TTL | 24 hours, rotates | Cleared on page reload |
| Purpose | Analytics event deduplication | Ad arming / page-fetch counting |
| Used in | `event_logs.session_hash` | `isAdArmed()`, `recordPageFetch()` |

These are intentionally separate. Do not merge them.
