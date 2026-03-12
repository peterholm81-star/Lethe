-- Migration: Reports / moderation system
-- Stores user-submitted reports against confessions.
-- All client access goes through the report_confession RPC (SECURITY DEFINER).
-- No direct table reads or writes are exposed to clients.

-- =============================================================================
-- REPORTS TABLE
-- =============================================================================
-- confession_id is NOT a foreign key so reports survive confession expiry/deletion.
-- reporter_user_id is nullable: populated when anonymous auth is active, null otherwise.
-- status tracks moderation workflow; only editable by service-role (admin tooling).

CREATE TABLE reports (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  confession_id     UUID        NOT NULL,
  reason            TEXT        NOT NULL,
  details           TEXT,
  reporter_user_id  UUID,
  status            TEXT        NOT NULL DEFAULT 'open',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT reports_status_check
    CHECK (status IN ('open', 'reviewed', 'actioned', 'dismissed')),

  CONSTRAINT reports_reason_nonempty
    CHECK (char_length(btrim(reason)) > 0)
);

-- Index to look up all reports for a given confession (moderation dashboard)
CREATE INDEX reports_confession_id_idx
  ON reports (confession_id);

-- Index for the moderation queue (filter by open status)
CREATE INDEX reports_status_open_idx
  ON reports (created_at DESC)
  WHERE status = 'open';

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================
-- RLS is enabled but no policies are granted to anon/authenticated roles.
-- The RPC uses SECURITY DEFINER and runs as the function owner, bypassing RLS.
-- This means:
--   - Clients cannot SELECT, INSERT, UPDATE, or DELETE reports directly.
--   - Only service-role (admin tooling / Supabase Studio) can query the table.

ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- RPC: report_confession
-- =============================================================================
-- Called by the frontend as: supabase.rpc('report_confession', { ... })
--
-- Validates inputs, attaches auth.uid() if a session exists, inserts the report.
-- Returns void — the caller only needs to know if it succeeded or threw.
--
-- Security:
--   SECURITY DEFINER  — runs as function owner, bypasses RLS on reports table
--   Anon + authenticated roles are granted EXECUTE
--   Direct table INSERT is blocked by RLS (no policy)
-- =============================================================================

CREATE OR REPLACE FUNCTION report_confession(
  p_confession_id  UUID,
  p_reason         TEXT,
  p_details        TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id  UUID;
  v_reason   TEXT;
  v_details  TEXT;
BEGIN
  -- Validate confession_id
  IF p_confession_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_confession_id is required';
  END IF;

  -- Validate and normalise reason
  v_reason := btrim(COALESCE(p_reason, ''));
  IF v_reason = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_reason is required';
  END IF;

  -- Normalise details: treat blank string as null
  v_details := NULLIF(btrim(COALESCE(p_details, '')), '');

  -- Attach anonymous auth user if a session exists (enables per-user tracking)
  v_user_id := auth.uid();

  INSERT INTO reports (
    confession_id,
    reason,
    details,
    reporter_user_id
  ) VALUES (
    p_confession_id,
    v_reason,
    v_details,
    v_user_id
  );
END;
$$;

-- Allow anonymous and authenticated users to call the RPC.
-- Direct table access remains blocked by RLS (no policies defined above).
GRANT EXECUTE ON FUNCTION report_confession TO anon;
GRANT EXECUTE ON FUNCTION report_confession TO authenticated;
