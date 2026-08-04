-- M1 — append-only and immutable records.
--
-- The append-only triggers reject UPDATE and DELETE for EVERY role, including
-- the migration role and service_role. That is deliberately stronger than
-- revoking privileges, because it also protects against a mistake inside a
-- SECURITY DEFINER function (SECURITY.md §10).
--
-- Covers SECURITY.md §15 assertions 12 and 13.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(12);

create function pg_temp.append_only_survivors(p_arena_id uuid)
returns table (relation text, operation text)
language plpgsql
as $probe$
declare
  v_table text;
  v_op    text;
begin
  foreach v_table in array array['payments', 'inventory_movements', 'audit_logs'] loop
    foreach v_op in array array['update', 'delete'] loop
      begin
        if v_op = 'update' then
          execute format(
            'update public.%I set business_date = business_date + 1 where arena_id = $1', v_table
          ) using p_arena_id;
        else
          execute format('delete from public.%I where arena_id = $1', v_table)
            using p_arena_id;
        end if;

        -- Reaching here means the row changed. Raise so the subtransaction
        -- rolls back either way, then report it.
        raise exception 'append_only_violated' using errcode = 'P0001';
      exception
        when others then
          if sqlerrm like 'append_only_violated%' then
            relation := v_table;
            operation := v_op;
            return next;
          end if;
      end;
    end loop;
  end loop;
end;
$probe$;

-- ── As the migration role (the RPC definer) ──────────────────────────────────

select is_empty(
  format(
    $$ select relation || ' / ' || operation from pg_temp.append_only_survivors(%L) $$,
    :'arena_a'
  ),
  'payments, inventory_movements and audit_logs reject UPDATE and DELETE for the definer role'
);

-- ── As service_role, which bypasses RLS entirely ─────────────────────────────

set local role service_role;

select is_empty(
  format(
    $$ select relation || ' / ' || operation from pg_temp.append_only_survivors(%L) $$,
    :'arena_a'
  ),
  'the same three tables reject UPDATE and DELETE for service_role too (assertion 12)'
);

reset role;

-- ── As an authenticated client, the privilege layer refuses first ────────────

select pg_temp.become(:'user_a_owner');
set local role authenticated;

select throws_ok(
  format($$ delete from public.payments where arena_id = %L $$, :'arena_a'),
  '42501',
  null,
  'an authenticated client cannot even attempt to delete a payment'
);

reset role;

-- ── Business date is immutable once written (D09) ────────────────────────────

select throws_ok(
  format(
    $$ update public.shifts set business_date = business_date + 1 where arena_id = %L $$,
    :'arena_a'
  ),
  'P0001',
  null,
  'shifts.business_date cannot be moved after insert'
);

select throws_ok(
  format(
    $$ update public.sessions set business_date = business_date + 1 where arena_id = %L $$,
    :'arena_a'
  ),
  'P0001',
  null,
  'sessions.business_date cannot be moved after insert'
);

select throws_ok(
  format(
    $$ update public.orders set business_date = business_date + 1 where arena_id = %L $$,
    :'arena_a'
  ),
  'P0001',
  null,
  'orders.business_date cannot be moved after insert'
);

-- ── A settled order is immutable except for paid_total ───────────────────────

insert into public.orders
  (id, arena_id, status, subtotal, tax_total, total, paid_total,
   receipt_number, receipt_sequence, settled_by_user_id, settled_at,
   opened_by_user_id, business_date)
values ('a0000000-0000-4000-8000-0000000000e1', :'arena_a', 'settled',
        0, 0, 0, 0, 'TEST/000001', 1, :'user_a_owner', now(),
        :'user_a_owner', app.business_date(:'arena_a', now()));

select throws_ok(
  $$ update public.orders set status = 'open'
      where id = 'a0000000-0000-4000-8000-0000000000e1' $$,
  'P0001',
  null,
  'no path transitions an order out of settled (assertion 13)'
);

select throws_ok(
  $$ update public.orders set receipt_number = 'TEST/000002'
      where id = 'a0000000-0000-4000-8000-0000000000e1' $$,
  'P0001',
  null,
  'orders.receipt_number cannot be changed once assigned (assertion 13)'
);

select throws_ok(
  $$ update public.orders set receipt_sequence = 99
      where id = 'a0000000-0000-4000-8000-0000000000e1' $$,
  'P0001',
  null,
  'orders.receipt_sequence cannot be changed once assigned'
);

select throws_ok(
  $$ update public.orders set total = 999
      where id = 'a0000000-0000-4000-8000-0000000000e1' $$,
  'P0001',
  null,
  'a settled order''s money cannot be edited (D21)'
);

select lives_ok(
  $$ update public.orders set paid_total = 0
      where id = 'a0000000-0000-4000-8000-0000000000e1' $$,
  'paid_total is the one column that may change on a settled order — it is '
  'trigger-maintained from payments (D21)'
);

-- ── A closed shift is immutable ──────────────────────────────────────────────

update public.shifts
   set status = 'closed', closed_by_user_id = :'user_a_owner', closed_at = now(),
       expected_cash = 100.00, counted_cash = 100.00
 where id = 'a0000000-0000-4000-8000-00000000000b';

select throws_ok(
  $$ update public.shifts set notes = 'after the fact'
      where id = 'a0000000-0000-4000-8000-00000000000b' $$,
  'P0001',
  null,
  'a closed shift is a financial record and does not move afterwards'
);

select * from finish();
rollback;
