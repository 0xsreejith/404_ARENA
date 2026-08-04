-- M1 — harness and scope boundary.
--
-- Proves the test framework runs (the M0 exit criterion) and pins the M1 scope:
-- exactly the 28 tables in DATABASE.md §14, none of the tables §14 defers, and
-- only the RPC surface ROADMAP assigns to M1.
--
-- These assertions fail loudly the moment a later milestone's table or RPC is
-- pulled forward into a migration, which is when it is cheapest to notice.
--
-- Run with:  supabase test db

begin;
set local search_path to extensions, public, pg_catalog;

select plan(9);

-- ── The harness itself ───────────────────────────────────────────────────────

select ok(true, 'pgTAP executes an assertion');

select has_extension(
  'extensions', 'pgtap',
  'pgTAP is installed in the extensions schema (D35)'
);

select ok(
  current_setting('server_version_num')::int >= 150000,
  'PostgreSQL is 15 or newer'
);

-- ── Required extensions (DATABASE.md §13) ────────────────────────────────────

select has_extension('extensions', 'pg_trgm', 'pg_trgm is installed for member name search');
select has_extension('extensions', 'btree_gin', 'btree_gin is installed for the multicolumn GIN index');

-- ── The 28 P0 tables, exhaustively ───────────────────────────────────────────

select tables_are(
  'public',
  array[
    'organizations', 'arenas', 'arena_settings', 'profiles', 'permissions',
    'roles', 'role_permissions', 'arena_users', 'devices',
    'zones', 'station_types', 'stations', 'games',
    'billing_plans', 'tax_rates', 'tax_rate_components',
    'members', 'products', 'inventory_movements', 'product_stock',
    'shifts', 'sessions', 'orders', 'order_items', 'payments',
    'receipt_counters', 'idempotency_keys', 'audit_logs'
  ],
  'public holds exactly the 28 P0 tables in DATABASE.md §14 — no more, no fewer'
);

-- Spelled out separately so a failure names the offender rather than dumping
-- a 28-element diff.
select is_empty(
  $$
    select table_name
      from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'pricing_rules', 'membership_plans', 'member_memberships', 'wallets',
         'wallet_transactions', 'session_games', 'station_games', 'expenses',
         'cash_movements', 'assets', 'maintenance_tickets', 'reservations',
         'sync_operations', 'session_events'
       )
  $$,
  'none of the tables DATABASE.md §14 defers to post-MVP exist (D28)'
);

-- ── The M1 helper schema and RPC surface ─────────────────────────────────────

select has_schema('app', 'the app helper schema exists (DATABASE.md §1.2)');

-- ROADMAP assigns exactly one public RPC to M1: provision_arena. me(),
-- floor_snapshot, the session/checkout/member/shift RPCs and sync_pull are M2
-- and later, and must not appear yet.
select functions_are(
  'public',
  array['provision_arena'],
  'provision_arena is the only public RPC in M1 (ROADMAP M1, API.md §11)'
);

select * from finish();
rollback;
