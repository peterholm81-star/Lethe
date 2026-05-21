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
