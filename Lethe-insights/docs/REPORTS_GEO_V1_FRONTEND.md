# Reports Geo V1 - Frontend Integration Guide

## Overview

This document describes the integration of `create_confession_report_v1` RPC for geo-tagged reports.

**Status: IMPLEMENTED** (see changes below)

## Backend

The SQL migration `sql/reports_geo_v1_setup.sql` creates:

1. **`haversine_distance_m(lat1, lng1, lat2, lng2)`** - Distance calculation helper (for future use)
2. **`create_confession_report_v1(...)`** - Report creation RPC with city_code
3. **`backfill_report_city_codes_v1(...)`** - Backfill for existing reports

Deploy this SQL to Supabase SQL Editor.

## Frontend Changes (DONE)

### Files Modified

1. **`src/analytics.ts`** - Added `getGeoDimensions()` export
2. **`src/App.tsx`** - Updated `handleReportSubmit()` to use new RPC

### Implementation Details

```typescript
// src/analytics.ts - New export
export function getGeoDimensions(): {
  country_code?: string
  region?: string
  city_code?: string
} {
  return { ...cachedGeo }
}
```

```typescript
// src/App.tsx - Updated report submission
async function handleReportSubmit() {
  // Get geo context for the report
  const geo = getGeoDimensions()
  const lat = deviceLocation?.lat ?? null
  const lng = deviceLocation?.lng ?? null

  // Use new RPC with city_code support
  const { error } = await supabase.rpc('create_confession_report_v1', {
    p_confession_id: reportConfessionId,
    p_reason: reportReason.toUpperCase(),
    p_details: reportDetails.trim() || null,
    p_city_code: geo.city_code ?? null,
    p_lat: lat,
    p_lng: lng,
  })

  // Fallback to old RPC if new one doesn't exist yet
  if (error?.code === 'PGRST202' || error?.message?.includes('not found')) {
    // ... fallback logic
  }
}
```

### Data Sources

| Parameter | Source | Notes |
|-----------|--------|-------|
| `p_city_code` | `getGeoDimensions().city_code` | From session geo (set by `fetchSessionGeo()` on app load) |
| `p_lat` / `p_lng` | `deviceLocation` state | From device GPS (if granted) |

### Validation Behavior (v1 - Simple)

The RPC sanitizes but trusts the city_code:

| Scenario | Result |
|----------|--------|
| `p_city_code` is null or empty | `city_code` = NULL |
| `p_city_code` > 50 chars | `city_code` = NULL |
| Valid city_code | `city_code` = UPPER(TRIM(p_city_code)) |

**Reports are NEVER rejected.** Invalid city_code = NULL.

## Deployment Steps

1. **Deploy SQL migration:**
   ```sql
   -- Run in Supabase SQL Editor:
   -- Copy contents of sql/reports_geo_v1_setup.sql
   ```

2. **Deploy frontend changes:**
   - The changes to `src/analytics.ts` and `src/App.tsx` are already in place
   - Build and deploy as normal

3. **Verify:**
   ```sql
   -- Check recent reports with city_code
   SELECT city_code, count(*) 
   FROM confession_reports 
   WHERE created_at > now() - interval '24 hours' 
   GROUP BY 1 ORDER BY 2 DESC;
   ```

## Testing

1. Open the Lethe app
2. Wait for geo to load (check dev console for `[fetchSessionGeo]` log)
3. Report a confession
4. Check database for `city_code` value

## Backfill Existing Reports (Admin Only)

```sql
-- Check missing city_codes
SELECT count(*) FROM confession_reports WHERE city_code IS NULL;

-- Run backfill (copies city_code from confessions table)
SELECT * FROM backfill_report_city_codes_v1(1000);

-- Verify
SELECT city_code, count(*) 
FROM confession_reports 
GROUP BY city_code 
ORDER BY count(*) DESC;
```

## Future Improvements (v2)

- Add strict validation against a city_codes lookup table
- Use distance validation (reporter location vs city center)
- Add `reporter_lat` / `reporter_lng` columns for precise geo queries
- Add rate limiting per city to detect coordinated abuse
