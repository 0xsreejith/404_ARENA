-- Migration: 20260804120000_epic3c_checkout_integrity.sql
-- Description: Epic 3C — Checkout Integrity. Replace hardcoded tax/receipts with
--              M1 algorithms (app.play_charge, app.compute_order_totals,
--              app.next_receipt_number). Align session pricing_snapshot to the
--              normative shape. Wire settle idempotency.
-- Authoritative Spec: docs/DATABASE.md §9–§10 · docs/CHECKOUT_RULES.md ·
--                     docs/DECISIONS.md D01, D11, D13, D16, D31, D32, D33
--                     IMPLEMENTATION_PLAN.md Epic 3C

-- ── 1. Tax payload helper (rate → compute_order_totals input) ─────────────────

create or replace function app.tax_input_from_rate(p_tax_rate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_rate       public.tax_rates;
  v_components jsonb := '[]'::jsonb;
  v_row        record;
begin
  if p_tax_rate_id is null then
    return jsonb_build_object(
      'percent', app.percent_text(0),
      'components', '[]'::jsonb
    );
  end if;

  select * into v_rate
    from public.tax_rates
   where id = p_tax_rate_id
     and deleted_at is null;

  if v_rate.id is null then
    return jsonb_build_object(
      'percent', app.percent_text(0),
      'components', '[]'::jsonb
    );
  end if;

  for v_row in
    select c.name, c.percent
      from public.tax_rate_components c
     where c.tax_rate_id = p_tax_rate_id
       and c.deleted_at is null
     order by c.sort_order, c.created_at
  loop
    v_components := v_components || jsonb_build_object(
      'name', v_row.name,
      'percent', app.percent_text(v_row.percent)
    );
  end loop;

  return jsonb_build_object(
    'rate_id', v_rate.id,
    'name', v_rate.name,
    'percent', app.percent_text(v_rate.percent),
    'components', v_components
  );
end;
$$;

comment on function app.tax_input_from_rate(uuid) is
  'Builds the tax object consumed by app.compute_order_totals from a live '
  'tax_rates row and its components. Percentages are data (D31/D33).';

-- ── 2. Normalize any snapshot shape → M1 play_charge ─────────────────────────

create or replace function app.normalize_pricing_snapshot(p_pricing_snapshot jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, app
as $$
declare
  v_type text;
  v_rate text;
begin
  if p_pricing_snapshot is null then
    raise exception 'validation_failed: pricing_snapshot is required'
      using errcode = 'P0001';
  end if;

  -- Already normative (DATABASE.md §9 / session fixtures).
  if p_pricing_snapshot ? 'billing_plan' then
    return p_pricing_snapshot;
  end if;

  -- Epic 2 flat shape: plan_type / rate / duration_minutes.
  v_type := coalesce(p_pricing_snapshot->>'plan_type', p_pricing_snapshot->>'type');
  v_rate := coalesce(p_pricing_snapshot->>'rate', p_pricing_snapshot->>'hourly_rate',
                     p_pricing_snapshot->>'fixed_price');

  if v_type = 'open_time' then
    return jsonb_build_object(
      'schema_version', 1,
      'billing_plan', jsonb_build_object(
        'type', 'open_time',
        'hourly_rate', coalesce(v_rate, '0.00')
      ),
      'billing_policy', jsonb_build_object(
        'grace_minutes',
          coalesce((p_pricing_snapshot->>'grace_minutes')::int, 0),
        'minimum_billable_minutes',
          coalesce((p_pricing_snapshot->>'minimum_billable_minutes')::int, 0),
        'rounding_increment_minutes',
          coalesce((p_pricing_snapshot->>'rounding_increment_minutes')::int, 1),
        'rounding_mode',
          coalesce(p_pricing_snapshot->>'rounding_mode', 'up')
      )
    );
  elsif v_type = 'fixed_duration' then
    return jsonb_build_object(
      'schema_version', 1,
      'billing_plan', jsonb_build_object(
        'type', 'fixed_duration',
        'duration_minutes',
          coalesce((p_pricing_snapshot->>'duration_minutes')::int, 60),
        'fixed_price', coalesce(v_rate, '0.00')
      ),
      'billing_policy', jsonb_build_object(
        'grace_minutes',
          coalesce((p_pricing_snapshot->>'grace_minutes')::int, 0)
      )
    );
  end if;

  raise exception 'validation_failed: unknown pricing_snapshot shape'
    using errcode = 'P0001';
end;
$$;

create or replace function app.compute_play_charge(
  p_started_at           timestamptz,
  p_ended_at             timestamptz,
  p_total_paused_seconds int,
  p_pricing_snapshot     jsonb
)
returns numeric(12,2)
language plpgsql
immutable
set search_path = pg_catalog, app
as $$
declare
  v_elapsed bigint;
  v_snap    jsonb;
begin
  v_elapsed := greatest(
    0,
    extract(epoch from (coalesce(p_ended_at, now()) - p_started_at))::bigint
      - coalesce(p_total_paused_seconds, 0)
  );
  v_snap := app.normalize_pricing_snapshot(p_pricing_snapshot);
  return app.play_charge(v_snap, v_elapsed)::numeric(12,2);
end;
$$;

comment on function app.compute_play_charge(timestamptz, timestamptz, int, jsonb) is
  'Thin adapter over app.play_charge. Accepts Epic 2 flat snapshots and the '
  'normative nested snapshot; never embeds rates (D11, D33).';

-- ── 3. session_start — write normative pricing_snapshot ──────────────────────

create or replace function public.session_start(
  p_arena_id         uuid,
  p_session_id       uuid,
  p_station_id       uuid,
  p_billing_plan_id  uuid,
  p_member_id        uuid default null,
  p_game_id          uuid default null,
  p_player_count     int default 1,
  p_client_at        timestamptz default now(),
  p_idempotency_key  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_station            record;
  v_plan               record;
  v_live_count         int;
  v_pricing_snapshot   jsonb;
  v_started_at         timestamptz;
  v_planned_end_at     timestamptz;
  v_business_date      date;
  v_current_shift_id   uuid;
  v_replay             jsonb;
  v_fingerprint        text;
  v_response           jsonb;
begin
  perform app.require_permission(p_arena_id, 'session.start');

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    v_fingerprint := md5(
      p_session_id::text || p_station_id::text || p_billing_plan_id::text
      || coalesce(p_member_id::text, '') || coalesce(p_game_id::text, '')
      || coalesce(p_player_count::text, '1')
    );
    v_replay := app.claim_idempotency(
      p_arena_id, p_idempotency_key, 'session_start', v_fingerprint
    );
    if v_replay is not null then
      return v_replay;
    end if;
  end if;

  select * into v_station
    from public.stations
   where id = p_station_id and arena_id = p_arena_id and deleted_at is null;

  if v_station.id is null then
    raise exception 'not_found: station %', p_station_id using errcode = 'P0001';
  end if;

  if v_station.status <> 'active' then
    raise exception 'invalid_state: station is %', v_station.status
      using errcode = 'P0001';
  end if;

  select count(*) into v_live_count
    from public.sessions
   where station_id = p_station_id
     and arena_id = p_arena_id
     and status in ('active', 'paused');

  if v_live_count > 0 then
    raise exception 'conflict: station already has a live session'
      using errcode = 'P0001';
  end if;

  select * into v_plan
    from public.billing_plans
   where id = p_billing_plan_id and arena_id = p_arena_id and deleted_at is null;

  if v_plan.id is null then
    raise exception 'not_found: billing plan %', p_billing_plan_id
      using errcode = 'P0001';
  end if;

  if v_plan.type = 'open_time' then
    v_pricing_snapshot := jsonb_build_object(
      'schema_version', 1,
      'plan_id', v_plan.id,
      'plan_name', v_plan.name,
      'billing_plan', jsonb_build_object(
        'type', 'open_time',
        'hourly_rate', app.money_text(v_plan.hourly_rate)
      ),
      'billing_policy', jsonb_build_object(
        'grace_minutes', v_plan.grace_minutes,
        'minimum_billable_minutes', v_plan.minimum_billable_minutes,
        'rounding_increment_minutes', v_plan.rounding_increment_minutes,
        'rounding_mode', v_plan.rounding_mode
      )
    );
  else
    v_pricing_snapshot := jsonb_build_object(
      'schema_version', 1,
      'plan_id', v_plan.id,
      'plan_name', v_plan.name,
      'billing_plan', jsonb_build_object(
        'type', 'fixed_duration',
        'duration_minutes', v_plan.duration_minutes,
        'fixed_price', app.money_text(v_plan.fixed_price)
      ),
      'billing_policy', jsonb_build_object(
        'grace_minutes', v_plan.grace_minutes
      )
    );
  end if;

  v_started_at := coalesce(p_client_at, now());

  if v_plan.type = 'fixed_duration' then
    v_planned_end_at := v_started_at + (v_plan.duration_minutes * interval '1 minute');
  else
    v_planned_end_at := null;
  end if;

  v_business_date := app.business_date(p_arena_id, v_started_at);
  v_current_shift_id := app.current_shift_id(p_arena_id);

  insert into public.sessions (
    id, arena_id, station_id, member_id, game_id, billing_plan_id,
    opened_in_shift_id, status, player_count, started_by_user_id, started_at,
    planned_end_at, pricing_snapshot, client_created_at, business_date
  )
  values (
    p_session_id, p_arena_id, p_station_id, p_member_id, p_game_id, p_billing_plan_id,
    v_current_shift_id, 'active', p_player_count, app.current_actor_id(), v_started_at,
    v_planned_end_at, v_pricing_snapshot, p_client_at, v_business_date
  );

  perform app.audit(
    p_arena_id,
    'session.started',
    'session',
    p_session_id,
    jsonb_build_object('station_id', p_station_id, 'plan_type', v_plan.type)
  );

  v_response := jsonb_build_object(
    'id', p_session_id,
    'status', 'active',
    'started_at', v_started_at,
    'planned_end_at', v_planned_end_at,
    'pricing_snapshot', v_pricing_snapshot
  );

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
  end if;

  return v_response;
end;
$$;

-- ── 4. checkout_open — play line + arena default tax ─────────────────────────

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
  v_session         record;
  v_business_date   date;
  v_play_amount     numeric(12,2);
  v_order_item_id   uuid;
  v_tax_rate_id     uuid;
  v_tax_input       jsonb;
  v_settings        record;
  v_member_id       uuid := p_member_id;
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  if exists (select 1 from public.orders where id = p_order_id and arena_id = p_arena_id) then
    return jsonb_build_object('id', p_order_id, 'status',
      (select status from public.orders where id = p_order_id and arena_id = p_arena_id));
  end if;

  select * into v_settings
    from public.arena_settings
   where arena_id = p_arena_id;

  if v_settings.arena_id is null then
    raise exception 'not_found: arena % has no settings', p_arena_id
      using errcode = 'P0001';
  end if;

  v_business_date := app.business_date(p_arena_id, now());

  if p_session_id is not null then
    select * into v_session
      from public.sessions
     where id = p_session_id and arena_id = p_arena_id;

    if v_session.id is null then
      raise exception 'not_found: session %', p_session_id using errcode = 'P0001';
    end if;

    if v_session.status not in ('completed', 'active', 'paused') then
      raise exception 'invalid_state: cannot checkout session in state %', v_session.status
        using errcode = 'P0001';
    end if;

    if exists (
      select 1 from public.orders o
       where o.session_id = p_session_id
         and o.arena_id = p_arena_id
         and o.status <> 'void'
    ) then
      raise exception 'conflict: session already has a non-void order'
        using errcode = 'P0001';
    end if;

    if v_member_id is null then
      v_member_id := v_session.member_id;
    end if;
  end if;

  insert into public.orders (
    id, arena_id, session_id, member_id, status, opened_by_user_id, business_date
  )
  values (
    p_order_id, p_arena_id, p_session_id, v_member_id, 'open',
    app.current_actor_id(), v_business_date
  );

  if p_session_id is not null then
    v_play_amount := app.compute_play_charge(
      v_session.started_at,
      v_session.ended_at,
      v_session.total_paused_seconds,
      v_session.pricing_snapshot
    );

    v_tax_rate_id := v_settings.default_play_tax_rate_id;
    v_tax_input := app.tax_input_from_rate(v_tax_rate_id);
    v_order_item_id := gen_random_uuid();

    insert into public.order_items (
      id, arena_id, order_id, type, session_id, name_snapshot, quantity, unit_price,
      line_subtotal, taxable_amount, tax_amount, line_total,
      tax_rate_id, tax_rate_snapshot
    )
    values (
      v_order_item_id, p_arena_id, p_order_id, 'play', p_session_id,
      coalesce(v_session.pricing_snapshot->>'plan_name', 'Session Play Charge'),
      1, v_play_amount,
      v_play_amount, v_play_amount, 0.00, v_play_amount,
      v_tax_rate_id,
      jsonb_build_object(
        'schema_version', 1,
        'rate_id', v_tax_input->>'rate_id',
        'name', v_tax_input->>'name',
        'percent', v_tax_input->>'percent',
        'inclusive', v_settings.prices_include_tax,
        'components', coalesce(v_tax_input->'components', '[]'::jsonb)
      )
    );
  end if;

  perform app.audit(
    p_arena_id, 'order.created', 'order', p_order_id,
    jsonb_build_object('session_id', p_session_id)
  );

  return jsonb_build_object('id', p_order_id, 'status', 'open');
end;
$$;

-- ── 5. order_add_product — attach product tax rate ───────────────────────────

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
  v_tax_input    jsonb;
  v_inclusive    boolean;
begin
  perform app.require_permission(p_arena_id, 'inventory.sell');

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'validation_failed: quantity must be positive'
      using errcode = 'P0001';
  end if;

  select status into v_order_status
    from public.orders
   where id = p_order_id and arena_id = p_arena_id;

  if v_order_status is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  if v_order_status != 'open' then
    raise exception 'invalid_state: cannot modify % order', v_order_status
      using errcode = 'P0001';
  end if;

  select * into v_product
    from public.products
   where id = p_product_id and arena_id = p_arena_id and deleted_at is null;

  if v_product.id is null then
    raise exception 'not_found: product %', p_product_id using errcode = 'P0001';
  end if;

  select s.prices_include_tax into v_inclusive
    from public.arena_settings s
   where s.arena_id = p_arena_id;

  v_line_sub := round(p_quantity * v_product.selling_price, 2);
  v_tax_input := app.tax_input_from_rate(v_product.tax_rate_id);

  insert into public.order_items (
    id, arena_id, order_id, type, product_id, name_snapshot, quantity, unit_price,
    line_subtotal, taxable_amount, tax_amount, line_total,
    tax_rate_id, tax_rate_snapshot
  )
  values (
    p_order_item_id, p_arena_id, p_order_id, 'product', p_product_id, v_product.name,
    p_quantity, v_product.selling_price,
    v_line_sub, v_line_sub, 0.00, v_line_sub,
    v_product.tax_rate_id,
    jsonb_build_object(
      'schema_version', 1,
      'rate_id', v_tax_input->>'rate_id',
      'name', v_tax_input->>'name',
      'percent', v_tax_input->>'percent',
      'inclusive', coalesce(v_inclusive, true),
      'components', coalesce(v_tax_input->'components', '[]'::jsonb)
    )
  );

  return jsonb_build_object('id', p_order_item_id, 'order_id', p_order_id);
end;
$$;

-- ── 6. order_preview — app.compute_order_totals only ─────────────────────────

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
  v_order       record;
  v_inclusive   boolean;
  v_lines_in    jsonb := '[]'::jsonb;
  v_item        record;
  v_tax_input   jsonb;
  v_computed    jsonb;
  v_out_lines   jsonb := '[]'::jsonb;
  v_comp_line   jsonb;
  v_idx         int := 0;
  v_item_ids    uuid[] := array[]::uuid[];
  v_item_names  text[] := array[]::text[];
  v_item_qtys   numeric[] := array[]::numeric[];
  v_item_prices numeric[] := array[]::numeric[];
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  select * into v_order
    from public.orders
   where id = p_order_id and arena_id = p_arena_id;

  if v_order.id is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  select s.prices_include_tax into v_inclusive
    from public.arena_settings s
   where s.arena_id = p_arena_id;

  for v_item in
    select *
      from public.order_items
     where order_id = p_order_id and arena_id = p_arena_id
     order by sort_order, created_at
  loop
    v_idx := v_idx + 1;
    v_item_ids[v_idx] := v_item.id;
    v_item_names[v_idx] := v_item.name_snapshot;
    v_item_qtys[v_idx] := v_item.quantity;
    v_item_prices[v_idx] := v_item.unit_price;

    if v_item.tax_rate_id is not null then
      v_tax_input := app.tax_input_from_rate(v_item.tax_rate_id);
    elsif v_item.tax_rate_snapshot is not null
          and v_item.tax_rate_snapshot ? 'percent' then
      v_tax_input := jsonb_build_object(
        'rate_id', v_item.tax_rate_snapshot->>'rate_id',
        'name', v_item.tax_rate_snapshot->>'name',
        'percent', v_item.tax_rate_snapshot->>'percent',
        'components', coalesce(v_item.tax_rate_snapshot->'components', '[]'::jsonb)
      );
    else
      v_tax_input := jsonb_build_object(
        'percent', app.percent_text(0),
        'components', '[]'::jsonb
      );
    end if;

    v_lines_in := v_lines_in || jsonb_build_object(
      'quantity', to_char(v_item.quantity, 'FM999999990.000'),
      'unit_price', app.money_text(v_item.unit_price),
      'tax', v_tax_input
    );
  end loop;

  v_computed := app.compute_order_totals(
    v_lines_in,
    coalesce(v_inclusive, true),
    v_order.discount_kind,
    v_order.discount_value
  );

  for v_idx in 1 .. coalesce(array_length(v_item_ids, 1), 0) loop
    v_comp_line := v_computed->'lines'->(v_idx - 1);
    v_out_lines := v_out_lines || jsonb_build_object(
      'id', v_item_ids[v_idx],
      'name', v_item_names[v_idx],
      'quantity', v_item_qtys[v_idx],
      'unit_price', v_item_prices[v_idx],
      'line_subtotal', (v_comp_line->>'line_subtotal')::numeric,
      'discount_amount', (v_comp_line->>'discount_amount')::numeric,
      'taxable_amount', (v_comp_line->>'taxable_amount')::numeric,
      'tax_amount', (v_comp_line->>'tax_amount')::numeric,
      'line_total', (v_comp_line->>'line_total')::numeric,
      'tax_rate_snapshot', v_comp_line->'tax_rate_snapshot'
    );
  end loop;

  return jsonb_build_object(
    'order_id', p_order_id,
    'status', v_order.status,
    'prices_include_tax', coalesce(v_inclusive, true),
    'subtotal', (v_computed->>'subtotal')::numeric,
    'discount_kind', v_order.discount_kind,
    'discount_value', v_order.discount_value,
    'discount_total', (v_computed->>'discount_total')::numeric,
    'tax_total', (v_computed->>'tax_total')::numeric,
    'total', (v_computed->>'total')::numeric,
    'paid_total', v_order.paid_total,
    'balance_due', (v_computed->>'total')::numeric - v_order.paid_total,
    'items', v_out_lines
  );
end;
$$;

-- ── 7. order_settle — receipt helpers + idempotency + persist line tax ───────

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
  v_receipt        record;
  v_item           jsonb;
  v_new_paid_total numeric(12,2);
  v_total          numeric(12,2);
  v_replay         jsonb;
  v_fingerprint    text;
  v_response       jsonb;
  v_status         text;
  v_line           jsonb;
  v_i              int;
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    v_fingerprint := md5(
      p_order_id::text || p_payment_id::text || p_payment_method
      || app.money_text(p_amount) || coalesce(p_reference, '')
    );
    v_replay := app.claim_idempotency(
      p_arena_id, p_idempotency_key, 'order_settle', v_fingerprint
    );
    if v_replay is not null then
      return v_replay;
    end if;
  end if;

  if p_payment_method not in ('cash', 'card', 'upi') then
    raise exception 'validation_failed: invalid payment method %', p_payment_method
      using errcode = 'P0001';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'validation_failed: payment amount must be positive'
      using errcode = 'P0001';
  end if;

  select * into v_order
    from public.orders
   where id = p_order_id and arena_id = p_arena_id;

  if v_order.id is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  if v_order.status = 'settled' then
    v_response := jsonb_build_object(
      'id', p_order_id,
      'status', 'settled',
      'receipt_number', v_order.receipt_number,
      'paid_total', v_order.paid_total
    );
    if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
      perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
    end if;
    return v_response;
  end if;

  if v_order.status = 'void' then
    raise exception 'invalid_state: cannot settle voided order'
      using errcode = 'P0001';
  end if;

  v_shift_id := app.current_shift_id(p_arena_id);
  if v_shift_id is null then
    raise exception 'invalid_state: an open shift is required for cash reconciliation'
      using errcode = 'P0001';
  end if;

  insert into public.payments (
    id, arena_id, order_id, shift_id, method, amount, reference,
    actor_user_id, business_date
  )
  values (
    p_payment_id, p_arena_id, p_order_id, v_shift_id, p_payment_method, p_amount,
    p_reference, app.current_actor_id(), v_order.business_date
  );

  v_preview := public.order_preview(p_arena_id, p_order_id);
  v_new_paid_total := (v_preview->>'paid_total')::numeric;
  v_total := (v_preview->>'total')::numeric;
  v_status := 'open';

  if v_new_paid_total >= v_total then
    select * into v_receipt
      from app.next_receipt_number(p_arena_id, v_order.business_date);

    update public.orders
       set status = 'settled',
           subtotal = (v_preview->>'subtotal')::numeric,
           discount_total = (v_preview->>'discount_total')::numeric,
           tax_total = (v_preview->>'tax_total')::numeric,
           total = v_total,
           receipt_sequence = v_receipt.sequence_number,
           receipt_number = v_receipt.formatted_number,
           settled_by_user_id = app.current_actor_id(),
           settled_at = now()
     where id = p_order_id and arena_id = p_arena_id;

    for v_i in 0 .. greatest(jsonb_array_length(coalesce(v_preview->'items', '[]'::jsonb)) - 1, -1)
    loop
      v_line := v_preview->'items'->v_i;
      update public.order_items
         set taxable_amount = (v_line->>'taxable_amount')::numeric,
             tax_amount = (v_line->>'tax_amount')::numeric,
             line_total = (v_line->>'line_total')::numeric,
             tax_rate_snapshot = coalesce(
               v_line->'tax_rate_snapshot', tax_rate_snapshot
             )
       where id = (v_line->>'id')::uuid
         and arena_id = p_arena_id
         and order_id = p_order_id;
    end loop;

    insert into public.inventory_movements (
      id, arena_id, product_id, type, quantity, order_id, order_item_id,
      actor_user_id, business_date
    )
    select gen_random_uuid(), p_arena_id, oi.product_id, 'sale', -oi.quantity,
           p_order_id, oi.id, app.current_actor_id(), v_order.business_date
      from public.order_items oi
     where oi.order_id = p_order_id
       and oi.arena_id = p_arena_id
       and oi.type = 'product';

    perform app.audit(
      p_arena_id, 'order.settled', 'order', p_order_id,
      jsonb_build_object(
        'receipt_number', v_receipt.formatted_number,
        'total', app.money_text(v_total)
      )
    );

    v_status := 'settled';
    v_response := jsonb_build_object(
      'id', p_order_id,
      'status', 'settled',
      'receipt_number', v_receipt.formatted_number,
      'paid_total', v_new_paid_total
    );
  else
    v_response := jsonb_build_object(
      'id', p_order_id,
      'status', 'open',
      'receipt_number', null,
      'paid_total', v_new_paid_total
    );
  end if;

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
  end if;

  return v_response;
end;
$$;
