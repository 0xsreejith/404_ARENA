-- M0 — pgTAP test harness (D35, ROADMAP M0).
--
-- Installs the database test framework and nothing else. This migration
-- creates NO business schema: the 28 tables in DATABASE.md are M1 work and
-- must not be pulled forward to make an M0 test pass.
--
-- pgTAP is installed in every environment so the same suite can be run against
-- staging before a release. It defines only test functions; it grants nothing
-- and exposes nothing to the `authenticated` role.

create extension if not exists pgtap with schema extensions;

comment on extension pgtap is
  'Database test framework (D35). Test suite lives in supabase/tests/. '
  'Installed by M0; the 20 required assertions land in M1 (SECURITY.md §15).';
