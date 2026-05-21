# Lethe Insights Local Recovery Notes

This document describes the local-only stabilization work for running Lethe
Insights against the large seeded Supabase dataset.

## Scope

All changes are local development support only. They live under `supabase/dev`
and are applied through:

```powershell
npm run supabase:dev:seed-large
```

Do not paste these SQL shims into production Supabase.

## What Was Fixed

The current Insights frontend references a mix of older and newer RPC/table
contracts. The local dev seed now creates compatibility wrappers so the current
dashboards can load without changing UI layout or dashboard architecture.

## RPCs Mapped Or Shimmed

- `get_pulse_metrics` wraps `get_pulse_metrics_range` for active-day bootstrap.
- `get_latest_metrics_day` returns the latest seeded analytics day.
- `get_reports_overview_v2`, `get_reports_breakdown_v2`,
  `get_reports_trend_v2`, and `get_reports_map_v2` provide Reports page data.
- `get_reports_geo_coverage_v2` maps the current Reports geo coverage hook.
- `get_reports_groups` and `set_reports_handled_for_confession` support grouped
  report inbox actions.
- `get_year_wheel_v1`, `get_emotion_fingerprint_v1`, and
  `get_trends_movers_v1` include overloads for the frontend's current
  `p_city` parameter.
- `get_moderation_actions_v1` accepts optional `p_action_type` to support both
  moderation and audit-log callers.

## Local Tables And Views

- `ad_policy_country` supports local Revenue Lab policy edits.
- `country_optimization_v1` powers country optimization rows.
- `country_optimization_action_summary_30d` powers the action summary.
- `confessions.intent` is added for the existing Intent card query.

## Expected Remaining Warnings

- A browser `net::ERR_ABORTED` may appear when navigating quickly between pages.
  This is a canceled in-flight request, not a missing RPC.
- Supabase CLI may warn about local service versions differing from the linked
  project. This does not block local dashboard testing.
- Supabase may show stopped `imgproxy` or `pooler` services locally. They are
  not required for the current Lethe/Insights verification.

## Restart Later

```powershell
npx supabase start
npm run supabase:dev:seed-large
npm run dev
```

In another terminal for Insights:

```powershell
cd Lethe-Insights\Lethe-insights
npm run dev -- --host 127.0.0.1 --port 5176
```

If `.env.local` points at production Supabase, override env vars in the terminal
or update local env files to use the local values from:

```powershell
npx supabase status
```
