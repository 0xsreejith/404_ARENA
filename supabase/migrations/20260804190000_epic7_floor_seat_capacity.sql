-- Migration: 20260804190000_epic7_floor_seat_capacity.sql
-- Description: Epic 7 — expose stations.seat_capacity on floor_snapshot for
--              Lobby station cards (HTML seat row parity).
-- Authoritative Spec: IMPLEMENTATION_PLAN Epic 7 · UI_SPEC station cards

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
      'status_reason', s.status_reason,
      'seat_capacity', s.seat_capacity
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
  'Floor grid payload including seat_capacity for Lobby station cards '
  '(API.md §3 · Epic 7).';
