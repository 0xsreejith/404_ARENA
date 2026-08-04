-- M1 — composite tenant foreign keys reject cross-arena references.
--
-- Run as the migration role, deliberately: RLS is bypassed here so the
-- assertion is about the constraint itself, not about a policy that happens to
-- hide the row (SECURITY.md §15 assertion 4).
--
-- Covers SECURITY.md §15 assertions 3, 4 and 5.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(8);

-- Walks every composite tenant relationship in the catalogue and tries to point
-- an arena A row at an arena B parent. A relationship added later is covered
-- without touching this file.
--
-- payments and inventory_movements are excluded because they are append-only:
-- any UPDATE on them raises before the foreign key is ever evaluated. They are
-- asserted separately below, by insert.
create function pg_temp.cross_arena_fk_survivors(p_arena_a uuid, p_arena_b uuid)
returns table (relation text, offending_column text)
language plpgsql
as $probe$
declare
  v_fk     record;
  v_foreign_id uuid;
begin
  for v_fk in
    select child.relname::text  as child_table,
           parent.relname::text as parent_table,
           att.attname::text    as col
      from pg_constraint con
      join pg_class child on child.oid = con.conrelid
      join pg_namespace nchild on nchild.oid = child.relnamespace
      join pg_class parent on parent.oid = con.confrelid
      join pg_namespace nparent on nparent.oid = parent.relnamespace
      join lateral unnest(con.conkey) as k(attnum) on true
      join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
     where con.contype = 'f'
       and nchild.nspname = 'public'
       and nparent.nspname = 'public'
       and att.attname <> 'arena_id'
       and child.relname not in ('payments', 'inventory_movements')
       and exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = child.relname
            and c.column_name = 'arena_id'
       )
       and exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = parent.relname
            and c.column_name = 'arena_id'
       )
     order by 1, 3
  loop
    execute format('select id from public.%I where arena_id = $1 limit 1', v_fk.parent_table)
      into v_foreign_id using p_arena_b;
    continue when v_foreign_id is null;

    begin
      execute format(
        'update public.%I set %I = $1
          where ctid = (select ctid from public.%I where arena_id = $2 limit 1)',
        v_fk.child_table, v_fk.col, v_fk.child_table
      ) using v_foreign_id, p_arena_a;

      -- Reaching here means the cross-arena reference was accepted. Raise so
      -- the subtransaction rolls back either way, then report it.
      raise exception 'cross_arena_reference_survived' using errcode = 'P0001';
    exception
      when others then
        if sqlerrm like 'cross_arena_reference_survived%' then
          relation := v_fk.child_table;
          offending_column := v_fk.col;
          return next;
        end if;
    end;
  end loop;
end;
$probe$;

select is_empty(
  format(
    $$ select relation || '.' || offending_column from pg_temp.cross_arena_fk_survivors(%L, %L) $$,
    :'arena_a', :'arena_b'
  ),
  'no composite tenant relationship accepts a cross-arena reference (D03, assertion 3)'
);

-- The relationships SECURITY.md §15 names explicitly, asserted with the exact
-- SQLSTATE so a unique-violation cannot masquerade as proof.
--
-- Each needs an unreferenced arena B target, otherwise a partial unique index
-- (one live session per station, one live order per session, one play line per
-- order) fires first and proves the wrong thing.

insert into public.stations (id, arena_id, zone_id, station_type_id, name)
select 'b0000000-0000-4000-8000-0000000000e2', :'arena_b', z.id,
       'b0000000-0000-4000-8000-000000000001', 'Station Two'
  from public.zones z where z.arena_id = :'arena_b' limit 1;

insert into public.sessions
  (id, arena_id, station_id, billing_plan_id, status, started_by_user_id, started_at,
   ended_by_user_id, ended_at, end_reason, pricing_snapshot, business_date)
values ('b0000000-0000-4000-8000-0000000000e3', :'arena_b',
        'b0000000-0000-4000-8000-0000000000e2', 'b0000000-0000-4000-8000-000000000007',
        'completed', :'user_b_owner', now(), :'user_b_owner', now(), 'normal',
        '{}'::jsonb, app.business_date(:'arena_b', now()));

insert into public.orders
  (id, arena_id, status, opened_by_user_id, business_date)
values ('b0000000-0000-4000-8000-0000000000e4', :'arena_b', 'open', :'user_b_owner',
        app.business_date(:'arena_b', now()));

select throws_ok(
  format(
    $$ update public.orders set session_id = %L where id = %L $$,
    'b0000000-0000-4000-8000-0000000000e3', 'a0000000-0000-4000-8000-00000000000d'
  ),
  '23503',
  null,
  'orders.session_id cannot reference a session in another arena (assertion 4)'
);

select throws_ok(
  format(
    $$ insert into public.inventory_movements
         (id, arena_id, product_id, type, quantity, actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, 'opening', 1, %L, current_date) $$,
    :'arena_a', 'b0000000-0000-4000-8000-000000000009', :'user_a_owner'
  ),
  '23503',
  null,
  'inventory_movements.product_id cannot reference another arena''s product (assertion 5)'
);

select throws_ok(
  format(
    $$ insert into public.inventory_movements
         (id, arena_id, product_id, type, quantity, order_id, order_item_id,
          actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, 'sale', -1, %L, %L, %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-000000000009',
    'a0000000-0000-4000-8000-00000000000d', 'b0000000-0000-4000-8000-00000000000e',
    :'user_a_owner'
  ),
  '23503',
  null,
  'inventory_movements.order_item_id cannot reference another arena''s order line (assertion 5)'
);

select throws_ok(
  format(
    $$ insert into public.payments
         (id, arena_id, order_id, shift_id, method, amount, actor_user_id, business_date)
       values (gen_random_uuid(), %L, %L, %L, 'cash', 10.00, %L, current_date) $$,
    :'arena_a', 'a0000000-0000-4000-8000-00000000000d',
    'b0000000-0000-4000-8000-00000000000b', :'user_a_owner'
  ),
  '23503',
  null,
  'a payment cannot be attributed to another arena''s shift (D08)'
);

select throws_ok(
  format(
    $$ update public.sessions set station_id = %L where id = %L $$,
    'b0000000-0000-4000-8000-0000000000e2', 'a0000000-0000-4000-8000-00000000000c'
  ),
  '23503',
  null,
  'a session cannot reference a station in another arena'
);

select throws_ok(
  format(
    $$ update public.order_items set order_id = %L where id = %L $$,
    'b0000000-0000-4000-8000-0000000000e4', 'a0000000-0000-4000-8000-00000000000e'
  ),
  '23503',
  null,
  'an order line cannot be moved onto another arena''s order'
);

select throws_ok(
  format(
    $$ update public.role_permissions set role_id =
         (select id from public.roles where arena_id = %L and code = 'owner')
        where ctid = (select ctid from public.role_permissions where arena_id = %L limit 1) $$,
    :'arena_b', :'arena_a'
  ),
  null,
  null,
  'a permission grant cannot be moved onto another tenant''s role (C11)'
);

select * from finish();
rollback;
