-- M1 — constraints and status transitions.
--
-- Layer 4 of the security model: schema constraints that hold even if a bug
-- reaches layers 1 to 3 (SECURITY.md §1). Run as the migration role, because
-- these are properties of the schema rather than of a policy.
--
-- Covers SECURITY.md §15 assertion 10 (the deterministic half — the concurrent
-- race is M4's exit criterion) and the M1 clause "important database
-- constraints and status transitions".

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(24);

-- ── One live session per station (OFFLINE.md §4) ─────────────────────────────

select throws_ok(
  format(
    $$ insert into public.sessions
         (id, arena_id, station_id, billing_plan_id, status, started_by_user_id,
          started_at, pricing_snapshot, business_date)
       values (gen_random_uuid(), %L, %L, %L, 'active', %L, now(), '{}'::jsonb, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000007', :'user_a_owner'
  ),
  '23505',
  null,
  'a second live session on the same station is rejected by the database'
);

select throws_ok(
  format(
    $$ insert into public.sessions
         (id, arena_id, station_id, billing_plan_id, status, started_by_user_id,
          started_at, paused_at, pricing_snapshot, business_date)
       values (gen_random_uuid(), %L, %L, %L, 'paused', %L, now(), now(),
               '{}'::jsonb, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000007', :'user_a_owner'
  ),
  '23505',
  null,
  'a paused session counts as live: the index covers active AND paused'
);

select lives_ok(
  format(
    $$ insert into public.sessions
         (id, arena_id, station_id, billing_plan_id, status, started_by_user_id,
          started_at, ended_by_user_id, ended_at, end_reason, pricing_snapshot, business_date)
       values ('a0000000-0000-4000-8000-0000000000d1', %L, %L, %L, 'completed', %L, now(),
               %L, now(), 'normal', '{}'::jsonb, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000007', :'user_a_owner', :'user_a_owner'
  ),
  'a completed session on the same station is fine — the station is free again'
);

-- ── One open shift per arena (D30) ───────────────────────────────────────────

select throws_ok(
  format(
    $$ insert into public.shifts
         (id, arena_id, business_date, status, opened_by_user_id, opened_at, opening_float)
       values (gen_random_uuid(), %L, current_date, 'open', %L, now(), 0) $$,
    :'arena_a', :'user_a_owner'
  ),
  '23505',
  null,
  'a second open shift in the same arena is rejected (D30)'
);

-- ── One live order per session, void excluded (D07) ──────────────────────────

select throws_ok(
  format(
    $$ insert into public.orders (id, arena_id, session_id, status, opened_by_user_id,
                                  business_date)
       values (gen_random_uuid(), %L, %L, 'open', %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-00000000000c', :'user_a_owner'
  ),
  '23505',
  null,
  'a session cannot have two live orders'
);

select lives_ok(
  format(
    $$ update public.orders set status = 'void', void_reason = 'test' where id = %L;
       insert into public.orders (id, arena_id, session_id, status, opened_by_user_id,
                                  business_date)
       values ('a0000000-0000-4000-8000-0000000000d2', %L, %L, 'open', %L, current_date) $$,
    'a0000000-0000-4000-8000-00000000000d', :'arena_a',
    'a0000000-0000-4000-8000-00000000000c', :'user_a_owner'
  ),
  'a session whose order was voided can be checked out again (D07, API.md §5)'
);

select throws_ok(
  format(
    $$ insert into public.order_items
         (id, arena_id, order_id, type, session_id, name_snapshot, quantity, unit_price,
          line_subtotal, taxable_amount, tax_rate_snapshot, line_total)
       values (gen_random_uuid(), %L, %L, 'play', %L, 'Second play line', 1, 1, 1, 1,
               '{}'::jsonb, 1) $$,
    :'arena_a', 'a0000000-0000-4000-8000-00000000000d',
    'a0000000-0000-4000-8000-00000000000c'
  ),
  '23505',
  null,
  'at most one play line per order (DATABASE.md §10)'
);

-- ── Catalogue partial uniques are partial on deleted_at (D17) ────────────────

select throws_ok(
  format(
    $$ insert into public.stations (id, arena_id, zone_id, station_type_id, name)
       select gen_random_uuid(), %L, zone_id, station_type_id, name
         from public.stations where id = %L $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000002'
  ),
  '23505',
  null,
  'two live stations cannot share a name within an arena'
);

select lives_ok(
  format(
    $$ update public.stations set deleted_at = now() where id = %L;
       insert into public.stations (id, arena_id, zone_id, station_type_id, name)
       select gen_random_uuid(), %L, z.id, %L, 'Station One'
         from public.zones z where z.arena_id = %L limit 1 $$,
    'a0000000-0000-4000-8000-000000000002', :'arena_a',
    'a0000000-0000-4000-8000-000000000001', :'arena_a'
  ),
  'a soft-deleted station releases its name: uniqueness is partial on deleted_at IS NULL'
);

select throws_ok(
  format(
    $$ insert into public.products (id, arena_id, name, sku, selling_price)
       values (gen_random_uuid(), %L, 'Another name', 'SKU-1', 1.00) $$,
    :'arena_a'
  ),
  '23505',
  null,
  'product SKU is unique per arena while live'
);

-- ── The same name in a DIFFERENT arena is fine ───────────────────────────────

select is(
  (select count(*) from public.products where name = 'Product One' and sku = 'SKU-1')::int,
  2,
  'uniqueness is scoped per arena: both tenants hold a live product of the same name and SKU'
);

-- ── CHECK constraints ────────────────────────────────────────────────────────

select throws_ok(
  format(
    $$ insert into public.billing_plans (arena_id, name, type, hourly_rate, duration_minutes)
       values (%L, 'Broken plan', 'open_time', 10.00, 60) $$,
    :'arena_a'
  ),
  '23514',
  null,
  'an open_time plan cannot also carry package columns (DATABASE.md §5)'
);

select throws_ok(
  format(
    $$ insert into public.billing_plans (arena_id, name, type, fixed_price)
       values (%L, 'Broken package', 'fixed_duration', 10.00) $$,
    :'arena_a'
  ),
  '23514',
  null,
  'a fixed_duration plan must carry duration_minutes'
);

select throws_ok(
  format(
    $$ insert into public.members (id, arena_id, full_name, phone, created_by_user_id)
       values (gen_random_uuid(), %L, 'Bad Phone', '9876543210', %L) $$,
    :'arena_a', :'user_a_owner'
  ),
  '23514',
  null,
  'members.phone accepts canonical E.164 only (D36)'
);

select throws_ok(
  format(
    $$ update public.members set blocked = true where arena_id = %L $$,
    :'arena_a'
  ),
  '23514',
  null,
  'blocking a member requires a reason'
);

select throws_ok(
  format(
    $$ update public.stations set status = 'maintenance' where arena_id = %L $$,
    :'arena_a'
  ),
  '23514',
  null,
  'a non-active station status requires a reason (DATABASE.md §4)'
);

select throws_ok(
  format(
    $$ insert into public.inventory_movements
         (id, arena_id, product_id, type, quantity, actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, 'restock', -1, %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000009', :'user_a_owner'
  ),
  '23514',
  null,
  'a restock cannot be negative: the sign is constrained per movement type (D20)'
);

select throws_ok(
  format(
    $$ insert into public.inventory_movements
         (id, arena_id, product_id, type, quantity, actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, 'sale', -1, %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000009', :'user_a_owner'
  ),
  '23514',
  null,
  'a sale movement must reference the order line that caused it'
);

select throws_ok(
  format(
    $$ insert into public.payments
         (id, arena_id, order_id, shift_id, method, amount, reverses_payment_id,
          actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, %L, 'cash', 5.00, %L, %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-0000000000d2',
    'a0000000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-00000000000f',
    :'user_a_owner'
  ),
  '23514',
  null,
  'a reversal must be negative and a normal payment positive (D21)'
);

select throws_ok(
  format(
    $$ update public.orders set discount_kind = 'flat', discount_value = 5 where id = %L $$,
    'a0000000-0000-4000-8000-0000000000d2'
  ),
  '23514',
  null,
  'a discount without a reason and an authoriser is rejected (D14)'
);

-- ── Session status transitions (DATABASE.md §9) ──────────────────────────────

select lives_ok(
  format(
    $$ update public.sessions set status = 'paused', paused_at = now() where id = %L $$,
    'a0000000-0000-4000-8000-00000000000c'
  ),
  'active -> paused is permitted'
);

select throws_ok(
  format(
    $$ update public.sessions set status = 'active' where id = %L $$,
    'a0000000-0000-4000-8000-00000000000c'
  ),
  '23514',
  null,
  'paused_at must be cleared when leaving paused — the state shape is constrained'
);

select lives_ok(
  format(
    $$ update public.sessions
          set status = 'completed', paused_at = null, ended_at = now(),
              ended_by_user_id = %L, end_reason = 'normal'
        where id = %L $$,
    :'user_a_owner', 'a0000000-0000-4000-8000-00000000000c'
  ),
  'paused -> completed is permitted'
);

select throws_ok(
  format(
    $$ update public.sessions set status = 'active', ended_at = null,
             ended_by_user_id = null, end_reason = null where id = %L $$,
    'a0000000-0000-4000-8000-00000000000c'
  ),
  'P0001',
  null,
  'completed is terminal: no path moves a session back out of it (D06)'
);

select * from finish();
rollback;
