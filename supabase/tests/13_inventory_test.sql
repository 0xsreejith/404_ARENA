-- M1 — inventory as signed, immutable movements.
--
-- Stock is derived, never a mutable column. Negative stock is permitted and
-- flagged rather than blocking a sale (D20).
--
-- Immutability of the movements themselves is asserted in 07; this file is
-- about the materialisation staying honest.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(6);

-- The fixture opened with +10.
select is(
  (select quantity from public.product_stock
    where arena_id = :'arena_a' and product_id = 'a0000000-0000-4000-8000-000000000009'),
  10.000::numeric,
  'an opening movement materialises product_stock by trigger (D20)'
);

insert into public.inventory_movements
  (id, arena_id, product_id, type, quantity, actor_user_id, business_date)
values
  (gen_random_uuid(), :'arena_a', 'a0000000-0000-4000-8000-000000000009',
   'restock', 5.000, :'user_a_owner', app.business_date(:'arena_a', now())),
  (gen_random_uuid(), :'arena_a', 'a0000000-0000-4000-8000-000000000009',
   'wastage', -2.500, :'user_a_owner', app.business_date(:'arena_a', now())),
  (gen_random_uuid(), :'arena_a', 'a0000000-0000-4000-8000-000000000009',
   'correction', -20.000, :'user_a_owner', app.business_date(:'arena_a', now()));

select is(
  (select quantity from public.product_stock
    where arena_id = :'arena_a' and product_id = 'a0000000-0000-4000-8000-000000000009'),
  (-7.500)::numeric,
  'stock accumulates from signed movements and is allowed to go negative (D20)'
);

select is_empty(
  format($$ select product_id::text from app.product_stock_drift(%L) $$, :'arena_a'),
  'product_stock always equals the sum of movements — the reconciliation query is empty '
  '(DATABASE.md §7)'
);

select is(
  (select quantity from public.product_stock
    where arena_id = :'arena_b' and product_id = 'b0000000-0000-4000-8000-000000000009'),
  10.000::numeric,
  'arena B''s stock is untouched by arena A''s movements'
);

select throws_ok(
  format(
    $$ insert into public.inventory_movements
         (id, arena_id, product_id, type, quantity, actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, 'correction', 0, %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000009', :'user_a_owner'
  ),
  '23514',
  null,
  'a zero-quantity movement is meaningless and is rejected'
);

-- A client cannot touch the materialisation directly, only the movements — and
-- it has no privilege for those either.
select pg_temp.become(:'user_a_owner');
set local role authenticated;

select throws_ok(
  format(
    $$ update public.product_stock set quantity = 999 where arena_id = %L $$, :'arena_a'
  ),
  '42501',
  null,
  'product_stock is never client-writable (D20)'
);

reset role;
select * from finish();
rollback;
