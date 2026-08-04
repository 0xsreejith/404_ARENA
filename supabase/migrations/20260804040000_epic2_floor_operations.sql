-- Migration: 20260804040000_epic2_floor_operations.sql
-- Description: Epic 2 — Floor Operations RPCs (floor_snapshot, session_start, session_pause, session_resume, session_stop, station_set_status).
-- Authoritative Spec: docs/API.md §3, §4 · docs/DECISIONS.md D06, D10, D11

-- ── 1. public.floor_snapshot(p_arena_id uuid) ─────────────────────────────────

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

  -- Zones
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

  -- Station Types
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

  -- Stations
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

  -- Games
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

  -- Billing Plans
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

  -- Live Sessions (active or paused)
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

  -- Unbilled Completed Sessions
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ss.id,
      'station_id', ss.station_id,
      'station_name', stn.name,
      'member_name', m.full_name,
      'started_at', ss.started_at,
      'ended_at', ss.ended_at,
      'status', ss.status
    ) order by ss.ended_at desc
  ), '[]'::jsonb)
  into v_unbilled_sessions
  from public.sessions ss
  join public.stations stn on stn.id = ss.station_id and stn.arena_id = ss.arena_id
  left join public.members m on m.id = ss.member_id and m.arena_id = ss.arena_id
  left join public.orders o on o.session_id = ss.id and o.arena_id = ss.arena_id
  where ss.arena_id = p_arena_id and ss.status = 'completed' and o.id is null;

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
  'Returns zones, stations, games, billing plans, live sessions and unbilled sessions for the floor grid (API.md §3).';

grant execute on function public.floor_snapshot(uuid) to authenticated;

-- ── 2. public.session_start ───────────────────────────────────────────────────

create or replace function public.session_start(
  p_arena_id        uuid,
  p_session_id      uuid,
  p_station_id      uuid,
  p_billing_plan_id uuid,
  p_member_id       uuid default null,
  p_game_id         uuid default null,
  p_player_count    int default 1,
  p_client_at       timestamptz default now(),
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_station_status   text;
  v_plan             record;
  v_started_at       timestamptz;
  v_planned_end_at   timestamptz;
  v_pricing_snapshot jsonb;
  v_business_date    date;
  v_current_shift_id uuid;
  v_session          jsonb;
begin
  perform app.require_permission(p_arena_id, 'session.start');

  -- 1. Validate station availability
  select status into v_station_status
  from public.stations
  where id = p_station_id and arena_id = p_arena_id and deleted_at is null;

  if v_station_status is null then
    raise exception 'not_found: station %', p_station_id using errcode = 'P0001';
  end if;

  if v_station_status != 'active' then
    raise exception 'invalid_state: station is %', v_station_status using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.sessions
    where station_id = p_station_id and arena_id = p_arena_id and status in ('active', 'paused')
  ) then
    raise exception 'conflict: station already has a live session' using errcode = 'P0001';
  end if;

  -- 2. Fetch billing plan
  select * into v_plan
  from public.billing_plans
  where id = p_billing_plan_id and arena_id = p_arena_id and deleted_at is null;

  if v_plan.id is null then
    raise exception 'not_found: billing plan %', p_billing_plan_id using errcode = 'P0001';
  end if;

  -- 3. Pricing snapshot
  v_pricing_snapshot := jsonb_build_object(
    'plan_id', v_plan.id,
    'plan_name', v_plan.name,
    'plan_type', v_plan.type,
    'rate', coalesce(v_plan.fixed_price, v_plan.hourly_rate),
    'duration_minutes', v_plan.duration_minutes
  );

  v_started_at := coalesce(p_client_at, now());

  if v_plan.type = 'fixed_duration' then
    v_planned_end_at := v_started_at + (v_plan.duration_minutes * interval '1 minute');
  else
    v_planned_end_at := null;
  end if;

  v_business_date := app.business_date(p_arena_id, v_started_at);
  v_current_shift_id := app.current_shift_id(p_arena_id);

  -- 4. Create Session
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

  select jsonb_build_object(
    'id', p_session_id,
    'station_id', p_station_id,
    'status', 'active',
    'started_at', v_started_at,
    'planned_end_at', v_planned_end_at
  ) into v_session;

  return v_session;
end;
$$;

grant execute on function public.session_start to authenticated;

-- ── 3. public.session_pause ───────────────────────────────────────────────────

create or replace function public.session_pause(
  p_arena_id        uuid,
  p_session_id      uuid,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_status text;
begin
  perform app.require_permission(p_arena_id, 'session.pause');

  select status into v_status
  from public.sessions
  where id = p_session_id and arena_id = p_arena_id;

  if v_status is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0001';
  end if;

  if v_status != 'active' then
    raise exception 'invalid_state: cannot pause session with status %', v_status using errcode = 'P0001';
  end if;

  update public.sessions
  set status = 'paused', paused_at = now()
  where id = p_session_id and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'session.paused', 'session', p_session_id, jsonb_build_object('paused_at', now())
  );

  return jsonb_build_object('id', p_session_id, 'status', 'paused');
end;
$$;

grant execute on function public.session_pause to authenticated;

-- ── 4. public.session_resume ──────────────────────────────────────────────────

create or replace function public.session_resume(
  p_arena_id        uuid,
  p_session_id      uuid,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_session record;
  v_pause_seconds int;
begin
  perform app.require_permission(p_arena_id, 'session.resume');

  select * into v_session
  from public.sessions
  where id = p_session_id and arena_id = p_arena_id;

  if v_session.id is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0001';
  end if;

  if v_session.status != 'paused' then
    raise exception 'invalid_state: cannot resume session with status %', v_session.status using errcode = 'P0001';
  end if;

  v_pause_seconds := greatest(0, extract(epoch from (now() - v_session.paused_at))::int);

  update public.sessions
  set status = 'active',
      paused_at = null,
      total_paused_seconds = total_paused_seconds + v_pause_seconds,
      planned_end_at = case
        when planned_end_at is not null then planned_end_at + (v_pause_seconds * interval '1 second')
        else null
      end
  where id = p_session_id and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'session.resumed', 'session', p_session_id, jsonb_build_object('pause_seconds', v_pause_seconds)
  );

  return jsonb_build_object('id', p_session_id, 'status', 'active');
end;
$$;

grant execute on function public.session_resume to authenticated;

-- ── 5. public.session_stop ────────────────────────────────────────────────────

create or replace function public.session_stop(
  p_arena_id        uuid,
  p_session_id      uuid,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_status text;
begin
  perform app.require_permission(p_arena_id, 'session.stop');

  select status into v_status
  from public.sessions
  where id = p_session_id and arena_id = p_arena_id;

  if v_status is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0001';
  end if;

  if v_status not in ('active', 'paused') then
    raise exception 'invalid_state: cannot stop session in state %', v_status using errcode = 'P0001';
  end if;

  update public.sessions
  set status = 'completed',
      ended_at = now(),
      ended_by_user_id = app.current_actor_id(),
      end_reason = 'normal'
  where id = p_session_id and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'session.stopped', 'session', p_session_id, jsonb_build_object('ended_at', now())
  );

  return jsonb_build_object('id', p_session_id, 'status', 'completed');
end;
$$;

grant execute on function public.session_stop to authenticated;

-- ── 6. public.station_set_status ──────────────────────────────────────────────

create or replace function public.station_set_status(
  p_arena_id   uuid,
  p_station_id uuid,
  p_status     text,
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'station.maintenance');

  if p_status not in ('active', 'maintenance', 'inactive') then
    raise exception 'validation_failed: status % is invalid', p_status using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.sessions
    where station_id = p_station_id and arena_id = p_arena_id and status in ('active', 'paused')
  ) then
    raise exception 'conflict: station has an active session' using errcode = 'P0001';
  end if;

  update public.stations
  set status = p_status,
      status_reason = p_reason
  where id = p_station_id and arena_id = p_arena_id;

  perform app.audit(
    p_arena_id, 'station.status_changed', 'station', p_station_id, jsonb_build_object('status', p_status, 'reason', p_reason)
  );

  return jsonb_build_object('id', p_station_id, 'status', p_status);
end;
$$;

grant execute on function public.station_set_status to authenticated;
