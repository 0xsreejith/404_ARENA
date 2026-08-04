-- M1 — tenant isolation, per table, as a real authenticated caller.
--
-- SECURITY.md §15 assertion 1 asks for this "asserted per table across all 28
-- tables — not a spot check". The loop below enumerates every table carrying
-- arena_id from the catalogue, so a table added later is covered automatically
-- and cannot quietly escape the assertion.
--
-- Covers SECURITY.md §15 assertions 1 and 14, and the M1 exit clause "a user in
-- arena A can neither read nor write any row of arena B".

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(15);

-- Probes run inside the authenticated role, so RLS applies. The three tables
-- with no client read at all are excluded here and asserted separately below —
-- selecting from them raises a privilege error rather than returning nothing.
create function pg_temp.arena_row_counts(p_arena_id uuid)
returns table (relation text, rows_visible bigint)
language plpgsql
as $probe$
declare
  v_table text;
  v_count bigint;
begin
  for v_table in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
       and c.relname not in ('members', 'receipt_counters', 'idempotency_keys')
       and exists (
         select 1 from information_schema.columns col
          where col.table_schema = 'public'
            and col.table_name = c.relname
            and col.column_name = 'arena_id'
       )
     order by c.relname
  loop
    execute format('select count(*) from public.%I where arena_id = $1', v_table)
      into v_count using p_arena_id;
    relation := v_table;
    rows_visible := v_count;
    return next;
  end loop;
end;
$probe$;

-- The probe plus the tables asserted individually below must account for all 28
-- tables. Without this, the loop could silently cover nothing and every
-- isolation assertion below would pass vacuously.
select set_eq(
  format(
    $$ select relation from pg_temp.arena_row_counts(%L)
        union all
       select unnest(array['members', 'receipt_counters', 'idempotency_keys',
                           'arenas', 'organizations', 'profiles', 'permissions']) $$,
    :'arena_a'
  ),
  $$
    select c.relname::text
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
  $$,
  'the probe plus the individually asserted tables account for all 28 tables'
);

-- ── A member of arena A ──────────────────────────────────────────────────────

select pg_temp.become(:'user_a_owner');
set local role authenticated;

select is_empty(
  format(
    $$ select relation from pg_temp.arena_row_counts(%L) where rows_visible > 0 $$,
    :'arena_b'
  ),
  'a user of arena A sees zero rows of arena B on every tenant-owned table (assertion 1)'
);

select is_empty(
  format(
    $$ select relation from pg_temp.arena_row_counts(%L) where rows_visible = 0 $$,
    :'arena_a'
  ),
  'the same user does see arena A''s own rows on every tenant-owned table — '
  'so the assertion above is not passing vacuously'
);

select is_empty(
  format($$ select id::text from public.arenas where id <> %L $$, :'arena_a'),
  'arenas itself is scoped: only the caller''s arena is visible'
);

select is_empty(
  $$
    select o.name from public.organizations o where o.name = 'Organisation Two'
  $$,
  'organizations is readable only for organizations owning an arena the caller belongs to'
);

select is_empty(
  $$ select p.display_name from public.profiles p where p.display_name = 'B Owner' $$,
  'a profile is readable only to users sharing an arena (SECURITY.md §4)'
);

select isnt_empty(
  $$ select p.display_name from public.profiles p where p.display_name = 'A Staff' $$,
  'a profile IS readable to a user sharing an arena'
);

select is(
  (select count(*) from public.permissions)::int,
  33,
  'the permission catalogue is global: all 33 codes are readable (PERMISSIONS.md §1)'
);

-- ── Tables with no client read path at all ───────────────────────────────────

select throws_ok(
  'select 1 from public.members',
  '42501',
  null,
  'members cannot be selected at all — there is no query a client can write that '
  'returns the member table (D19)'
);

select throws_ok(
  'select 1 from public.idempotency_keys',
  '42501',
  null,
  'idempotency_keys has no client read path'
);

select throws_ok(
  'select 1 from public.receipt_counters',
  '42501',
  null,
  'receipt_counters has no client read path'
);

-- ── Writes have no client path either ────────────────────────────────────────

select throws_ok(
  format(
    $$ insert into public.sessions (id, arena_id, station_id, billing_plan_id, status,
         started_by_user_id, started_at, pricing_snapshot, business_date)
       values (gen_random_uuid(), %L, %L, %L, 'active', %L, now(), '{}'::jsonb, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000007', :'user_a_owner'
  ),
  '42501',
  null,
  'a member of arena A cannot insert into their own arena''s sessions either (D05)'
);

select throws_ok(
  format($$ update public.orders set total = 0 where arena_id = %L $$, :'arena_a'),
  '42501',
  null,
  'money columns are not client-writable (audit §3)'
);

-- ── A member of the same arena without report.view ───────────────────────────

reset role;
select pg_temp.become(:'user_a_staff');
set local role authenticated;

select is(
  (select count(*) from public.audit_logs)::int,
  0,
  'a staff user without report.view reads no audit rows, even in their own arena'
);

-- ── An authenticated user who belongs to no arena ────────────────────────────

reset role;
select pg_temp.become(:'user_outsider');
set local role authenticated;

select is_empty(
  format(
    $$ select relation from pg_temp.arena_row_counts(%L)
        where rows_visible > 0
        union all
       select relation from pg_temp.arena_row_counts(%L) where rows_visible > 0 $$,
    :'arena_a', :'arena_b'
  ),
  'an authenticated non-member sees nothing of either tenant'
);

reset role;
select * from finish();
rollback;
