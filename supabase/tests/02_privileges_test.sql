-- M1 — layer 1: PostgreSQL privileges.
--
-- Privilege revocation, not RLS, is the primary write control (D05,
-- SECURITY.md §1). These assertions are catalogue-level: they hold whatever
-- data exists and whoever is signed in.
--
-- Covers SECURITY.md §15 assertions 6 and 14 (the privilege half).

begin;
set local search_path to extensions, public, pg_catalog;

select plan(11);

-- ── No client write path anywhere ────────────────────────────────────────────
--
-- Asserted across every table rather than only the protected list in
-- SECURITY.md §5, because a catalogue table that becomes client-writable is
-- the same bug.

select is_empty(
  $$
    select t.table_name || ' / ' || p.priv
      from information_schema.tables t
      cross join unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES']) as p(priv)
     where t.table_schema = 'public'
       and t.table_type = 'BASE TABLE'
       and has_table_privilege(
             'authenticated',
             ('public.' || quote_ident(t.table_name))::regclass,
             p.priv
           )
  $$,
  'authenticated has no INSERT, UPDATE, DELETE, TRUNCATE or REFERENCES on any table (D05)'
);

select is_empty(
  $$
    select t.table_name || ' / ' || p.priv
      from information_schema.tables t
      cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES'])
        as p(priv)
     where t.table_schema = 'public'
       and t.table_type = 'BASE TABLE'
       and has_table_privilege(
             'anon',
             ('public.' || quote_ident(t.table_name))::regclass,
             p.priv
           )
  $$,
  'anon has no privilege of any kind: there is no unauthenticated surface in P0'
);

-- ── Reads that must exist ────────────────────────────────────────────────────

select is_empty(
  $$
    select t.name
      from unnest(array[
        'organizations', 'arenas', 'arena_settings', 'profiles', 'permissions',
        'roles', 'role_permissions', 'arena_users', 'devices',
        'zones', 'station_types', 'stations', 'games',
        'billing_plans', 'tax_rates', 'tax_rate_components',
        'products', 'product_stock', 'inventory_movements',
        'shifts', 'sessions', 'orders', 'order_items', 'payments', 'audit_logs'
      ]) as t(name)
     where not has_table_privilege(
             'authenticated', ('public.' || quote_ident(t.name))::regclass, 'SELECT'
           )
  $$,
  'authenticated holds SELECT on every table with a client read path (SECURITY.md §4)'
);

-- ── Reads that must NOT exist ────────────────────────────────────────────────

select ok(
  not has_table_privilege('authenticated', 'public.members', 'SELECT'),
  'authenticated has no SELECT privilege on members — a revoked privilege, not a policy (D19)'
);

select ok(
  not has_table_privilege('authenticated', 'public.idempotency_keys', 'SELECT'),
  'authenticated has no SELECT privilege on idempotency_keys (SECURITY.md §4)'
);

select ok(
  not has_table_privilege('authenticated', 'public.receipt_counters', 'SELECT'),
  'authenticated has no SELECT privilege on receipt_counters (SECURITY.md §4)'
);

-- ── Function privileges ──────────────────────────────────────────────────────

select ok(
  not has_function_privilege(
    'authenticated',
    'public.provision_arena(uuid, text, text, text, text, uuid)',
    'EXECUTE'
  ),
  'authenticated cannot execute provision_arena: no P0 permission code covers creating '
  'an arena, and the self-serve path is M10'
);

select ok(
  not has_schema_privilege('anon', 'app', 'USAGE'),
  'anon cannot reach the app helper schema'
);

select is_empty(
  $$
    select p.proname::text
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
       and p.proname not in (
         'current_actor_id', 'current_arena_ids', 'is_arena_member', 'has_permission'
       )
  $$,
  'authenticated can execute only the four app helpers an RLS policy needs'
);

select is_empty(
  $$
    select t.name
      from unnest(array[
        'current_actor_id', 'current_arena_ids', 'is_arena_member', 'has_permission'
      ]) as t(name)
     where not exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = t.name
          and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     )
  $$,
  'the membership helpers RLS policies evaluate are executable by authenticated'
);

-- ── SECURITY DEFINER hygiene (SECURITY.md §5) ────────────────────────────────

select is_empty(
  $$
    select n.nspname || '.' || p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and p.prosecdef
       and not exists (
         select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
          where cfg like 'search_path=%'
       )
  $$,
  'every SECURITY DEFINER function pins an explicit search_path (SECURITY.md §5)'
);

select * from finish();
rollback;
