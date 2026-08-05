-- Epic 10 / Wave A — Members P0 pgTAP.
-- Governed by docs/API.md §6 · D19 · D36.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(12);

\set member_new 'e1000000-0000-4000-8000-000000000001'
\set member_dup 'e1000000-0000-4000-8000-000000000002'

reset role;

-- Unauthenticated denial
select throws_ok(
  format(
    $$ select public.member_search(%L, 'Member') $$,
    :'arena_a'
  ),
  '42501',
  null,
  'Unauthenticated caller cannot search members'
);

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select has_function(
  'public', 'member_search', array['uuid', 'text', 'int'],
  'public.member_search(uuid, text, int) exists'
);

select throws_ok(
  format(
    $$ select public.member_search(%L, 'ab') $$,
    :'arena_a'
  ),
  'P0001',
  'validation_failed: search query must be at least 3 characters',
  'Search rejects queries shorter than 3 characters'
);

select ok(
  (public.member_search(:'arena_a'::uuid, 'Member')->'members')
    @> jsonb_build_array(
      jsonb_build_object('id', 'a0000000-0000-4000-8000-00000000000a')
    ),
  'Staff can search members by name'
);

select lives_ok(
  format(
    $$ select public.member_create(
         %L, %L, 'New Member', '5550009999', null, 'wave-a note', 'idem-member-create-1'
       ) $$,
    :'arena_a', :'member_new'
  ),
  'Staff can create a member with local phone digits'
);

select is(
  (public.member_get(:'arena_a'::uuid, :'member_new'::uuid)->>'phone') ~ '^\+[1-9][0-9]{6,14}$',
  true,
  'Created member phone is canonical E.164'
);

select throws_ok(
  format(
    $$ select public.member_create(
         %L, %L, 'Dup Phone', '5550009999', null, null, 'idem-member-create-2'
       ) $$,
    :'arena_a', :'member_dup'
  ),
  'P0001',
  format('conflict: member already exists with id %s', :'member_new'),
  'Duplicate live phone within arena is rejected'
);

-- member.update / member.block are manager+; use owner
reset role;
select pg_temp.become(:'user_a_owner');
set local role authenticated;

select lives_ok(
  format(
    $$ select public.member_update(%L, %L, 'Renamed Member', null, null, 'updated notes') $$,
    :'arena_a', :'member_new'
  ),
  'Owner can update a member'
);

select throws_ok(
  format(
    $$ select public.member_set_blocked(%L, %L, true, null) $$,
    :'arena_a', :'member_new'
  ),
  'P0001',
  'validation_failed: reason is required when blocking',
  'Block without reason is rejected'
);

select lives_ok(
  format(
    $$ select public.member_set_blocked(%L, %L, true, 'abuse') $$,
    :'arena_a', :'member_new'
  ),
  'Owner can block a member with a reason'
);

reset role;
select pg_temp.become(:'user_b_owner');
set local role authenticated;

select throws_ok(
  format(
    $$ select public.member_get(%L, %L) $$,
    :'arena_a', :'member_new'
  ),
  '42501',
  null,
  'Cross-arena member_get is denied'
);

select throws_ok(
  format(
    $$ select public.member_search(%L, 'Member') $$,
    :'arena_a'
  ),
  '42501',
  null,
  'Cross-arena member_search is denied'
);

select * from finish();
rollback;
