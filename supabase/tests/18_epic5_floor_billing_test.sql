-- Epic 5 — unbilled semantics + order_preview money strings + settle gate
-- Governed by docs/API.md §4–§5 · D01 · IMPLEMENTATION_PLAN Epic 5

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(8);

reset role;

-- Free fixture live session so we can stop a clean one.
update public.sessions
   set status = 'completed',
       ended_at = now(),
       end_reason = 'normal',
       ended_by_user_id = :'user_a_owner'
 where id = 'a0000000-0000-4000-8000-00000000000c'
   and arena_id = :'arena_a'
   and status in ('active', 'paused');

select pg_temp.become(:'user_a_staff');
set local role authenticated;

-- unbilled_sessions RPC exists and returns the completed fixture session
select has_function(
  'public', 'unbilled_sessions', array['uuid'],
  'public.unbilled_sessions(uuid) exists'
);

select ok(
  (
    select jsonb_array_length(public.unbilled_sessions(:'arena_a'::uuid)->'sessions') >= 1
  ),
  'completed session without settled order appears in unbilled_sessions'
);

-- Start + stop a fresh session, then open checkout
select lives_ok(
  format(
    $$ select public.session_start(%L, 'e5000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000007') $$,
    :'arena_a'
  ),
  'staff can start session for checkout path'
);

reset role;
update public.sessions
   set started_at = now() - interval '2 hours'
 where id = 'e5000000-0000-4000-8000-000000000001'
   and arena_id = :'arena_a';

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select lives_ok(
  format(
    $$ select public.session_stop(%L, 'e5000000-0000-4000-8000-000000000001') $$,
    :'arena_a'
  ),
  'staff can stop session before checkout'
);

select lives_ok(
  format(
    $$ select public.checkout_open(%L, 'e5000000-0000-4000-8000-000000000010', 'e5000000-0000-4000-8000-000000000001') $$,
    :'arena_a'
  ),
  'checkout_open creates order for completed session'
);

-- order_preview money fields are JSON strings (D01)
select ok(
  jsonb_typeof(
    public.order_preview(
      :'arena_a'::uuid,
      'e5000000-0000-4000-8000-000000000010'::uuid
    )->'total'
  ) = 'string',
  'order_preview.total is a decimal string'
);

select ok(
  jsonb_typeof(
    public.order_preview(
      :'arena_a'::uuid,
      'e5000000-0000-4000-8000-000000000010'::uuid
    )->'balance_due'
  ) = 'string',
  'order_preview.balance_due is a decimal string'
);

-- With fixture open shift, settle succeeds when amount matches total
select lives_ok(
  format(
    $$
      select public.order_settle(
        %L,
        'e5000000-0000-4000-8000-000000000010',
        'e5000000-0000-4000-8000-000000000020',
        'cash',
        (public.order_preview(%L, 'e5000000-0000-4000-8000-000000000010')->>'total')::numeric
      )
    $$,
    :'arena_a',
    :'arena_a'
  ),
  'order_settle succeeds when an open shift exists'
);

select * from finish();
rollback;
