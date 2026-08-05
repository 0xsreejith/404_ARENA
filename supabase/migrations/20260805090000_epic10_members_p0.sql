-- Migration: 20260805090000_epic10_members_p0.sql
-- Description: Epic 10 / Wave A — member search/get/create/update/block RPCs (D19).
-- Spec: docs/API.md §6 · SECURITY.md §8 · D19 · D36

-- ── Helpers ──────────────────────────────────────────────────────────────────

create or replace function app.mask_phone(p_phone text)
returns text
language sql
immutable
as $$
  select case
    when p_phone is null or length(p_phone) < 4 then '****'
    else overlay(p_phone placing repeat('*', greatest(length(p_phone) - 4, 0)) from 1 for greatest(length(p_phone) - 4, 0))
  end;
$$;

comment on function app.mask_phone(text) is
  'Display helper for member_search — last 4 digits visible (D19).';

create or replace function app.member_to_json(p_member public.members)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_member.id,
    'arena_id', p_member.arena_id,
    'full_name', p_member.full_name,
    'phone', p_member.phone,
    'phone_masked', app.mask_phone(p_member.phone),
    'dob', p_member.dob,
    'blocked', p_member.blocked,
    'blocked_reason', p_member.blocked_reason,
    'notes', p_member.notes,
    'created_at', p_member.created_at,
    'updated_at', p_member.updated_at
  );
$$;

-- ── member_search ────────────────────────────────────────────────────────────

create or replace function public.member_search(
  p_arena_id uuid,
  p_query    text,
  p_limit    int default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions
as $$
declare
  v_q       text := btrim(coalesce(p_query, ''));
  v_limit   int := least(greatest(coalesce(p_limit, 20), 1), 20);
  v_phone   text;
  v_rows    jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  if length(v_q) < 3 then
    raise exception 'validation_failed: search query must be at least 3 characters'
      using errcode = 'P0001';
  end if;

  begin
    v_phone := app.normalise_phone(p_arena_id, v_q);
  exception
    when others then
      v_phone := null;
  end;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
    into v_rows
    from (
      select
        m.id,
        m.full_name,
        app.mask_phone(m.phone) as phone_masked,
        m.phone,
        m.blocked,
        m.blocked_reason,
        m.dob,
        m.updated_at
      from public.members m
      where m.arena_id = p_arena_id
        and m.deleted_at is null
        and (
          (v_phone is not null and m.phone = v_phone)
          or m.phone like '%' || regexp_replace(v_q, '[^0-9+]', '', 'g') || '%'
          or m.full_name ilike '%' || v_q || '%'
        )
      order by
        case when v_phone is not null and m.phone = v_phone then 0 else 1 end,
        m.full_name
      limit v_limit
    ) t;

  return jsonb_build_object('members', v_rows, 'query', v_q, 'limit', v_limit);
end;
$$;

comment on function public.member_search(uuid, text, int) is
  'RPC-only member search — min 3 chars, limit 20 (API.md §6, D19).';

grant execute on function public.member_search(uuid, text, int) to authenticated;

-- ── member_get ───────────────────────────────────────────────────────────────

create or replace function public.member_get(
  p_arena_id  uuid,
  p_member_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_member public.members;
  v_sessions jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  select * into v_member
    from public.members m
   where m.id = p_member_id
     and m.arena_id = p_arena_id
     and m.deleted_at is null;

  if v_member.id is null then
    raise exception 'not_found: member'
      using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(row_to_json(s)::jsonb order by s.started_at desc), '[]'::jsonb)
    into v_sessions
    from (
      select
        sess.id,
        sess.status,
        sess.started_at,
        sess.ended_at,
        st.name as station_name,
        g.title as game_title,
        sess.business_date
      from public.sessions sess
      left join public.stations st
        on st.id = sess.station_id and st.arena_id = sess.arena_id
      left join public.games g
        on g.id = sess.game_id and g.arena_id = sess.arena_id
      where sess.arena_id = p_arena_id
        and sess.member_id = p_member_id
      order by sess.started_at desc
      limit 10
    ) s;

  return app.member_to_json(v_member) || jsonb_build_object('recent_sessions', v_sessions);
end;
$$;

comment on function public.member_get(uuid, uuid) is
  'Full member record plus last 10 sessions (API.md §6).';

grant execute on function public.member_get(uuid, uuid) to authenticated;

-- ── member_create ────────────────────────────────────────────────────────────

create or replace function public.member_create(
  p_arena_id         uuid,
  p_member_id        uuid,
  p_full_name        text,
  p_phone            text,
  p_dob              date default null,
  p_notes            text default null,
  p_idempotency_key  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_actor       uuid := app.current_actor_id();
  v_phone       text;
  v_existing    uuid;
  v_member      public.members;
  v_fingerprint text;
  v_replay      jsonb;
  v_response    jsonb;
  v_key         text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
begin
  perform app.require_permission(p_arena_id, 'member.create');

  if p_member_id is null then
    raise exception 'validation_failed: member id is required'
      using errcode = 'P0001';
  end if;

  if p_full_name is null or length(btrim(p_full_name)) = 0 then
    raise exception 'validation_failed: full name is required'
      using errcode = 'P0001';
  end if;

  v_phone := app.normalise_phone(p_arena_id, p_phone);

  if v_key is not null then
    v_fingerprint := md5(p_member_id::text || v_phone || btrim(p_full_name));
    v_replay := app.claim_idempotency(p_arena_id, v_key, 'member_create', v_fingerprint);
    if v_replay is not null then
      return v_replay;
    end if;
  end if;

  select m.id into v_existing
    from public.members m
   where m.arena_id = p_arena_id
     and m.phone = v_phone
     and m.deleted_at is null;

  if v_existing is not null then
    raise exception 'conflict: member already exists with id %', v_existing
      using errcode = 'P0001';
  end if;

  insert into public.members (
    id, arena_id, full_name, phone, dob, notes, created_by_user_id
  ) values (
    p_member_id, p_arena_id, btrim(p_full_name), v_phone, p_dob,
    nullif(btrim(coalesce(p_notes, '')), ''), v_actor
  )
  returning * into v_member;

  perform app.audit(
    p_arena_id, 'member.created', 'member', p_member_id,
    jsonb_build_object('phone', v_phone, 'full_name', v_member.full_name)
  );

  v_response := app.member_to_json(v_member);

  if v_key is not null then
    perform app.complete_idempotency(p_arena_id, v_key, v_response);
  end if;

  return v_response;
end;
$$;

comment on function public.member_create(uuid, uuid, text, text, date, text, text) is
  'Create member with server-side E.164 phone normalisation (API.md §6, D36).';

grant execute on function public.member_create(uuid, uuid, text, text, date, text, text)
  to authenticated;

-- ── member_update ────────────────────────────────────────────────────────────

create or replace function public.member_update(
  p_arena_id  uuid,
  p_member_id uuid,
  p_full_name text default null,
  p_phone     text default null,
  p_dob       date default null,
  p_notes     text default null,
  p_clear_dob boolean default false,
  p_clear_notes boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_member   public.members;
  v_phone    text;
  v_existing uuid;
begin
  perform app.require_permission(p_arena_id, 'member.update');

  select * into v_member
    from public.members m
   where m.id = p_member_id
     and m.arena_id = p_arena_id
     and m.deleted_at is null
   for update;

  if v_member.id is null then
    raise exception 'not_found: member'
      using errcode = 'P0001';
  end if;

  if p_full_name is not null then
    if length(btrim(p_full_name)) = 0 then
      raise exception 'validation_failed: full name is required'
        using errcode = 'P0001';
    end if;
    v_member.full_name := btrim(p_full_name);
  end if;

  if p_phone is not null then
    v_phone := app.normalise_phone(p_arena_id, p_phone);
    select m.id into v_existing
      from public.members m
     where m.arena_id = p_arena_id
       and m.phone = v_phone
       and m.deleted_at is null
       and m.id <> p_member_id;
    if v_existing is not null then
      raise exception 'conflict: member already exists with id %', v_existing
        using errcode = 'P0001';
    end if;
    v_member.phone := v_phone;
  end if;

  if p_clear_dob then
    v_member.dob := null;
  elsif p_dob is not null then
    v_member.dob := p_dob;
  end if;

  if p_clear_notes then
    v_member.notes := null;
  elsif p_notes is not null then
    v_member.notes := nullif(btrim(p_notes), '');
  end if;

  update public.members m
     set full_name = v_member.full_name,
         phone = v_member.phone,
         dob = v_member.dob,
         notes = v_member.notes
   where m.id = p_member_id
     and m.arena_id = p_arena_id
  returning * into v_member;

  perform app.audit(
    p_arena_id, 'member.updated', 'member', p_member_id,
    jsonb_build_object('full_name', v_member.full_name, 'phone', v_member.phone)
  );

  return app.member_to_json(v_member);
end;
$$;

comment on function public.member_update(uuid, uuid, text, text, date, text, boolean, boolean) is
  'Update member identity fields (API.md §6).';

grant execute on function
  public.member_update(uuid, uuid, text, text, date, text, boolean, boolean)
  to authenticated;

-- ── member_set_blocked ───────────────────────────────────────────────────────

create or replace function public.member_set_blocked(
  p_arena_id  uuid,
  p_member_id uuid,
  p_blocked   boolean,
  p_reason    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_member public.members;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  perform app.require_permission(p_arena_id, 'member.block');

  if p_blocked is null then
    raise exception 'validation_failed: blocked flag is required'
      using errcode = 'P0001';
  end if;

  if p_blocked and v_reason is null then
    raise exception 'validation_failed: reason is required when blocking'
      using errcode = 'P0001';
  end if;

  update public.members m
     set blocked = p_blocked,
         blocked_reason = case when p_blocked then v_reason else null end
   where m.id = p_member_id
     and m.arena_id = p_arena_id
     and m.deleted_at is null
  returning * into v_member;

  if v_member.id is null then
    raise exception 'not_found: member'
      using errcode = 'P0001';
  end if;

  perform app.audit(
    p_arena_id,
    case when p_blocked then 'member.blocked' else 'member.unblocked' end,
    'member',
    p_member_id,
    jsonb_build_object('reason', v_member.blocked_reason)
  );

  return app.member_to_json(v_member);
end;
$$;

comment on function public.member_set_blocked(uuid, uuid, boolean, text) is
  'Block or unblock a member; reason required when blocking (API.md §6).';

grant execute on function public.member_set_blocked(uuid, uuid, boolean, text)
  to authenticated;
