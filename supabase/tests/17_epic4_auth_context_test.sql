-- Epic 4 / M2 — Auth context: devices.platform + register_device permission/platform gates
-- Governed by docs/API.md §2 · docs/ROADMAP.md M2 · IMPLEMENTATION_PLAN Epic 4

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(7);

-- ── Platform CHECK accepts web / desktop (Epic 4 migration) ──────────────────

reset role;

select lives_ok(
  format(
    $$
      insert into public.devices (
        id, arena_id, name, platform, registered_by_user_id, last_seen_at, active
      ) values (
        'e4000000-0000-4000-8000-000000000001',
        %L,
        'Owner Web',
        'web',
        'aaaa0000-0000-4000-8000-000000000001',
        now(),
        true
      )
    $$,
    :'arena_a'
  ),
  'devices.platform CHECK accepts web'
);

select lives_ok(
  format(
    $$
      insert into public.devices (
        id, arena_id, name, platform, registered_by_user_id, last_seen_at, active
      ) values (
        'e4000000-0000-4000-8000-000000000002',
        %L,
        'Desktop shell',
        'desktop',
        'aaaa0000-0000-4000-8000-000000000001',
        now(),
        true
      )
    $$,
    :'arena_a'
  ),
  'devices.platform CHECK accepts desktop'
);

-- ── register_device as staff (holds station.view) ────────────────────────────

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select lives_ok(
  format(
    $$ select public.register_device(%L, 'e4000000-0000-4000-8000-000000000010', 'Tablet A', 'android', '0.1.0') $$,
    :'arena_a'
  ),
  'staff with station.view can register_device'
);

select lives_ok(
  format(
    $$ select public.register_device(%L, 'e4000000-0000-4000-8000-000000000011', 'Browser', 'web', '0.1.0') $$,
    :'arena_a'
  ),
  'register_device accepts platform web'
);

select throws_ok(
  format(
    $$ select public.register_device(%L, 'e4000000-0000-4000-8000-000000000012', 'Bad', 'console', null) $$,
    :'arena_a'
  ),
  'P0001',
  'validation_failed: invalid platform console',
  'register_device rejects unknown platform'
);

-- ── Outsider cannot register into arena A ────────────────────────────────────

reset role;
select pg_temp.become(:'user_outsider');
set local role authenticated;

select throws_ok(
  format(
    $$ select public.register_device(%L, 'e4000000-0000-4000-8000-000000000013', 'Spy', 'web', null) $$,
    :'arena_a'
  ),
  '42501',
  null,
  'non-member is refused register_device with insufficient_privilege'
);

-- Cross-tenant: arena B owner cannot register into arena A
reset role;
select pg_temp.become(:'user_b_owner');
set local role authenticated;

select throws_ok(
  format(
    $$ select public.register_device(%L, 'e4000000-0000-4000-8000-000000000014', 'B Web', 'web', null) $$,
    :'arena_a'
  ),
  '42501',
  null,
  'cross-tenant register_device is refused'
);

select * from finish();
rollback;
