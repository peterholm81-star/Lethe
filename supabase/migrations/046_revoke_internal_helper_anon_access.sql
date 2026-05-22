-- =============================================================================
-- Migration 046: Revoke anon/PUBLIC access to internal helper functions
--
-- Phase: CRITICAL — Production launch blocker
--
-- Purpose:
--   Two internal helper functions were left with the PostgreSQL default PUBLIC
--   execute grant, making them directly callable via the Supabase REST API
--   (/rest/v1/rpc/_lethe_confession_filtered and _lethe_event_filtered) by
--   any anonymous caller holding only the public anon key.
--
--   _lethe_confession_filtered: returns SETOF confessions (SELECT * — full rows
--     including confession text, is_hidden flag, lat/lng, emotion_bucket, geo)
--
--   _lethe_event_filtered: returns SETOF event_logs (SELECT * — full rows
--     including session_hash, event_name, all geo columns, emotion_bucket, mode)
--
--   These helpers exist solely as internal building blocks for analytics
--   aggregate RPCs. They have no frontend callers and must never be callable
--   by external clients.
--
-- Why this is safe to revoke without any compensating GRANT:
--   Both functions are owned by the 'postgres' superuser and marked
--   SECURITY DEFINER. All 8 callers in the codebase are also SECURITY DEFINER
--   functions owned by 'postgres':
--     - get_change_over_time_range  (uses _lethe_event_filtered)
--     - get_engagement_flow_range   (uses _lethe_event_filtered)
--     - get_pulse_metrics_range     (uses _lethe_event_filtered)
--     - get_readers_writers_range   (uses _lethe_event_filtered)
--     - get_friction_range          (uses _lethe_event_filtered)
--     - get_sessions_by_country_range (uses _lethe_event_filtered)
--     - rpc_get_mood_summary        (uses _lethe_confession_filtered)
--     - rpc_get_mood_pulse          (uses _lethe_confession_filtered)
--
--   In PostgreSQL, superusers bypass all privilege checks. When a SECURITY
--   DEFINER function owned by 'postgres' calls another function, the call is
--   made with superuser privileges and no grant on the callee is required.
--   Revoking PUBLIC/anon execute does not affect any of these callers.
--
-- What changes:
--   Before: anon can call /rest/v1/rpc/_lethe_confession_filtered with any
--     date range and dump raw confession text, geo, and is_hidden state.
--   After: anon receives "permission denied for function" (SQLSTATE 42501).
--
-- No function bodies, signatures, or search_path are modified.
-- No local shim restoration is required (no frontend calls these helpers).
-- =============================================================================

-- _lethe_confession_filtered
-- Removes default PUBLIC execute grant and explicitly blocks anon and
-- authenticated. No GRANT is needed because all callers are SECURITY DEFINER
-- functions owned by the postgres superuser, which bypasses grant checks.
REVOKE ALL     ON FUNCTION public._lethe_confession_filtered(DATE, DATE, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._lethe_confession_filtered(DATE, DATE, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public._lethe_confession_filtered(DATE, DATE, TEXT, TEXT, TEXT) FROM authenticated;

-- _lethe_event_filtered
-- Same treatment.
REVOKE ALL     ON FUNCTION public._lethe_event_filtered(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._lethe_event_filtered(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public._lethe_event_filtered(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM authenticated;
