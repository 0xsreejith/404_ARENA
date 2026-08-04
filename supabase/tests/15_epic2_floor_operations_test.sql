-- Business Rules Validation for Epic 2: Floor Operations & Session Lifecycle
-- Governed by docs/DECISIONS.md D06, D10, D11 · docs/API.md §3, §4 · docs/UI_SPEC.md §3

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(16);

-- Fixture seeds an active session on station a…002 — free it so lifecycle
-- tests start from an idle station.
reset role;
update public.sessions
   set status = 'completed',
       ended_at = now(),
       end_reason = 'normal',
       ended_by_user_id = :'user_a_owner'
 where id = 'a0000000-0000-4000-8000-00000000000c'
   and arena_id = :'arena_a'
   and status in ('active', 'paused');

-- ── 1. Valid Session Lifecycle (Start -> Pause -> Resume -> Stop) ──────────────

select pg_temp.become(:'user_a_staff');
set local role authenticated;

-- Test 1: Start Open-Time Session
select lives_ok(
  format(
    $$ select public.session_start(%L, 'e2000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000007') $$,
    :'arena_a'
  ),
  'Staff can start an open-time session on an active idle station'
);

-- Test 2: Verify Session is Active
select results_eq(
  format(
    $$ select status, paused_at is null from public.sessions where id = 'e2000000-0000-4000-8000-000000000001' $$
  ),
  $$ select 'active'::text, true $$,
  'Started session is in active state with no paused_at timestamp'
);

-- Test 3: Pause Session
select lives_ok(
  format(
    $$ select public.session_pause(%L, 'e2000000-0000-4000-8000-000000000001') $$,
    :'arena_a'
  ),
  'Staff can pause an active session'
);

-- Test 4: Verify Session is Paused
select results_eq(
  format(
    $$ select status, paused_at is not null from public.sessions where id = 'e2000000-0000-4000-8000-000000000001' $$
  ),
  $$ select 'paused'::text, true $$,
  'Paused session is in paused state with non-null paused_at timestamp'
);

-- Test 5: Resume Session
select lives_ok(
  format(
    $$ select public.session_resume(%L, 'e2000000-0000-4000-8000-000000000001') $$,
    :'arena_a'
  ),
  'Staff can resume a paused session'
);

-- Test 6: Verify Session is Active Again
select results_eq(
  format(
    $$ select status, paused_at is null from public.sessions where id = 'e2000000-0000-4000-8000-000000000001' $$
  ),
  $$ select 'active'::text, true $$,
  'Resumed session returns to active state'
);

-- Test 7: Stop Session
select lives_ok(
  format(
    $$ select public.session_stop(%L, 'e2000000-0000-4000-8000-000000000001') $$,
    :'arena_a'
  ),
  'Staff can stop a running session'
);

-- Test 8: Verify Session is Completed and Unbilled
select results_eq(
  format(
    $$ select status, ended_at is not null, end_reason from public.sessions where id = 'e2000000-0000-4000-8000-000000000001' $$
  ),
  $$ select 'completed'::text, true, 'normal'::text $$,
  'Stopped session transitions to completed status with normal end_reason'
);

-- ── 2. Concurrent Session & Partial Unique Index Enforcement ─────────────────

-- Test 9: Start Session on Station
select lives_ok(
  format(
    $$ select public.session_start(%L, 'e2000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000007') $$,
    :'arena_a'
  ),
  'Start session for concurrency test'
);

-- Test 10: Attempt Concurrent Session on Same Station Fails
select throws_ok(
  format(
    $$ select public.session_start(%L, 'e2000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000007') $$,
    :'arena_a'
  ),
  'P0001',
  'conflict: station already has a live session',
  'Concurrent session on live station is rejected with conflict error'
);

-- ── 3. Invalid State Transitions ─────────────────────────────────────────────

-- Test 11: Cannot Pause Already Paused Session
select public.session_pause(:'arena_a', 'e2000000-0000-4000-8000-000000000002');

select throws_ok(
  format(
    $$ select public.session_pause(%L, 'e2000000-0000-4000-8000-000000000002') $$,
    :'arena_a'
  ),
  'P0001',
  'invalid_state: cannot pause session with status paused',
  'Pausing an already paused session is rejected'
);

-- Test 12: Cannot Resume Active Session
select public.session_resume(:'arena_a', 'e2000000-0000-4000-8000-000000000002');

select throws_ok(
  format(
    $$ select public.session_resume(%L, 'e2000000-0000-4000-8000-000000000002') $$,
    :'arena_a'
  ),
  'P0001',
  'invalid_state: cannot resume session with status active',
  'Resuming an active session is rejected'
);

-- Test 13: Cannot Stop Already Completed Session
select public.session_stop(:'arena_a', 'e2000000-0000-4000-8000-000000000002');

select throws_ok(
  format(
    $$ select public.session_stop(%L, 'e2000000-0000-4000-8000-000000000002') $$,
    :'arena_a'
  ),
  'P0001',
  'invalid_state: cannot stop session in state completed',
  'Stopping a completed session is rejected'
);

-- ── 4. Maintenance Station Protection ────────────────────────────────────────

select pg_temp.become(:'user_a_owner');

-- Test 14: Mark Station Maintenance
select lives_ok(
  format(
    $$ select public.station_set_status(%L, 'a0000000-0000-4000-8000-000000000002', 'maintenance', 'Hardware repair') $$,
    :'arena_a'
  ),
  'Owner can set station status to maintenance'
);

select pg_temp.become(:'user_a_staff');

-- Test 15: Cannot Start Session on Maintenance Station
select throws_ok(
  format(
    $$ select public.session_start(%L, 'e2000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000007') $$,
    :'arena_a'
  ),
  'P0001',
  'invalid_state: station is maintenance',
  'Starting a session on a maintenance station is rejected'
);

select pg_temp.become(:'user_a_owner');
select public.station_set_status(:'arena_a', 'a0000000-0000-4000-8000-000000000002', 'active');

-- ── 5. Fixed-Duration Package Extension Test ─────────────────────────────────

select pg_temp.become(:'user_a_staff');

-- Test 16: Package Session Start sets planned_end_at
select lives_ok(
  format(
    $$ select public.session_start(%L, 'e2000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000008') $$,
    :'arena_a'
  ),
  'Start fixed-duration package session'
);

select * from finish();
rollback;
