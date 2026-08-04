-- Migration: 20260804180000_epic6_shift_cash.sql
-- Description: Epic 6 — production shift/cash RPCs (API.md §6).
-- Authoritative Spec: docs/API.md §6 · docs/DECISIONS.md D08, D29, D30

-- ── 1. public.shift_current(p_arena_id uuid) ─────────────────────────────────

create or replace function public.shift_current(p_arena_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_shift record;
begin
  perform app.require_permission(p_arena_id, 'shift.view');

  select *
    into v_shift
    from public.shifts s
   where s.arena_id = p_arena_id
     and s.status = 'open';

  if v_shift.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_shift.id,
    'arena_id', v_shift.arena_id,
    'business_date', v_shift.business_date,
    'status', v_shift.status,
    'opened_by_user_id', v_shift.opened_by_user_id,
    'opened_at', v_shift.opened_at,
    'opening_float', app.money_text(v_shift.opening_float),
    'closed_by_user_id', v_shift.closed_by_user_id,
    'closed_at', v_shift.closed_at,
    'expected_cash', case
      when v_shift.expected_cash is null then null
      else app.money_text(v_shift.expected_cash)
    end,
    'counted_cash', case
      when v_shift.counted_cash is null then null
      else app.money_text(v_shift.counted_cash)
    end,
    'variance', case
      when v_shift.variance is null then null
      else app.money_text(v_shift.variance)
    end,
    'notes', v_shift.notes
  );
end;
$$;

comment on function public.shift_current(uuid) is
  'Returns the open shift for an arena, or null (API.md §6).';

grant execute on function public.shift_current(uuid) to authenticated;

-- ── 2. public.shift_open(...) ─────────────────────────────────────────────────

create or replace function public.shift_open(
  p_arena_id         uuid,
  p_shift_id         uuid,
  p_opening_float    numeric,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_replay      jsonb;
  v_fingerprint text;
  v_response    jsonb;
begin
  perform app.require_permission(p_arena_id, 'shift.open');

  if p_shift_id is null then
    raise exception 'validation_failed: shift id is required'
      using errcode = 'P0001';
  end if;

  if p_opening_float is null or p_opening_float < 0 then
    raise exception 'validation_failed: opening float must be zero or greater'
      using errcode = 'P0001';
  end if;

  v_fingerprint := md5(p_shift_id::text || app.money_text(p_opening_float));
  v_replay := app.claim_idempotency(
    p_arena_id, p_idempotency_key, 'shift_open', v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  if app.current_shift_id(p_arena_id) is not null then
    raise exception 'invalid_state: a shift is already open (D30)'
      using errcode = 'P0001';
  end if;

  insert into public.shifts (
    id, arena_id, business_date, status, opened_by_user_id, opened_at, opening_float
  )
  values (
    p_shift_id, p_arena_id, app.business_date(p_arena_id, now()), 'open',
    app.current_actor_id(), now(), p_opening_float
  );

  perform app.audit(
    p_arena_id, 'shift.opened', 'shift', p_shift_id,
    jsonb_build_object('opening_float', app.money_text(p_opening_float))
  );

  select jsonb_build_object(
    'id', s.id,
    'arena_id', s.arena_id,
    'business_date', s.business_date,
    'status', s.status,
    'opened_by_user_id', s.opened_by_user_id,
    'opened_at', s.opened_at,
    'opening_float', app.money_text(s.opening_float),
    'closed_by_user_id', s.closed_by_user_id,
    'closed_at', s.closed_at,
    'expected_cash', null,
    'counted_cash', null,
    'variance', null,
    'notes', s.notes
  )
    into v_response
    from public.shifts s
   where s.id = p_shift_id
     and s.arena_id = p_arena_id;

  perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
  return v_response;
end;
$$;

comment on function public.shift_open(uuid, uuid, numeric, text) is
  'Opens one shift per arena with an opening float; rejects an existing open shift (D30).';

grant execute on function public.shift_open(uuid, uuid, numeric, text) to authenticated;

-- ── 3. public.shift_summary(p_arena_id uuid, p_shift_id uuid) ────────────────

create or replace function public.shift_summary(p_arena_id uuid, p_shift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_shift                 record;
  v_order_count           int;
  v_session_count         int;
  v_sales_play            numeric(12,2);
  v_sales_product         numeric(12,2);
  v_discount_total        numeric(12,2);
  v_tax_total             numeric(12,2);
  v_payments_by_method    jsonb;
  v_cash_payments         numeric(12,2);
  v_unbilled_sessions     int;
begin
  perform app.require_permission(p_arena_id, 'shift.view');

  select *
    into v_shift
    from public.shifts s
   where s.id = p_shift_id
     and s.arena_id = p_arena_id;

  if v_shift.id is null then
    raise exception 'not_found: shift %', p_shift_id
      using errcode = 'P0001';
  end if;

  with shift_orders as (
    select distinct p.order_id
      from public.payments p
     where p.arena_id = p_arena_id
       and p.shift_id = p_shift_id
  )
  select count(*),
         count(o.session_id),
         coalesce(sum(o.discount_total), 0),
         coalesce(sum(o.tax_total), 0)
    into v_order_count, v_session_count, v_discount_total, v_tax_total
    from shift_orders so
    join public.orders o
      on o.id = so.order_id
     and o.arena_id = p_arena_id;

  with shift_orders as (
    select distinct p.order_id
      from public.payments p
     where p.arena_id = p_arena_id
       and p.shift_id = p_shift_id
  )
  select coalesce(sum(oi.line_total) filter (where oi.type = 'play'), 0),
         coalesce(sum(oi.line_total) filter (where oi.type = 'product'), 0)
    into v_sales_play, v_sales_product
    from shift_orders so
    join public.order_items oi
      on oi.order_id = so.order_id
     and oi.arena_id = p_arena_id;

  select coalesce(jsonb_object_agg(method, app.money_text(total) order by method), '{}'::jsonb)
    into v_payments_by_method
    from (
      select p.method, sum(p.amount)::numeric(12,2) as total
        from public.payments p
       where p.arena_id = p_arena_id
         and p.shift_id = p_shift_id
       group by p.method
    ) payments;

  select coalesce(sum(p.amount), 0)
    into v_cash_payments
    from public.payments p
   where p.arena_id = p_arena_id
     and p.shift_id = p_shift_id
     and p.method = 'cash';

  select count(*)
    into v_unbilled_sessions
    from public.sessions ss
   where ss.arena_id = p_arena_id
     and ss.opened_in_shift_id = p_shift_id
     and ss.status = 'completed'
     and not exists (
       select 1
         from public.orders settled
        where settled.session_id = ss.id
          and settled.arena_id = ss.arena_id
          and settled.status = 'settled'
     );

  return jsonb_build_object(
    'shift_id', v_shift.id,
    'status', v_shift.status,
    'business_date', v_shift.business_date,
    'opened_at', v_shift.opened_at,
    'closed_at', v_shift.closed_at,
    'opening_float', app.money_text(v_shift.opening_float),
    'order_count', coalesce(v_order_count, 0),
    'session_count', coalesce(v_session_count, 0),
    'sales', jsonb_build_object(
      'play', app.money_text(coalesce(v_sales_play, 0)),
      'product', app.money_text(coalesce(v_sales_product, 0))
    ),
    'discount_total', app.money_text(coalesce(v_discount_total, 0)),
    'tax_total', app.money_text(coalesce(v_tax_total, 0)),
    'payments_by_method', coalesce(v_payments_by_method, '{}'::jsonb),
    'cash_payments', app.money_text(coalesce(v_cash_payments, 0)),
    'expected_cash', app.money_text(v_shift.opening_float + coalesce(v_cash_payments, 0)),
    'unbilled_session_count', coalesce(v_unbilled_sessions, 0)
  );
end;
$$;

comment on function public.shift_summary(uuid, uuid) is
  'Summarises a shift from payments.shift_id and computes expected cash (D08).';

grant execute on function public.shift_summary(uuid, uuid) to authenticated;

-- ── 4. public.shift_close(...) ────────────────────────────────────────────────

create or replace function public.shift_close(
  p_arena_id         uuid,
  p_shift_id         uuid,
  p_counted_cash     numeric,
  p_notes            text,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_shift        record;
  v_replay       jsonb;
  v_fingerprint  text;
  v_cash_payments numeric(12,2);
  v_expected_cash numeric(12,2);
  v_variance      numeric(12,2);
  v_response      jsonb;
begin
  perform app.require_permission(p_arena_id, 'shift.close');

  if p_counted_cash is null or p_counted_cash < 0 then
    raise exception 'validation_failed: counted cash must be zero or greater'
      using errcode = 'P0001';
  end if;

  v_fingerprint := md5(
    p_shift_id::text || app.money_text(p_counted_cash) || coalesce(p_notes, '')
  );
  v_replay := app.claim_idempotency(
    p_arena_id, p_idempotency_key, 'shift_close', v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select *
    into v_shift
    from public.shifts s
   where s.id = p_shift_id
     and s.arena_id = p_arena_id
   for update;

  if v_shift.id is null then
    raise exception 'not_found: shift %', p_shift_id
      using errcode = 'P0001';
  end if;

  if v_shift.status <> 'open' then
    raise exception 'invalid_state: shift % is already closed', p_shift_id
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
      from public.orders o
     where o.arena_id = p_arena_id
       and o.status = 'open'
  ) then
    raise exception 'invalid_state: close or void open orders before closing shift'
      using errcode = 'P0001';
  end if;

  select coalesce(sum(p.amount), 0)
    into v_cash_payments
    from public.payments p
   where p.arena_id = p_arena_id
     and p.shift_id = p_shift_id
     and p.method = 'cash';

  v_expected_cash := v_shift.opening_float + coalesce(v_cash_payments, 0);
  v_variance := p_counted_cash - v_expected_cash;

  if v_variance <> 0 and btrim(coalesce(p_notes, '')) = '' then
    raise exception 'validation_failed: notes are required when cash variance is non-zero (D29)'
      using errcode = 'P0001';
  end if;

  update public.shifts
     set status = 'closed',
         closed_by_user_id = app.current_actor_id(),
         closed_at = now(),
         expected_cash = v_expected_cash,
         counted_cash = p_counted_cash,
         notes = nullif(btrim(coalesce(p_notes, '')), '')
   where id = p_shift_id
     and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'shift.closed', 'shift', p_shift_id,
    jsonb_build_object(
      'expected_cash', app.money_text(v_expected_cash),
      'counted_cash', app.money_text(p_counted_cash),
      'variance', app.money_text(v_variance)
    )
  );

  select jsonb_build_object(
    'id', s.id,
    'arena_id', s.arena_id,
    'business_date', s.business_date,
    'status', s.status,
    'opened_by_user_id', s.opened_by_user_id,
    'opened_at', s.opened_at,
    'opening_float', app.money_text(s.opening_float),
    'closed_by_user_id', s.closed_by_user_id,
    'closed_at', s.closed_at,
    'expected_cash', app.money_text(s.expected_cash),
    'counted_cash', app.money_text(s.counted_cash),
    'variance', app.money_text(s.variance),
    'notes', s.notes
  )
    into v_response
    from public.shifts s
   where s.id = p_shift_id
     and s.arena_id = p_arena_id;

  perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
  return v_response;
end;
$$;

comment on function public.shift_close(uuid, uuid, numeric, text, text) is
  'Closes an open shift after open orders are cleared; variance requires notes (D29).';

grant execute on function public.shift_close(uuid, uuid, numeric, text, text) to authenticated;
