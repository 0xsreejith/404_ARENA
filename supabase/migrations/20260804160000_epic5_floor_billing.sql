-- Migration: 20260804160000_epic5_floor_billing.sql
-- Description: Epic 5 — unbilled queue semantics (API.md §4), money_text wire
--              format on order_preview (D01), public.unbilled_sessions RPC.
-- Authoritative Spec: docs/API.md §4–§5 · IMPLEMENTATION_PLAN Epic 5 · D01

-- ── 1. floor_snapshot — only unbilled semantics change; rest matches Epic 2 ──

create or replace function public.floor_snapshot(p_arena_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_zones             jsonb;
  v_station_types     jsonb;
  v_stations          jsonb;
  v_games             jsonb;
  v_billing_plans     jsonb;
  v_live_sessions     jsonb;
  v_unbilled_sessions jsonb;
begin
  perform app.require_permission(p_arena_id, 'station.view');

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', z.id,
      'name', z.name,
      'sort_order', z.sort_order
    ) order by z.sort_order, z.name
  ), '[]'::jsonb)
  into v_zones
  from public.zones z
  where z.arena_id = p_arena_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', st.id,
      'name', st.name,
      'icon', null,
      'hourly_rate', 0
    ) order by st.name
  ), '[]'::jsonb)
  into v_station_types
  from public.station_types st
  where st.arena_id = p_arena_id and st.deleted_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'name', s.name,
      'zone_id', s.zone_id,
      'station_type_id', s.station_type_id,
      'status', s.status,
      'status_reason', s.status_reason
    ) order by s.name
  ), '[]'::jsonb)
  into v_stations
  from public.stations s
  where s.arena_id = p_arena_id and s.deleted_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', g.id,
      'title', g.title,
      'cover_url', null
    ) order by g.title
  ), '[]'::jsonb)
  into v_games
  from public.games g
  where g.arena_id = p_arena_id and g.deleted_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', bp.id,
      'name', bp.name,
      'type', bp.type,
      'duration_minutes', bp.duration_minutes,
      'price', coalesce(bp.fixed_price, bp.hourly_rate),
      'station_type_id', bp.station_type_id
    ) order by bp.name
  ), '[]'::jsonb)
  into v_billing_plans
  from public.billing_plans bp
  where bp.arena_id = p_arena_id and bp.deleted_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ss.id,
      'station_id', ss.station_id,
      'member_id', ss.member_id,
      'member_name', m.full_name,
      'game_id', ss.game_id,
      'game_title', g.title,
      'billing_plan_id', ss.billing_plan_id,
      'status', ss.status,
      'player_count', ss.player_count,
      'started_at', ss.started_at,
      'planned_end_at', ss.planned_end_at,
      'paused_at', ss.paused_at,
      'total_paused_seconds', ss.total_paused_seconds,
      'pricing_snapshot', ss.pricing_snapshot
    ) order by ss.started_at
  ), '[]'::jsonb)
  into v_live_sessions
  from public.sessions ss
  left join public.members m on m.id = ss.member_id and m.arena_id = ss.arena_id
  left join public.games g on g.id = ss.game_id and g.arena_id = ss.arena_id
  where ss.arena_id = p_arena_id and ss.status in ('active', 'paused');

  -- Completed sessions with no settled order (open / void / absent still unbilled).
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ss.id,
      'station_id', ss.station_id,
      'station_name', stn.name,
      'member_name', m.full_name,
      'started_at', ss.started_at,
      'ended_at', ss.ended_at,
      'status', ss.status,
      'open_order_id', open_ord.id
    ) order by ss.ended_at desc
  ), '[]'::jsonb)
  into v_unbilled_sessions
  from public.sessions ss
  join public.stations stn on stn.id = ss.station_id and stn.arena_id = ss.arena_id
  left join public.members m on m.id = ss.member_id and m.arena_id = ss.arena_id
  left join lateral (
    select o.id
      from public.orders o
     where o.session_id = ss.id
       and o.arena_id = ss.arena_id
       and o.status = 'open'
     order by o.created_at desc
     limit 1
  ) open_ord on true
  where ss.arena_id = p_arena_id
    and ss.status = 'completed'
    and not exists (
      select 1
        from public.orders settled
       where settled.session_id = ss.id
         and settled.arena_id = ss.arena_id
         and settled.status = 'settled'
    );

  return jsonb_build_object(
    'zones', v_zones,
    'station_types', v_station_types,
    'stations', v_stations,
    'games', v_games,
    'billing_plans', v_billing_plans,
    'live_sessions', v_live_sessions,
    'unbilled_sessions', v_unbilled_sessions
  );
end;
$$;

comment on function public.floor_snapshot(uuid) is
  'Returns zones, stations, games, billing plans, live sessions and unbilled '
  'sessions (completed without settled order) for the floor grid (API.md §3–§4).';

-- ── 2. Dedicated unbilled_sessions RPC (API.md §4) ───────────────────────────

create or replace function public.unbilled_sessions(p_arena_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_rows jsonb;
begin
  perform app.require_permission(p_arena_id, 'session.view');

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ss.id,
      'station_id', ss.station_id,
      'station_name', stn.name,
      'member_id', ss.member_id,
      'member_name', m.full_name,
      'started_at', ss.started_at,
      'ended_at', ss.ended_at,
      'status', ss.status,
      'open_order_id', open_ord.id
    ) order by ss.ended_at desc
  ), '[]'::jsonb)
  into v_rows
  from public.sessions ss
  join public.stations stn on stn.id = ss.station_id and stn.arena_id = ss.arena_id
  left join public.members m on m.id = ss.member_id and m.arena_id = ss.arena_id
  left join lateral (
    select o.id
      from public.orders o
     where o.session_id = ss.id
       and o.arena_id = ss.arena_id
       and o.status = 'open'
     order by o.created_at desc
     limit 1
  ) open_ord on true
  where ss.arena_id = p_arena_id
    and ss.status = 'completed'
    and not exists (
      select 1
        from public.orders settled
       where settled.session_id = ss.id
         and settled.arena_id = ss.arena_id
         and settled.status = 'settled'
    );

  return jsonb_build_object('sessions', v_rows);
end;
$$;

comment on function public.unbilled_sessions(uuid) is
  'Completed sessions with no settled order — abandoned open/void still appear (API.md §4).';

grant execute on function public.unbilled_sessions(uuid) to authenticated;

-- ── 3. order_preview — money crosses the wire as decimal strings (D01) ───────

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
  v_balance     numeric(12,2);
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
      'quantity', to_char(v_item_qtys[v_idx], 'FM999999990.000'),
      'unit_price', app.money_text(v_item_prices[v_idx]),
      'line_subtotal', v_comp_line->>'line_subtotal',
      'discount_amount', v_comp_line->>'discount_amount',
      'taxable_amount', v_comp_line->>'taxable_amount',
      'tax_amount', v_comp_line->>'tax_amount',
      'line_total', v_comp_line->>'line_total',
      'tax_rate_snapshot', v_comp_line->'tax_rate_snapshot'
    );
  end loop;

  v_balance := (v_computed->>'total')::numeric - v_order.paid_total;

  return jsonb_build_object(
    'order_id', p_order_id,
    'status', v_order.status,
    'prices_include_tax', coalesce(v_inclusive, true),
    'subtotal', v_computed->>'subtotal',
    'discount_kind', v_order.discount_kind,
    'discount_value', case
      when v_order.discount_kind = 'percent' then app.percent_text(v_order.discount_value)
      when v_order.discount_value is null then null
      else app.money_text(v_order.discount_value)
    end,
    'discount_total', v_computed->>'discount_total',
    'tax_total', v_computed->>'tax_total',
    'total', v_computed->>'total',
    'paid_total', app.money_text(v_order.paid_total),
    'balance_due', app.money_text(v_balance),
    'items', v_out_lines
  );
end;
$$;

comment on function public.order_preview(uuid, uuid) is
  'Authoritative checkout preview. Money fields are decimal strings (D01/D05).';
