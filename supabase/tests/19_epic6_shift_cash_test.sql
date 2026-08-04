-- Epic 6 — Shift and cash pgTAP.
-- Governed by docs/API.md §6 · D08 · D29 · D30.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(9);

\set shift_new 'e6000000-0000-4000-8000-000000000001'
\set shift_second 'e6000000-0000-4000-8000-000000000002'
\set order_cash 'e6000000-0000-4000-8000-000000000010'
\set item_play 'e6000000-0000-4000-8000-000000000011'
\set payment_cash 'e6000000-0000-4000-8000-000000000012'

reset role;

-- Fixture starts with an open shift. Close it directly so the RPC can open a
-- production shift, but leave the fixture open order in place for the close gate.
update public.shifts
   set status = 'closed',
       closed_by_user_id = :'user_a_owner',
       closed_at = now(),
       expected_cash = 200.00,
       counted_cash = 200.00,
       notes = 'fixture shift closed for epic6 test'
 where id = 'a0000000-0000-4000-8000-00000000000b'
   and arena_id = :'arena_a';

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select has_function(
  'public', 'shift_current', array['uuid'],
  'public.shift_current(uuid) exists'
);

select lives_ok(
  format(
    $$ select public.shift_open(%L, %L, 250.00, 'idem-shift-open-1') $$,
    :'arena_a', :'shift_new'
  ),
  'Staff can open a shift'
);

select is(
  public.shift_current(:'arena_a'::uuid)->>'id',
  :'shift_new',
  'shift_current returns the open shift'
);

select throws_ok(
  format(
    $$ select public.shift_open(%L, %L, 10.00, 'idem-shift-open-2') $$,
    :'arena_a', :'shift_second'
  ),
  'P0001',
  'invalid_state: a shift is already open (D30)',
  'Opening a second shift is rejected'
);

reset role;

insert into public.orders (
  id, arena_id, status, subtotal, tax_total, total, paid_total,
  receipt_sequence, receipt_number, opened_by_user_id, settled_by_user_id,
  settled_at, business_date
)
values (
  :'order_cash', :'arena_a', 'settled', 42.50, 2.50, 42.50, 42.50,
  9001, 'SHIFT-TEST-9001', :'user_a_owner', :'user_a_owner',
  now(), app.business_date(:'arena_a'::uuid, now())
);

insert into public.order_items (
  id, arena_id, order_id, type, session_id, name_snapshot, quantity, unit_price,
  line_subtotal, taxable_amount, tax_rate_id, tax_rate_snapshot, tax_amount, line_total
)
values (
  :'item_play', :'arena_a', :'order_cash', 'play',
  'a0000000-0000-4000-8000-00000000000c', 'Shift test play', 1,
  42.50, 42.50, 40.00, 'a0000000-0000-4000-8000-000000000004',
  jsonb_build_object('schema_version', 1, 'percent', '10.00', 'inclusive', true),
  2.50, 42.50
);

insert into public.payments (
  id, arena_id, order_id, shift_id, method, amount, actor_user_id, business_date
)
values (
  :'payment_cash', :'arena_a', :'order_cash', :'shift_new', 'cash', 42.50,
  :'user_a_owner', app.business_date(:'arena_a'::uuid, now())
);

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select results_eq(
  format(
    $$ select public.shift_summary(%L, %L)->>'expected_cash',
              public.shift_summary(%L, %L)->'payments_by_method'->>'cash' $$,
    :'arena_a', :'shift_new', :'arena_a', :'shift_new'
  ),
  $$ select '292.50'::text, '42.50'::text $$,
  'Summary expected cash is opening float plus cash payments from payments.shift_id'
);

select results_eq(
  format(
    $$ select (public.shift_summary(%L, %L)->>'order_count')::int,
              public.shift_summary(%L, %L)->'sales'->>'play' $$,
    :'arena_a', :'shift_new', :'arena_a', :'shift_new'
  ),
  $$ select 1, '42.50'::text $$,
  'Summary includes order count and play sales for shift payments'
);

reset role;
select pg_temp.become(:'user_a_owner');
set local role authenticated;

select throws_ok(
  format(
    $$ select public.shift_close(%L, %L, 292.50, null, 'idem-shift-close-open-order') $$,
    :'arena_a', :'shift_new'
  ),
  'P0001',
  'invalid_state: close or void open orders before closing shift',
  'Closing rejects while any order is open'
);

reset role;

update public.orders
   set status = 'void',
       void_reason = 'epic6 close test reset'
 where id = 'a0000000-0000-4000-8000-00000000000d'
   and arena_id = :'arena_a';

select pg_temp.become(:'user_a_owner');
set local role authenticated;

select throws_ok(
  format(
    $$ select public.shift_close(%L, %L, 300.00, null, 'idem-shift-close-no-notes') $$,
    :'arena_a', :'shift_new'
  ),
  'P0001',
  'validation_failed: notes are required when cash variance is non-zero (D29)',
  'Variance requires notes'
);

select results_eq(
  format(
    $$ select public.shift_close(%L, %L, 300.00, 'cash over by count', 'idem-shift-close-1')->>'variance' $$,
    :'arena_a', :'shift_new'
  ),
  $$ select '7.50'::text $$,
  'Shift closes with notes and records variance'
);

select * from finish();
rollback;
