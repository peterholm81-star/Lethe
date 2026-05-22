# Insights RPC Admin Pattern

Lethe is public and anonymous. Lethe Insights is private admin tooling.

This document describes the production-safe RPC pattern for future Insights
analytics, moderation, reports, and monetization functions. It does not require
frontend auth wiring yet and does not change current local demo dashboards.

## Recommended Function Structure

Admin RPCs should use a fixed structure:

```sql
CREATE OR REPLACE FUNCTION public.some_insights_rpc(...)
RETURNS ...
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_insights_admin() THEN
    -- Return a safe empty/null response, or raise insufficient_privilege for
    -- write/action RPCs.
  END IF;

  -- Admin-only query body.
END;
$$;
```

Use `SECURITY DEFINER` only when the function must read tables that regular
browser roles cannot access directly. Keep the function body narrow and return
only the minimum aggregate or scoped data needed by the dashboard.

## Explicit `search_path`

Every admin RPC should set an explicit `search_path`:

```sql
SET search_path = public, pg_temp
```

This avoids depending on caller-controlled search paths and keeps object lookup
predictable inside `SECURITY DEFINER` functions.

## Admin Gate

Read-only Insights RPCs should gate with:

```sql
IF NOT public.is_insights_admin() THEN
  -- Safe empty/null return.
END IF;
```

Action RPCs, such as moderation writes or monetization policy writes, should
raise an authorization error instead:

```sql
RAISE EXCEPTION 'insights admin required' USING ERRCODE = '42501';
```

Use safe null or empty returns only for read-only RPCs where the frontend can
render an empty state without leaking sensitive data.

## Least-Privilege Grants

Postgres grants function execution to `PUBLIC` by default. Every admin RPC
should revoke first, then grant only the role that can have a Supabase Auth
identity:

```sql
REVOKE ALL ON FUNCTION public.some_insights_rpc(...) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.some_insights_rpc(...) FROM anon;
GRANT EXECUTE ON FUNCTION public.some_insights_rpc(...) TO authenticated;
```

Do not grant direct table access to `anon` or broad `authenticated` users just
to make dashboards work. Use admin-checked RPCs as the boundary.

## Safe Return Patterns

Prefer aggregated, redacted outputs:

- counts, percentages, buckets, and trends
- country or region aggregates rather than raw coordinates
- report summaries rather than raw report rows unless needed for moderation
- null or empty responses for authenticated non-admin read access

Avoid returning:

- raw session hashes
- precise coordinates
- report submitter metadata
- moderation internals to non-admin users
- row-level event logs unless there is a specific owner-only export flow

## Browser Service Role Rule

The browser must never receive the Supabase `service_role` key.

`service_role` bypasses RLS and would turn any exposed browser session into an
admin database client. Production Insights should authenticate with Supabase
Auth, then call RPCs that enforce `public.is_insights_admin()` server-side.

## Migration Checklist

For each future Insights RPC migration:

1. Confirm the RPC is not part of the public anonymous app path.
2. Add or update exactly one behavior at a time.
3. Use `SECURITY DEFINER` only when needed.
4. Set `search_path = public, pg_temp`.
5. Gate with `public.is_insights_admin()`.
6. Revoke `PUBLIC` and `anon` execution.
7. Grant execution only to `authenticated`.
8. Verify anon, authenticated non-admin, and authenticated admin behavior.
9. Keep local demo shims separate from production migrations.

## Write / Action RPC Pattern

Write and action RPCs differ from read-only aggregates in one important way:
authenticated non-admins must receive an explicit permission error, not a silent
empty result. A silent no-op would mask a misconfiguration and give callers false
confidence that the action succeeded.

```sql
IF NOT public.is_insights_admin() THEN
  RAISE EXCEPTION 'permission denied: admin access required'
    USING ERRCODE = 'insufficient_privilege';
END IF;
```

The Supabase client surfaces this as a non-null `error` on the RPC call. Frontend
hooks that already check `if (error)` will handle it correctly without any
frontend changes.

Write RPCs also use `VOLATILE` (the PostgreSQL default for plpgsql functions that
perform writes) rather than `STABLE`.

No runtime shim restoration is needed after hardening write RPCs. Write actions
are triggered only by explicit user clicks, not by passive dashboard data loading.
The dashboard renders using read RPCs; write actions failing loudly for
non-admin anonymous local dev sessions is the correct behavior.

## Migration Status

Hardened so far:

**Read-only aggregate RPCs** (return empty set for non-admins):

- `public.is_insights_admin()` in `019_insights_admin_boundary.sql`
- `public.get_insights_event_log_summary_example()` in
  `020_insights_rpc_admin_pattern_example.sql`
- `public.get_change_over_time_range(...)` in
  `021_harden_change_over_time_rpc.sql`
- `public.get_engagement_flow_range(...)` in
  `022_harden_engagement_flow_rpc.sql`
- `public.get_pulse_metrics_range(...)` in
  `023_harden_pulse_metrics_rpc.sql`
- `public.get_readers_writers_range(...)` in
  `024_harden_readers_writers_rpc.sql`
- `public.get_friction_range(...)` in
  `025_harden_friction_rpc.sql`
- `public.get_revenue_by_country_range(...)` in
  `026_harden_revenue_by_country_rpc.sql`
- `public.rpc_get_mood_summary(...)` in
  `027_harden_mood_summary_rpc.sql`
- `public.rpc_get_mood_pulse(...)` in
  `028_harden_mood_pulse_rpc.sql`
- `public.rpc_get_mood_pulse_by_region(...)` in
  `029_harden_mood_pulse_by_region_rpc.sql`

**Write / action RPCs** (raise `insufficient_privilege` for non-admins):

- `public.set_confession_hidden(...)` in
  `030_harden_set_confession_hidden.sql`
- `public.set_report_handled(...)` in
  `031_harden_set_report_handled.sql`
- `public.set_reports_handled_for_confession(...)` in
  `032_harden_set_reports_handled_for_confession.sql`
- `public.log_moderation_action(...)` in
  `033_harden_log_moderation_action.sql`

**Read RPCs returning raw moderation content** (return empty set for non-admins):

- `public.get_reports_inbox(...)` in
  `034_harden_get_reports_inbox.sql`
- `public.get_reports_groups(...)` in
  `035_harden_get_reports_groups.sql`
- `public.get_reports_pending_v1(...)` in
  `036_harden_get_reports_pending_v1.sql`
- `public.get_reports_escalated_v1(...)` in
  `037_harden_get_reports_escalated_v1.sql`

- `public.get_moderation_actions_v1(...)` in
  `038_harden_get_moderation_actions_v1.sql`
- `public.get_reports_overview(...)` in
  `039_harden_get_reports_overview.sql`
- `public.get_reports_overview_v2(...)` in
  `040_harden_get_reports_overview_v2.sql`
- `public.get_reports_outcomes_v1(...)` in
  `041_harden_get_reports_outcomes_v1.sql`
- `public.get_reports_sla_v1(...)` in
  `042_harden_get_reports_sla_v1.sql`
  (also fixed pre-existing shape mismatch: old 3-column shape replaced with
  5-column shape the frontend has always expected)
- `public.get_reports_geo_coverage_v1(...)` in
  `043_harden_get_reports_geo_coverage_v1.sql`
  (no frontend caller; hardened preemptively before dashboard wiring)
- `public.get_reports_geo_coverage_v2(...)` in
  `044_harden_get_reports_geo_coverage_v2.sql`
- `public.get_reports_spike_explain_v1(...)` in
  `045_harden_get_reports_spike_explain_v1.sql`
  (also fixed pre-existing shape mismatch: old multi-row per-reason breakdown
  replaced with single aggregate spike-summary row the frontend has always
  expected)

- **CRITICAL internal helpers** (REVOKE only, no body changes):
  `public._lethe_confession_filtered(...)` and
  `public._lethe_event_filtered(...)` in
  `046_revoke_internal_helper_anon_access.sql`
  — anon and authenticated revoked; postgres superuser callers unaffected

- `public.get_reports_hotspots_v1(...)` in
  `047_harden_get_reports_hotspots_v1.sql`
  (plpgsql rewrite required to support admin gate; all CTE aliases fully
  qualified to avoid plpgsql RETURNS TABLE variable ambiguity; same
  3-parameter signature, 15-column return shape, and LIMIT 20 preserved)

- `public.get_reports_breakdown_v2(...)` in
  `048_harden_get_reports_breakdown_v2.sql`
  (plpgsql rewrite; 4-parameter signature, 2-column JSONB return shape
  preserved exactly; single-row result; frontend handles empty gracefully)

- `public.get_reports_trend_v2(...)` in
  `049_harden_get_reports_trend_v2.sql`
  (plpgsql rewrite; 4-parameter signature, single `trend jsonb` column
  preserved; date-series CTE renamed from "days" to "date_series" to avoid
  plpgsql shadowing of the "days" column in the params CTE; admin returns
  30-point daily array, non-admin returns 0 rows)

- `public.get_reports_map_v2(...)` in
  `050_harden_get_reports_map_v2.sql`
  (plpgsql rewrite; 4-parameter signature, single `markers jsonb` column
  preserved; CTE columns fully aliased to avoid plpgsql shadowing; no output
  column name conflicts; admin returns 1 row with marker array, non-admin
  returns 0 rows; dev seed lacks lat/lng so marker array is [] locally)

- `public.get_sessions_by_country_range(...)` in
  `051_harden_get_sessions_by_country_range.sql`
  (plpgsql rewrite; 6-parameter signature, 2-column multi-row table preserved;
  calls _lethe_event_filtered internally — safe because SECURITY DEFINER runs
  as postgres owner; ORDER BY 2 DESC avoids output-variable ambiguity;
  admin returns 23 country rows, non-admin returns 0 rows)

- `public.get_pulse_metrics(...)` and `public.get_latest_metrics_day(...)` in
  `052_harden_pulse_metrics_and_latest_day.sql`
  (batched together — both used in useInsightsActiveDay.ts bootstrap hook;
  get_pulse_metrics delegates to get_pulse_metrics_range (already hardened,
  migration 023) — explicit gate added for defence-in-depth; get_latest_metrics_day
  reads event_logs directly, e.day_bucket alias avoids output-variable shadowing;
  both return 0 rows for non-admin; admin: get_pulse_metrics=3/3/0, latest=2026-05-22)

- `public.get_trends_comparison_v1(...)` and `public.get_trends_trendline_v1(...)` in
  `053_harden_trends_comparison_and_trendline_v1.sql`
  (batched — both used by useTrendsV1.ts + useTrendsSummaryV1.ts; comparison:
  internal aliases sk/mk/val/cur_val/prev_val rename scope_key/metric_key/value
  to avoid plpgsql output-var shadowing; scopes CTE renamed evt_scopes;
  trendline: date_series replaces "days" CTE, mk/val replace metric_key/value;
  admin: 4 comparison rows, 120 trendline rows; non-admin: 0 rows)

- `public.get_trends_movers_v1(...)` — BOTH overloads — in
  `054_harden_get_trends_movers_v1.sql`
  (2 overloads: 4-param core logic + 5-param wrapper; frontend always calls
  5-param via scopeToRpc(); internal aliases etag/cnt/bline replace
  tag/c/b to avoid plpgsql output-var shadowing; ON instead of USING for
  the join; 5-param wrapper adds defence-in-depth gate before delegating;
  admin: 4 rows both overloads; non-admin: 0 rows both overloads)

- `public.get_year_wheel_v1(...)` — BOTH overloads — in
  `055_harden_get_year_wheel_v1.sql`
  (2 overloads: 5-param core + 6-param wrapper; frontend calls 6-param via
  scopeToRpc(); CTE aliases em_month/em_sessions/em_posts/cm_month/cm_mood_pos/
  cm_mood_neg/cm_total replace original names that matched output vars;
  all WHERE/JOIN refs use explicit table aliases; admin: 13 rows both overloads;
  non-admin: 0 rows)

Still ungated:
- `get_emotion_fingerprint_v1` (2 overloads — same p_city wrapper pattern)
- filter helpers (`get_insights_region_options`, `get_insights_country_options`,
  `get_insights_city_options`)
- trends and seasonality read aggregates (`get_trends_comparison_v1`,
  `get_trends_trendline_v1`, `get_year_wheel_v1`, `get_emotion_fingerprint_v1`,
  `get_trends_movers_v1`)
- remaining analytics reads (`get_sessions_by_country_range`,
  `get_pulse_metrics`, `get_latest_metrics_day`)
- filter helpers (`get_insights_region_options`, `get_insights_country_options`,
  `get_insights_city_options`)

Recommended next category:

Phase 1 (critical write RPCs) is complete. All four write RPCs are now
admin-gated with explicit `insufficient_privilege` errors for non-admins and
no dev-seed hardcodings in production bodies.

All moderation write RPCs and high-risk moderation read RPCs are now hardened.

All Reports-page RPCs are now hardened. The entire Reports section of
Lethe Insights is production-safe.

Recommended next category: `get_emotion_fingerprint_v1` (2 overloads —
same p_city wrapper pattern), then filter helpers (`get_insights_region_options`,
`get_insights_country_options`, `get_insights_city_options`) which are lowest risk.

After that: trends, seasonality, and remaining analytics reads
(`get_trends_comparison_v1`, `get_trends_trendline_v1`, `get_year_wheel_v1`,
`get_emotion_fingerprint_v1`, `get_trends_movers_v1`, `get_sessions_by_country_range`,
`get_pulse_metrics`, `get_latest_metrics_day`).

Filter helpers (`get_insights_region_options`, `get_insights_country_options`,
`get_insights_city_options`) are lowest risk and can be deferred to last.
