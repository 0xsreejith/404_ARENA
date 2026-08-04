-- M1 — layer 2: Row Level Security, at the catalogue level.
--
-- Data-level isolation is asserted in 04_tenant_isolation_test.sql. This file
-- proves the policy surface itself is right: RLS on everything, no write
-- policies at all, and deny-by-default on the three tables with no client read.
--
-- Covers SECURITY.md §15 assertion 2.

begin;
set local search_path to extensions, public, pg_catalog;

select plan(6);

select is_empty(
  $$
    select c.relname::text
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
       and not c.relrowsecurity
  $$,
  'RLS is enabled on every table in public, including those with no client read (SECURITY.md §4)'
);

select is_empty(
  $$
    select c.relname::text
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
       and c.relname not in ('members', 'receipt_counters', 'idempotency_keys')
       and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
  $$,
  'every table with a client read path has a read policy'
);

select is_empty(
  $$
    select c.relname::text
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('members', 'receipt_counters', 'idempotency_keys')
       and exists (select 1 from pg_policy p where p.polrelid = c.oid)
  $$,
  'members, receipt_counters and idempotency_keys have no policy at all: '
  'RLS enabled with no policy denies everything, which is the correct default'
);

select is_empty(
  $$
    select c.relname || ' / ' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and p.polcmd <> 'r'
  $$,
  'no table has an INSERT, UPDATE, DELETE or ALL policy — writes have no client path (D05)'
);

select is_empty(
  $$
    select c.relname || ' / ' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and (p.polroles = '{0}'::oid[]                       -- PUBLIC
            or not (p.polroles @> array['authenticated'::regrole::oid]))
  $$,
  'every policy is granted TO authenticated, never TO PUBLIC'
);

-- audit_logs is the one table whose read rule is arena scope AND a permission
-- code (SECURITY.md §4).
select ok(
  (select pg_get_expr(p.polqual, p.polrelid)
     from pg_policy p
     join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'audit_logs')
  like '%report.view%',
  'the audit_logs read policy additionally requires report.view (SECURITY.md §4)'
);

select * from finish();
rollback;
