-- Migration: Drop the open anon SELECT policy on the confessions table.
--
-- 001_confessions.sql created:
--   CREATE POLICY "Anyone can read confessions" ON confessions FOR SELECT TO anon USING (true);
--
-- This policy allows any HTTP client to call:
--   GET /rest/v1/confessions?select=*
-- and receive ALL confessions including:
--   • expired rows  (expires_at filter in get_confess_feed is bypassed)
--   • hidden rows   (is_hidden filter in get_confess_feed is bypassed)
--   • poster GPS coordinates
--
-- get_confess_feed runs as SECURITY DEFINER (function owner) and bypasses RLS
-- internally, so dropping this policy does not affect the feed. Direct table
-- access via PostgREST is blocked for both anon and authenticated roles.

DROP POLICY IF EXISTS "Anyone can read confessions" ON confessions;
