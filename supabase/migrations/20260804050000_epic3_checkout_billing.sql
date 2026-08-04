-- Migration: 20260804050000_epic3_checkout_billing.sql
-- Description: Epic 3 — Checkout & Billing RPCs (order_preview, checkout_open, order_add_product, order_apply_discount, order_settle, order_void).
-- Authoritative Spec: docs/DATABASE.md §9, §10 · docs/API.md §5 · docs/DECISIONS.md D01, D07, D08, D11, D12, D31, D32

-- ── 1. Helper function to compute play charge ─────────────────────────────────

create or replace function app.compute_play_charge(
  p_started_at           timestamptz,
  p_ended_at             timestamptz,
  p_total_paused_seconds int,
  p_pricing_snapshot     jsonb
)
returns numeric(12,2)
language plpgsql
immutable
as $$
declare
  v_elapsed_seconds int;
  v_elapsed_minutes int;
  v_plan_type       text;
  v_grace_minutes   int;
  v_rate            numeric(12,2);
  v_duration_min    int;
  v_min_billable    int;
  v_round_inc       int;
  v_round_mode      text;
  v_billable_min    int;
  v_overrun         int;
  v_blocks          int;
  v_amount          numeric(12,2);
begin
  v_elapsed_seconds := greatest(0, extract(epoch from (coalesce(p_ended_at, now()) - p_started_at))::int - coalesce(p_total_paused_seconds, 0));
  v_elapsed_minutes := ceil(v_elapsed_seconds / 60.0)::int;

  v_plan_type     := p_pricing_snapshot->'billing_plan'->>'type';
  v_grace_minutes := coalesce((p_pricing_snapshot->'billing_policy'->>'grace_minutes')::int, 0);

  if v_elapsed_minutes <= v_grace_minutes then
    return 0.00;
  end if;

  if v_plan_type = 'open_time' then
    v_rate         := coalesce((p_pricing_snapshot->'billing_plan'->>'hourly_rate')::numeric, (p_pricing_snapshot->'billing_plan'->>'rate')::numeric, 0.00);
    v_min_billable := coalesce((p_pricing_snapshot->'billing_policy'->>'minimum_billable_minutes')::int, 0);
    v_round_inc    := coalesce((p_pricing_snapshot->'billing_policy'->>'rounding_increment_minutes')::int, 1);
    v_round_mode   := coalesce(p_pricing_snapshot->'billing_policy'->>'rounding_mode', 'up');

    v_billable_min := greatest(v_elapsed_minutes, v_min_billable);
    if v_round_inc > 1 then
      if v_round_mode = 'up' then
        v_billable_min := ceil(v_billable_min::numeric / v_round_inc)::int * v_round_inc;
      end if;
    end if;

    v_amount := round((v_rate * v_billable_min::numeric / 60.0), 2);
  else
    -- fixed_duration
    v_rate         := coalesce((p_pricing_snapshot->'billing_plan'->>'fixed_price')::numeric, (p_pricing_snapshot->'billing_plan'->>'rate')::numeric, 0.00);
    v_duration_min := coalesce((p_pricing_snapshot->'billing_plan'->>'duration_minutes')::int, 60);

    v_overrun := greatest(0, v_elapsed_minutes - v_duration_min - v_grace_minutes);
    v_blocks  := 1 + ceil(v_overrun::numeric / v_duration_min)::int;

    v_amount  := round((v_rate * v_blocks::numeric), 2);
  end if;

  return v_amount;
end;
$$;

-- ── 2. public.checkout_open ───────────────────────────────────────────────────

create or replace function public.checkout_open(
  p_arena_id   uuid,
  p_order_id   uuid,
  p_session_id uuid default null,
  p_member_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_session       record;
  v_business_date date;
  v_play_amount   numeric(12,2);
  v_order_item_id uuid;
  v_tax_rate_id   uuid;
  v_tax_snapshot  jsonb;
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  if exists (select 1 from public.orders where id = p_order_id and arena_id = p_arena_id) then
    return jsonb_build_object('id', p_order_id, 'status', 'open');
  end if;

  v_business_date := app.business_date(p_arena_id, now());

  insert into public.orders (
    id, arena_id, session_id, member_id, status, opened_by_user_id, business_date
  )
  values (
    p_order_id, p_arena_id, p_session_id, p_member_id, 'open', app.current_actor_id(), v_business_date
  );

  -- If tied to session, add play charge line item
  if p_session_id is not null then
    select * into v_session from public.sessions where id = p_session_id and arena_id = p_arena_id;
    if v_session.id is not null then
      v_play_amount := app.compute_play_charge(
        v_session.started_at, v_session.ended_at, v_session.total_paused_seconds, v_session.pricing_snapshot
      );

      v_order_item_id := gen_random_uuid();
      v_tax_rate_id   := null;
      v_tax_snapshot  := jsonb_build_object('inclusive', true, 'components', jsonb_build_array());

      insert into public.order_items (
        id, arena_id, order_id, type, session_id, name_snapshot, quantity, unit_price,
        line_subtotal, taxable_amount, tax_amount, line_total, tax_rate_snapshot
      )
      values (
        v_order_item_id, p_arena_id, p_order_id, 'play', p_session_id, 'Session Play Charge', 1, v_play_amount,
        v_play_amount, v_play_amount, 0.00, v_play_amount, v_tax_snapshot
      );
    end if;
  end if;

  perform app.audit(
    p_arena_id, 'order.created', 'order', p_order_id, jsonb_build_object('session_id', p_session_id)
  );

  return jsonb_build_object('id', p_order_id, 'status', 'open');
end;
$$;

grant execute on function public.checkout_open to authenticated;

-- ── 3. public.order_add_product ───────────────────────────────────────────────

create or replace function public.order_add_product(
  p_arena_id      uuid,
  p_order_id      uuid,
  p_order_item_id uuid,
  p_product_id    uuid,
  p_quantity      numeric
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_order_status text;
  v_product      record;
  v_line_sub     numeric(12,2);
  v_tax_snapshot jsonb;
begin
  perform app.require_permission(p_arena_id, 'inventory.sell');

  select status into v_order_status
  from public.orders
  where id = p_order_id and arena_id = p_arena_id;

  if v_order_status is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  if v_order_status != 'open' then
    raise exception 'invalid_state: cannot modify % order', v_order_status using errcode = 'P0001';
  end if;

  select * into v_product
  from public.products
  where id = p_product_id and arena_id = p_arena_id and deleted_at is null;

  if v_product.id is null then
    raise exception 'not_found: product %', p_product_id using errcode = 'P0001';
  end if;

  v_line_sub := round(p_quantity * v_product.selling_price, 2);
  v_tax_snapshot := jsonb_build_object('inclusive', true, 'components', jsonb_build_array());

  insert into public.order_items (
    id, arena_id, order_id, type, product_id, name_snapshot, quantity, unit_price,
    line_subtotal, taxable_amount, tax_amount, line_total, tax_rate_snapshot
  )
  values (
    p_order_item_id, p_arena_id, p_order_id, 'product', p_product_id, v_product.name, p_quantity, v_product.selling_price,
    v_line_sub, v_line_sub, 0.00, v_line_sub, v_tax_snapshot
  );

  return jsonb_build_object('id', p_order_item_id, 'order_id', p_order_id);
end;
$$;

grant execute on function public.order_add_product to authenticated;

-- ── 4. public.order_apply_discount ───────────────────────────────────────────

create or replace function public.order_apply_discount(
  p_arena_id       uuid,
  p_order_id       uuid,
  p_discount_kind  text,
  p_discount_value numeric,
  p_discount_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_order_status text;
begin
  perform app.require_permission(p_arena_id, 'discount.apply');

  if p_discount_reason is null or btrim(p_discount_reason) = '' then
    raise exception 'validation_failed: discount reason is required' using errcode = 'P0001';
  end if;

  if p_discount_kind not in ('flat', 'percent') then
    raise exception 'validation_failed: invalid discount kind %', p_discount_kind using errcode = 'P0001';
  end if;

  select status into v_order_status
  from public.orders
  where id = p_order_id and arena_id = p_arena_id;

  if v_order_status != 'open' then
    raise exception 'invalid_state: cannot apply discount to % order', v_order_status using errcode = 'P0001';
  end if;

  update public.orders
  set discount_kind = p_discount_kind,
      discount_value = p_discount_value,
      discount_reason = btrim(p_discount_reason),
      discount_authorised_by_user_id = app.current_actor_id()
  where id = p_order_id and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'discount.applied', 'order', p_order_id, jsonb_build_object('kind', p_discount_kind, 'value', p_discount_value)
  );

  return jsonb_build_object('id', p_order_id, 'discount_applied', true);
end;
$$;

grant execute on function public.order_apply_discount to authenticated;

-- ── 5. public.order_preview (STABLE calculation engine) ───────────────────────

create or replace function public.order_preview(
  p_arena_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_order         record;
  v_items         jsonb;
  v_subtotal      numeric(12,2) := 0.00;
  v_disc_total    numeric(12,2) := 0.00;
  v_tax_total     numeric(12,2) := 0.00;
  v_total         numeric(12,2) := 0.00;
  v_paid_total    numeric(12,2) := 0.00;
  v_balance_due   numeric(12,2) := 0.00;
  v_item          record;
  v_line_disc     numeric(12,2);
  v_net           numeric(12,2);
  v_taxable       numeric(12,2);
  v_tax           numeric(12,2);
  v_line_tot      numeric(12,2);
  v_items_array   jsonb := '[]'::jsonb;
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  select * into v_order from public.orders where id = p_order_id and arena_id = p_arena_id;
  if v_order.id is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  select coalesce(sum(line_subtotal), 0.00) into v_subtotal
  from public.order_items where order_id = p_order_id and arena_id = p_arena_id;

  if v_order.discount_kind = 'flat' then
    v_disc_total := least(v_order.discount_value, v_subtotal);
  elsif v_order.discount_kind = 'percent' then
    v_disc_total := round(v_subtotal * (v_order.discount_value / 100.0), 2);
  else
    v_disc_total := 0.00;
  end if;

  for v_item in (
    select * from public.order_items where order_id = p_order_id and arena_id = p_arena_id order by sort_order, created_at
  ) loop
    if v_subtotal > 0 then
      v_line_disc := round(v_disc_total * (v_item.line_subtotal / v_subtotal), 2);
    else
      v_line_disc := 0.00;
    end if;

    v_net := v_item.line_subtotal - v_line_disc;
    -- Tax inclusive pilot
    v_taxable  := round(v_net / 1.18, 2);
    v_tax      := v_net - v_taxable;
    v_line_tot := v_net;

    v_tax_total := v_tax_total + v_tax;

    v_items_array := v_items_array || jsonb_build_object(
      'id', v_item.id,
      'name', v_item.name_snapshot,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'line_subtotal', v_item.line_subtotal,
      'discount_amount', v_line_disc,
      'taxable_amount', v_taxable,
      'tax_amount', v_tax,
      'line_total', v_line_tot
    );
  end loop;

  v_total       := v_subtotal - v_disc_total;
  v_paid_total  := v_order.paid_total;
  v_balance_due := v_total - v_paid_total;

  return jsonb_build_object(
    'order_id', p_order_id,
    'status', v_order.status,
    'subtotal', v_subtotal,
    'discount_kind', v_order.discount_kind,
    'discount_value', v_order.discount_value,
    'discount_total', v_disc_total,
    'tax_total', v_tax_total,
    'total', v_total,
    'paid_total', v_paid_total,
    'balance_due', v_balance_due,
    'items', v_items_array
  );
end;
$$;

grant execute on function public.order_preview to authenticated;

-- ── 6. public.order_settle ────────────────────────────────────────────────────

create or replace function public.order_settle(
  p_arena_id        uuid,
  p_order_id        uuid,
  p_payment_id      uuid,
  p_payment_method  text,
  p_amount          numeric,
  p_reference       text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_order          record;
  v_shift_id       uuid;
  v_preview        jsonb;
  v_series         text;
  v_seq            bigint;
  v_receipt_num    text;
  v_item           record;
  v_new_paid_total numeric(12,2);
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  if p_payment_method not in ('cash', 'card', 'upi') then
    raise exception 'validation_failed: invalid payment method %', p_payment_method using errcode = 'P0001';
  end if;

  select * into v_order from public.orders where id = p_order_id and arena_id = p_arena_id;
  if v_order.id is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  if v_order.status = 'settled' then
    return jsonb_build_object('id', p_order_id, 'status', 'settled', 'receipt_number', v_order.receipt_number);
  end if;

  if v_order.status = 'void' then
    raise exception 'invalid_state: cannot settle voided order' using errcode = 'P0001';
  end if;

  v_shift_id := app.current_shift_id(p_arena_id);
  if v_shift_id is null then
    raise exception 'invalid_state: an open shift is required for cash reconciliation' using errcode = 'P0001';
  end if;

  -- 1. Insert Payment
  insert into public.payments (
    id, arena_id, order_id, shift_id, method, amount, reference, actor_user_id, business_date
  )
  values (
    p_payment_id, p_arena_id, p_order_id, v_shift_id, p_payment_method, p_amount, p_reference, app.current_actor_id(), v_order.business_date
  );

  v_preview := public.order_preview(p_arena_id, p_order_id);
  v_new_paid_total := (v_preview->>'paid_total')::numeric;

  -- 2. Check if fully paid -> Settle order & assign sequential receipt
  if v_new_paid_total >= (v_preview->>'total')::numeric then
    v_series := app.receipt_series(p_arena_id, v_order.business_date);

    insert into public.receipt_counters (arena_id, series, next_number)
    values (p_arena_id, v_series, 2)
    on conflict (arena_id, series) do update set
      next_number = public.receipt_counters.next_number + 1
    returning next_number - 1 into v_seq;

    v_receipt_num := format('FIX/%s/%s', v_series, lpad(v_seq::text, 6, '0'));

    update public.orders
    set status = 'settled',
        subtotal = (v_preview->>'subtotal')::numeric,
        discount_total = (v_preview->>'discount_total')::numeric,
        tax_total = (v_preview->>'tax_total')::numeric,
        total = (v_preview->>'total')::numeric,
        receipt_sequence = v_seq,
        receipt_number = v_receipt_num,
        settled_by_user_id = app.current_actor_id(),
        settled_at = now()
    where id = p_order_id and arena_id = p_arena_id;

    -- Generate product stock movements if items exist
    for v_item in (select * from public.order_items where order_id = p_order_id and type = 'product') loop
      insert into public.inventory_movements (
        id, arena_id, product_id, type, quantity, order_id, order_item_id, actor_user_id, business_date
      )
      values (
        gen_random_uuid(), p_arena_id, v_item.product_id, 'sale', -v_item.quantity, p_order_id, v_item.id, app.current_actor_id(), v_order.business_date
      );
    end loop;

    perform app.audit(
      p_arena_id, 'order.settled', 'order', p_order_id, jsonb_build_object('receipt_number', v_receipt_num, 'total', v_preview->>'total')
    );
  end if;

  return jsonb_build_object(
    'id', p_order_id,
    'status', case when v_new_paid_total >= (v_preview->>'total')::numeric then 'settled' else 'open' end,
    'receipt_number', v_receipt_num,
    'paid_total', v_new_paid_total
  );
end;
$$;

grant execute on function public.order_settle to authenticated;

-- ── 7. public.order_void ──────────────────────────────────────────────────────

create or replace function public.order_void(
  p_arena_id uuid,
  p_order_id uuid,
  p_reason   text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_order record;
begin
  perform app.require_permission(p_arena_id, 'order.void');

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'validation_failed: void reason is required' using errcode = 'P0001';
  end if;

  select * into v_order from public.orders where id = p_order_id and arena_id = p_arena_id;
  if v_order.id is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  if v_order.status != 'open' then
    raise exception 'invalid_state: cannot void % order', v_order.status using errcode = 'P0001';
  end if;

  update public.orders
  set status = 'void', void_reason = btrim(p_reason)
  where id = p_order_id and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'order.voided', 'order', p_order_id, jsonb_build_object('reason', p_reason)
  );

  return jsonb_build_object('id', p_order_id, 'status', 'void');
end;
$$;

grant execute on function public.order_void to authenticated;
