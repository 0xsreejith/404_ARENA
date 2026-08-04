-- M1 — the app helper functions.
--
-- Actor derivation, membership, permission resolution, business date, the open
-- shift, and the audit writer.
--
-- Covers SECURITY.md §15 assertions 7 (as far as an M1 surface allows), 8
-- and 15.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(20);

-- ── Actor identity comes from auth.uid(), never from a parameter ─────────────

select is_empty(
  $$
    select p.proname || '(' || pg_get_function_arguments(p.oid) || ')'
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app')
       and pg_get_function_arguments(p.oid) ~
           '(p_actor|p_created_by|p_started_by|p_ended_by|p_opened_by|p_settled_by|p_authorised_by)'
  $$,
  'no function accepts an actor parameter — the server derives it (D04, assertion 8)'
);

-- Money is never an RPC input except where a human genuinely enters an amount,
-- and no such RPC exists yet in M1 (API.md §1). This is the half of assertion 9
-- the M1 surface can express; the settlement half arrives with order_settle.
select is_empty(
  $$
    select p.proname || '(' || pg_get_function_arguments(p.oid) || ')'
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_function_arguments(p.oid) ~ '\mnumeric\M'
  $$,
  'no public RPC accepts a money value in M1 (API.md §1, assertion 9)'
);

select pg_temp.become(:'user_a_owner');
set local role authenticated;

select is(
  app.current_actor_id(),
  :'user_a_owner'::uuid,
  'app.current_actor_id() resolves to auth.uid() (D04)'
);

select results_eq(
  format($$ select a from app.current_arena_ids() a $$),
  format($$ select %L::uuid $$, :'arena_a'),
  'app.current_arena_ids() returns exactly the caller''s active memberships'
);

select ok(app.is_arena_member(:'arena_a'::uuid), 'the caller is a member of arena A');
select ok(not app.is_arena_member(:'arena_b'::uuid), 'the caller is not a member of arena B');

select ok(
  app.has_permission(:'arena_a'::uuid, 'report.view'),
  'the seeded owner role holds report.view'
);

select ok(
  not app.has_permission(:'arena_b'::uuid, 'session.view'),
  'holding a permission in one arena grants nothing in another (C11)'
);

reset role;

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select ok(
  app.has_permission(:'arena_a'::uuid, 'session.start'),
  'the seeded staff role holds session.start (PERMISSIONS.md §2)'
);

select ok(
  not app.has_permission(:'arena_a'::uuid, 'report.view'),
  'the seeded staff role does not hold report.view'
);

select ok(
  not app.has_permission(:'arena_a'::uuid, 'pricing.manage'),
  'the seeded staff role does not hold pricing.manage'
);

reset role;

-- ── require_permission is the gate every mutating RPC opens with ─────────────

select pg_temp.become(:'user_outsider');

select throws_ok(
  format($$ select app.require_permission(%L, 'session.start') $$, :'arena_a'),
  '42501',
  null,
  'a non-member is refused with insufficient_privilege, and is not told the arena exists'
);

select pg_temp.become(:'user_a_staff');

select throws_ok(
  format($$ select app.require_permission(%L, 'report.view') $$, :'arena_a'),
  '42501',
  null,
  'a member lacking the code is refused with insufficient_privilege (assertion 7)'
);

select lives_ok(
  format($$ select app.require_permission(%L, 'session.start') $$, :'arena_a'),
  'a member holding the code passes'
);

-- Deactivating membership removes access on the next call (SECURITY.md §3).
update public.arena_users set active = false
 where arena_id = :'arena_a' and user_id = :'user_a_staff';

select throws_ok(
  format($$ select app.require_permission(%L, 'session.start') $$, :'arena_a'),
  '42501',
  null,
  'deactivating arena_users.active removes access immediately'
);

-- ── Business date, derived from arena timezone and trading hours ─────────────

select is(
  app.business_date(:'arena_a'::uuid, timestamptz '2026-07-30T02:00:00Z'),
  date '2026-07-29',
  'a timestamp before business_day_start_time belongs to the previous business day (D09)'
);

select is(
  app.business_date(:'arena_a'::uuid, timestamptz '2026-07-30T09:00:00Z'),
  date '2026-07-30',
  'a timestamp after business_day_start_time belongs to that business day'
);

-- ── The open shift ───────────────────────────────────────────────────────────

select is(
  app.current_shift_id(:'arena_a'::uuid),
  'a0000000-0000-4000-8000-00000000000b'::uuid,
  'app.current_shift_id returns the single open shift (D30)'
);

-- ── app.audit writes exactly one row, with a server-derived actor ────────────

select pg_temp.become(:'user_a_owner');

select lives_ok(
  format(
    $$ select app.audit(%L, 'station.status_changed', 'station', %L,
                        jsonb_build_object('to', 'maintenance')) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002'
  ),
  'app.audit inserts in the caller''s transaction (D22)'
);

select results_eq(
  format(
    $$ select action, actor_user_id, business_date
         from public.audit_logs
        where arena_id = %L and entity_id = %L $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002'
  ),
  format(
    $$ select 'station.status_changed'::text, %L::uuid, app.business_date(%L, now()) $$,
    :'user_a_owner', :'arena_a'
  ),
  'exactly one audit row, attributed to auth.uid(), stamped with the server business date'
);

select * from finish();
rollback;
