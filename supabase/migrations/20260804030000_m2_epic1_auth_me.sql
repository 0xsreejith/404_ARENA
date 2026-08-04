-- Migration: 20260804030000_m2_epic1_auth_me.sql
-- Description: Epic 1 — Authentication, User Context resolution (me() RPC), Branding columns, and Device Telemetry.
-- Authoritative Spec: docs/API.md §2, docs/SECURITY.md §3, §4

-- ── 1. Branding columns on arena_settings ────────────────────────────────────
-- Every branding setting is tenant configuration, stored in DB (no hardcoded colors/logos).

alter table public.arena_settings
  add column if not exists brand_name    text null,
  add column if not exists logo_url      text null,
  add column if not exists primary_color text not null default '#7CFF4F',
  add column if not exists accent_color  text not null default '#00F0FF';

comment on column public.arena_settings.brand_name is
  'Tenant display name override. Null defaults to public.arenas.name.';
comment on column public.arena_settings.primary_color is
  'Hex color code for tenant main accent UI elements.';
comment on column public.arena_settings.accent_color is
  'Hex color code for secondary UI highlights and glows.';

-- ── 2. public.me() RPC ───────────────────────────────────────────────────────
-- Resolves actor profile, accessible arenas/branches, role info, branding, and permission codes array.
-- Governed by API.md §2 and SECURITY.md §3.

create or replace function public.me()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_actor_id uuid;
  v_user     jsonb;
  v_arenas   jsonb;
begin
  v_actor_id := app.current_actor_id();

  if v_actor_id is null then
    raise exception 'insufficient_privilege: not authenticated'
      using errcode = 'insufficient_privilege';
  end if;

  -- 1. Actor Profile
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'phone', p.phone
  )
  into v_user
  from public.profiles p
  where p.id = v_actor_id;

  if v_user is null then
    raise exception 'not_found: user profile does not exist'
      using errcode = 'P0001';
  end if;

  -- 2. Accessible Arenas/Branches & Permissions
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', a.id,
      'name', a.name,
      'timezone', a.timezone,
      'currency', a.currency,
      'branding', jsonb_build_object(
        'brand_name', coalesce(s.brand_name, a.name),
        'logo_url', s.logo_url,
        'primary_color', s.primary_color,
        'accent_color', s.accent_color
      ),
      'role', jsonb_build_object(
        'code', r.code,
        'name', r.name
      ),
      'permissions', (
        select coalesce(jsonb_agg(rp.permission_code order by rp.permission_code), '[]'::jsonb)
        from public.role_permissions rp
        where rp.role_id = r.id and rp.arena_id = a.id
      )
    ) order by a.name
  ), '[]'::jsonb)
  into v_arenas
  from public.arena_users au
  join public.arenas a on a.id = au.arena_id
  join public.arena_settings s on s.arena_id = a.id
  join public.roles r on r.id = au.role_id and r.arena_id = a.id
  where au.user_id = v_actor_id
    and au.active = true
    and a.active = true
    and r.deleted_at is null;

  return jsonb_build_object(
    'user', v_user,
    'arenas', v_arenas
  );
end;
$$;

comment on function public.me() is
  'Resolves current authenticated staff profile and accessible arena contexts with permission sets (API.md §2).';

grant execute on function public.me() to authenticated;

-- ── 3. public.register_device() RPC ──────────────────────────────────────────
-- Telemetry only. Upserts client device information (API.md §2).

create or replace function public.register_device(
  p_arena_id    uuid,
  p_device_id   uuid,
  p_name        text,
  p_platform    text,
  p_app_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'station.view');

  if p_platform not in ('android', 'ios', 'web', 'desktop') then
    raise exception 'validation_failed: invalid platform %', p_platform
      using errcode = 'P0001';
  end if;

  insert into public.devices (
    id, arena_id, name, platform, app_version, registered_by_user_id, last_seen_at, active
  )
  values (
    p_device_id, p_arena_id, p_name, p_platform, p_app_version, app.current_actor_id(), now(), true
  )
  on conflict (id) do update set
    arena_id = excluded.arena_id,
    name = excluded.name,
    app_version = excluded.app_version,
    last_seen_at = now();

  return jsonb_build_object('success', true, 'device_id', p_device_id);
end;
$$;

comment on function public.register_device(uuid, uuid, text, text, text) is
  'Registers client device hardware details for telemetry (API.md §2).';

grant execute on function public.register_device(uuid, uuid, text, text, text) to authenticated;
