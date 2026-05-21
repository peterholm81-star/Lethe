# Lethe Dev-Only Large Dataset

This folder is for local launch-readiness testing only.

It is intentionally outside `supabase/migrations` and outside the configured
`supabase/seed.sql` path, so it is not applied by normal production migration
workflows.

## What It Seeds

- 30,000 test confessions across Europe, North America, South America, Asia,
  Africa, Oceania, and the Middle East.
- Realistic city coordinates, with some rows intentionally missing coordinates.
- Rolling timestamps across the last 180 days, while keeping seeded confessions
  non-expired for local feed testing.
- Multiple languages and mood buckets.
- About 320,000 anonymous analytics events.
- Ad behavior scenarios for high, medium, and low tolerance regions.
- Reports, hidden confessions, dismissed/actioned reports, and moderation logs.
- Local-only RPCs needed by Lethe Insights dashboards.

## Safe Beginner Workflow

Run this only against local Supabase:

```powershell
npx supabase start
npm run supabase:dev:reset
npm run supabase:dev:seed-large
```

Then point both apps at the local Supabase API URL and anon key printed by:

```powershell
npx supabase status
```

## Reset / Remove

The safest reset is:

```powershell
npm run supabase:dev:reset
```

That drops the local database and reapplies normal migrations plus
`supabase/seed.sql`. It does not affect hosted Supabase projects.

## Production Safety

Do not paste `large_dev_seed.sql` into the Supabase Dashboard SQL editor for a
hosted project. Use the `--local` commands above.

All generated rows are marked with:

- `is_dev_seed = true`
- `dev_seed_batch = 'large-global-v1'`

The script removes only rows from previous runs of the same dev seed batch.
