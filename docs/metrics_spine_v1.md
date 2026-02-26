# Metrics Spine v1

Privacy-first analytics for Lethe. All events are anonymous—no user identity, no IP, no device fingerprint.

## Event Types

| Event Name      | Description                                    | When Logged                           |
|-----------------|------------------------------------------------|---------------------------------------|
| `session_start` | New anonymous session began                    | App mount (cold start)                |
| `feed_view`     | User viewed a feed tab                         | Tab switch (world/near/somewhere)     |
| `page_fetch`    | User fetched next page of confessions          | Pagination (not initial load)         |
| `post_attempt`  | User attempted to post a confession            | Submit button clicked                 |
| `post_success`  | Confession was posted successfully             | After Supabase insert succeeds        |
| `post_reject`   | Confession was rejected                        | Validation/rate-limit/network error   |
| `ad_shown`      | Ad was displayed to user                       | When ad card is inserted into feed    |

### Planned Events (not yet implemented)
| Event Name      | Description                                    |
|-----------------|------------------------------------------------|
| `feed_refresh`  | User manually refreshed the feed               |

## Dimensions (Columns)

All events include these dimensions:

| Column             | Type    | Description                                          |
|--------------------|---------|------------------------------------------------------|
| `id`               | UUID    | Unique event ID (auto-generated)                     |
| `event_name`       | TEXT    | Event type (see table above)                         |
| `created_at`       | TIMESTAMPTZ | Server timestamp                                 |
| `day_bucket`       | DATE    | Local date (YYYY-MM-DD)                              |
| `time_bucket`      | INT     | Local hour (0-23)                                    |
| `dow_bucket`       | INT     | Day of week (0=Sunday, 6=Saturday)                   |
| `session_hash`     | TEXT    | Anonymous session identifier (rotates every 24h)     |
| `country_code`     | TEXT    | ISO 3166-1 alpha-2 country code                      |
| `region`           | TEXT    | Region/state code                                    |
| `city_code`        | TEXT    | City identifier                                      |
| `mode`             | TEXT    | Feed scope: `world`, `near`, `somewhere`             |
| `language_detected`| TEXT    | Detected language of confession                      |
| `emotion_bucket`   | TEXT    | Bucketed emotion category                            |
| `reason_bucket`    | TEXT    | Rejection reason: `validation`, `rate_limit`, `network` |
| `meta`             | JSONB   | Extensible metadata (no PII)                         |

## Privacy Guarantees

1. **No user identity**: No `user_id`, no device ID, no fingerprinting
2. **Session rotation**: `session_hash` rotates every 24 hours
3. **No IP storage**: IP addresses are never logged
4. **Bucketed data**: Time is bucketed to hour-level, emotions are categorized
5. **Append-only**: RLS allows only INSERT, no SELECT/UPDATE/DELETE for clients

## Indexes

Optimized for common aggregation queries:

```sql
-- Time-based regional queries
idx_event_logs_day_region_city_event (day_bucket, region, city_code, event_name)

-- Session analysis
idx_event_logs_session_day (session_hash, day_bucket)

-- Day-of-week patterns
idx_event_logs_dow (dow_bucket, day_bucket)

-- Country-level queries
idx_event_logs_country_day (country_code, day_bucket)
```

## Geo Dimensions

Geo dimensions (`country_code`, `region`, `city_code`) are populated automatically on session start:

1. **Edge function `get_session_geo`** extracts geo from Cloudflare/Deno Deploy headers
2. **`fetchSessionGeo()`** is called once on app mount (before `session_start` event)
3. **`setGeoDimensions()`** stores the values in the analytics module

All subsequent `logEvent()` calls automatically include these dimensions.

### Privacy

- No IP addresses are stored
- Only coarse location codes (country, region, city bucket)
- Headers are extracted server-side, never exposed to client

## Usage

```typescript
import { logEvent, setGeoDimensions } from './analytics'

// Set geo once per session (from feed response)
setGeoDimensions({ country_code: 'NO', region: 'Oslo', city_code: 'oslo' })

// Log events
logEvent('session_start')
logEvent('feed_view', { mode: 'world' })
logEvent('page_fetch')
logEvent('post_attempt', { mode: 'near' })
logEvent('post_success', { mode: 'near' })
logEvent('post_reject', { mode: 'near', reason_bucket: 'validation' })
logEvent('ad_shown', { mode: 'world' })
```

## Deployment

1. **Database migration**:
   ```bash
   supabase db push
   ```

2. **Edge function** (must use `--no-verify-jwt` for public access):
   ```bash
   supabase functions deploy get_session_geo --no-verify-jwt
   ```

After deployment, all new events will include geo dimensions automatically.

### Auth Notes

The `get_session_geo` function is deployed with `--no-verify-jwt` because:
- It returns only coarse, non-sensitive geo data (country/region/city codes)
- It's called on every session start before user authentication
- The function still validates that `apikey` header is present (Supabase anon key)
- Visiting the URL directly in a browser will 401 (no headers)
