# Lethe Insights Admin Boundary Design

Lethe is public and anonymous. Lethe Insights is private admin tooling.

This document is a production design only. It does not implement SQL.

## Recommendation

Use Supabase Auth for admin identity, backed by a small `admin_users` allowlist
table. Insights may call Supabase directly from the browser only for RPCs that
perform an explicit admin check server-side. The browser must never receive a
`service_role` key.

The production rule is:

- public Lethe app users can read feed RPCs, post through the insert RPC, report
  content, resolve places, and insert anonymous analytics events.
- Insights users must be authenticated and present in `admin_users`.
- moderation, reports inbox, monetization policy writes, raw analytics, and
  operational dashboards are admin-only.

## Tables Needed

### `admin_users`

Purpose: explicit allowlist of Supabase Auth users who can access Insights.

Recommended columns:

- `user_id UUID PRIMARY KEY`
- `email TEXT`
- `role TEXT NOT NULL`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `created_by UUID`
- `disabled_at TIMESTAMPTZ`

Recommended roles:

- `owner`
- `insights_admin`
- `moderator`
- `finance_admin`
- `readonly_analyst`

Initial launch can use only `owner` and `insights_admin`, then expand later.

### `moderation_actions`

Production table for admin actions against reports/confessions.

Recommended access:

- no anon access
- no public authenticated access
- insert/read only through admin-checked RPCs
- append-only preferred; avoid destructive deletes

### Monetization Policy Tables

Production equivalents:

- `ad_policy_country`
- `ad_policy_effective` view
- country optimization views or RPCs

Recommended access:

- read: admin-only unless runtime app needs a safe public subset
- write: admin-only, ideally `finance_admin` or `owner`

## Functions Needed

### `is_insights_admin()`

Purpose: reusable DB-side check for admin access.

Behavior:

- reads `auth.uid()`
- returns false if no authenticated user
- returns false if user is absent from `admin_users`
- returns false if `disabled_at IS NOT NULL`
- can optionally accept required role(s)

Recommended shape:

```sql
is_insights_admin(required_roles text[] default null) returns boolean
```

Do not rely only on client-side checks.

### Admin RPC Pattern

Every admin RPC should:

- be `SECURITY DEFINER` only if needed
- set a fixed `search_path`
- start with an admin check
- raise `insufficient_privilege` if unauthorized
- return aggregate or scoped data only
- avoid leaking raw coordinates or report details unless necessary for moderation

Example behavior:

```sql
if not public.is_insights_admin(array['owner', 'insights_admin']) then
  raise exception 'admin only' using errcode = '42501';
end if;
```

## RPC Access Categories

### Public RPCs

These can stay callable by anon/authenticated users:

- `get_confess_feed`
- `insert_confession`
- `report_confession`
- `resolve_place` edge function, with rate limiting/abuse controls

### Public Table Access

Allowed:

- `event_logs` insert only
- `places_cache` read
- possibly `place_cache` read

Not allowed:

- direct `confessions` select
- direct `reports` access
- direct `event_logs` select

### Admin-Only Analytics RPCs

Examples:

- pulse metrics
- engagement flow
- readers/writers
- friction metrics
- change over time
- filter option RPCs if they expose operational geography

These can be admin-only RPCs called directly from Insights after login.

### Admin-Only Moderation RPCs

Examples:

- reports overview
- reports inbox
- report groups
- pending/escalated reports
- geo coverage
- report hotspots
- hide/unhide confession
- mark reports handled
- moderation audit log

These must check admin role server-side.

### Admin-Only Monetization RPCs/Tables

Examples:

- `ad_policy_country`
- `ad_policy_effective`
- country optimization views
- action summary views
- policy write/update/delete actions

Reads and writes should be admin-only. Writes should require a stronger role
than readonly analytics.

## RLS Policy Principles

### `confessions`

Keep:

- RLS enabled
- no direct anon select
- no direct anon insert
- public feed access through `get_confess_feed`
- public write access through `insert_confession`
- no lat/lng returned to public clients

Admin access:

- do not add broad direct table read for all authenticated users
- prefer admin-checked RPCs for moderation/Insights views

### `event_logs`

Keep:

- anon/auth insert only
- no anon/auth select

Insights:

- aggregate admin RPCs only
- avoid raw session-level exports unless owner-only

### `reports`

Keep:

- public report submission through `report_confession`
- no direct anon/auth table reads or writes

Insights:

- admin-checked RPCs for inbox, summaries, outcomes, and actions

### `moderation_actions`

Use:

- RLS enabled
- no anon policies
- no broad authenticated policies
- admin-checked RPCs for insert/read

### Monetization Tables

Use:

- RLS enabled
- no anon write access
- admin-only read/write policies or admin-checked RPCs
- readonly analysts may read derived views only

## Direct Supabase Calls vs Edge Functions

Recommended launch path:

Use direct Supabase RPC calls from Insights after Supabase Auth login, as long
as every sensitive RPC performs server-side admin checks.

Use Edge Functions when:

- orchestration requires multiple privileged writes
- external APIs are involved
- service role is unavoidable
- audit logging must be guaranteed around mutations
- rate limits or additional request validation are needed

Do not put `service_role` in the browser.

## Protecting Moderation Actions

Moderation writes should go through RPCs or Edge Functions that:

- require admin role
- write to `moderation_actions`
- update report/confession state atomically
- store actor `auth.uid()`
- store timestamp and action reason
- reject anonymous calls
- reject readonly analysts

Suggested roles:

- `owner`: all moderation actions
- `insights_admin`: all moderation actions
- `moderator`: hide/unhide, mark handled, dismiss/escalate
- `readonly_analyst`: no writes

## Protecting Monetization Policy Writes

Policy writes should:

- require `owner` or `finance_admin`
- audit every change
- validate ranges server-side
- avoid client-side-only validation
- never be available to anon/authenticated non-admin users

Recommended mutation RPCs:

- `upsert_ad_policy_country`
- `delete_ad_policy_country`

Both should check role and write audit entries.

## Testing Anon vs Admin Access

For every production migration, test at least:

### Anon should succeed

- call `get_confess_feed`
- call `insert_confession`
- call `report_confession`
- insert into `event_logs`
- read `places_cache`

### Anon should fail

- direct select `confessions`
- direct select `event_logs`
- direct select `reports`
- read report inbox RPCs
- write moderation actions
- read/write monetization policy tables
- call admin analytics RPCs

### Admin should succeed

- load Overview
- load Engagement
- load Monetization
- load Mood
- load Trends
- load Reports
- perform allowed moderation action
- perform allowed monetization policy action by role

### Non-admin authenticated user should fail

- all admin-only Insights RPCs
- all moderation writes
- all monetization writes

## Safest Implementation Order

1. Create `admin_users`.
2. Create `is_insights_admin()`.
3. Add one read-only admin RPC as a proof of pattern.
4. Add SQL access tests for anon, non-admin authenticated, and admin.
5. Migrate analytics aggregate RPCs.
6. Migrate reports read RPCs.
7. Migrate moderation write RPCs with audit logging.
8. Migrate monetization read views.
9. Migrate monetization write RPCs.
10. Point Insights to production-safe RPCs only after access tests pass.

## Risks To Avoid

- granting `EXECUTE ON ALL FUNCTIONS` to anon in production
- adding direct anon `SELECT` on `confessions`
- exposing raw lat/lng through dashboard RPCs
- exposing report details to non-admin users
- putting `service_role` in browser env
- relying on hidden frontend routes for security
- copying local dev seed shims into migrations wholesale
- allowing anon writes to ad policy or moderation tables

## Exact Next Migration To Build First

First migration should be only the admin foundation:

1. Create `admin_users`.
2. Enable RLS on `admin_users`.
3. Add policy allowing an admin to read active admin rows.
4. Create `is_insights_admin(required_roles text[] default null)`.
5. Grant execute on `is_insights_admin` to authenticated only.
6. Add no dashboard RPCs yet.

This migration is small, low-risk, and creates the boundary required before any
Insights production RPCs are promoted.
