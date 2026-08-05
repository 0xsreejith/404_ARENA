-- Migration: 20260805091000_epic10b_crm_depth.sql
-- Description: Wave B — member profiles, tags, notes, relationships, codes, stats + RPCs.
-- Spec: commercial DATABASE_SCHEMA §2.2 · D19 · D28a

-- ── Tables ───────────────────────────────────────────────────────────────────

create table public.member_profiles (
  member_id              uuid primary key,
  arena_id               uuid        not null,
  nickname               text        null,
  email                  text        null,
  whatsapp               text        null,
  gender                 text        null check (gender is null or gender in ('male', 'female', 'other', 'unspecified')),
  photo_path             text        null,
  preferred_branch_id    uuid        null,
  preferred_station_id   uuid        null,
  preferred_game_id      uuid        null,
  preferred_platform     text        null,
  skill_level            text        null check (skill_level is null or skill_level in ('casual', 'regular', 'competitive', 'pro')),
  marketing_consent      boolean     not null default false,
  referral_code          text        null,
  referred_by_member_id  uuid        null,
  emergency_contact      jsonb       null,
  guardian               jsonb       null,
  anniversary            date        null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (member_id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade,
  foreign key (referred_by_member_id, arena_id)
    references public.members (id, arena_id) on delete set null,
  foreign key (preferred_station_id, arena_id)
    references public.stations (id, arena_id) on delete set null,
  foreign key (preferred_game_id, arena_id)
    references public.games (id, arena_id) on delete set null
);

create index member_profiles_arena_idx on public.member_profiles (arena_id);
create index member_profiles_whatsapp_idx on public.member_profiles (arena_id, whatsapp)
  where whatsapp is not null;
create trigger member_profiles_touch_updated_at
  before update on public.member_profiles
  for each row execute function app.touch_updated_at();

create table public.member_tags (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null references public.arenas (id) on delete restrict,
  code       text        not null check (length(btrim(code)) > 0),
  label      text        not null check (length(btrim(label)) > 0),
  color      text        null,
  system     boolean     not null default false,
  created_at timestamptz not null default now(),
  unique (id, arena_id),
  unique (arena_id, code)
);

create table public.member_tag_assignments (
  arena_id   uuid        not null,
  member_id  uuid        not null,
  tag_id     uuid        not null,
  assigned_at timestamptz not null default now(),
  assigned_by_user_id uuid not null references public.profiles (id) on delete restrict,
  primary key (arena_id, member_id, tag_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade,
  foreign key (tag_id, arena_id)
    references public.member_tags (id, arena_id) on delete cascade
);

create table public.member_notes (
  id                 uuid primary key default gen_random_uuid(),
  arena_id           uuid        not null,
  member_id          uuid        not null,
  kind               text        not null check (kind in (
    'behaviour', 'damage', 'no_show', 'vip_pref', 'general'
  )),
  body               text        not null check (length(btrim(body)) > 0),
  created_by_user_id uuid        not null references public.profiles (id) on delete restrict,
  deleted_at         timestamptz null,
  created_at         timestamptz not null default now(),
  unique (id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade
);

create index member_notes_member_idx
  on public.member_notes (arena_id, member_id, created_at desc)
  where deleted_at is null;

create table public.member_relationships (
  id               uuid primary key default gen_random_uuid(),
  arena_id         uuid not null,
  parent_member_id uuid not null,
  child_member_id  uuid not null,
  relation         text not null check (relation in ('guardian', 'child', 'spouse', 'sibling', 'other')),
  created_at       timestamptz not null default now(),
  unique (id, arena_id),
  unique (arena_id, parent_member_id, child_member_id, relation),
  check (parent_member_id <> child_member_id),
  foreign key (parent_member_id, arena_id)
    references public.members (id, arena_id) on delete cascade,
  foreign key (child_member_id, arena_id)
    references public.members (id, arena_id) on delete cascade
);

create table public.member_codes (
  id          uuid primary key default gen_random_uuid(),
  arena_id    uuid        not null,
  member_id   uuid        not null,
  code        text        not null check (length(btrim(code)) > 0),
  kind        text        not null default 'public' check (kind in ('public', 'qr')),
  created_at  timestamptz not null default now(),
  unique (id, arena_id),
  unique (arena_id, code),
  unique (arena_id, member_id, kind),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade
);

create table public.member_stats (
  member_id              uuid primary key,
  arena_id               uuid           not null,
  visit_count            int            not null default 0,
  total_hours            numeric(12, 2) not null default 0,
  total_spend            numeric(12, 2) not null default 0,
  avg_spend              numeric(12, 2) not null default 0,
  avg_duration_minutes   numeric(12, 2) not null default 0,
  first_visit_at         timestamptz    null,
  last_visit_at          timestamptz    null,
  last_station_id        uuid           null,
  favourite_game_id      uuid           null,
  favourite_station_id   uuid           null,
  most_active_dow        int            null check (most_active_dow is null or most_active_dow between 0 and 6),
  most_active_hour       int            null check (most_active_hour is null or most_active_hour between 0 and 23),
  refreshed_at           timestamptz    not null default now(),
  unique (member_id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade
);

-- Seed system tags for every existing arena
insert into public.member_tags (arena_id, code, label, system)
select a.id, t.code, t.label, true
  from public.arenas a
 cross join (values
   ('vip', 'VIP'),
   ('student', 'Student'),
   ('streamer', 'Streamer'),
   ('tournament', 'Tournament'),
   ('regular', 'Regular'),
   ('suspended', 'Suspended'),
   ('banned', 'Banned'),
   ('minor', 'Minor'),
   ('corporate', 'Corporate')
 ) as t(code, label)
on conflict (arena_id, code) do nothing;

-- RLS: no client SELECT (D19)
alter table public.member_profiles enable row level security;
alter table public.member_tags enable row level security;
alter table public.member_tag_assignments enable row level security;
alter table public.member_notes enable row level security;
alter table public.member_relationships enable row level security;
alter table public.member_codes enable row level security;
alter table public.member_stats enable row level security;

revoke all on public.member_profiles from authenticated, anon, public;
revoke all on public.member_tags from authenticated, anon, public;
revoke all on public.member_tag_assignments from authenticated, anon, public;
revoke all on public.member_notes from authenticated, anon, public;
revoke all on public.member_relationships from authenticated, anon, public;
revoke all on public.member_codes from authenticated, anon, public;
revoke all on public.member_stats from authenticated, anon, public;

-- ── Ensure profile + code on create (extend member_create via trigger) ───────

create or replace function app.ensure_member_spine()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_code text;
begin
  insert into public.member_profiles (member_id, arena_id)
  values (new.id, new.arena_id)
  on conflict (member_id) do nothing;

  v_code := upper(substr(replace(new.id::text, '-', ''), 1, 8));
  insert into public.member_codes (arena_id, member_id, code, kind)
  values (new.arena_id, new.id, v_code, 'public')
  on conflict (arena_id, member_id, kind) do nothing;

  insert into public.member_stats (member_id, arena_id)
  values (new.id, new.arena_id)
  on conflict (member_id) do nothing;

  return new;
end;
$$;

create trigger members_ensure_spine
  after insert on public.members
  for each row execute function app.ensure_member_spine();

-- Backfill existing members
insert into public.member_profiles (member_id, arena_id)
select m.id, m.arena_id from public.members m
on conflict (member_id) do nothing;

insert into public.member_stats (member_id, arena_id)
select m.id, m.arena_id from public.members m
on conflict (member_id) do nothing;

insert into public.member_codes (arena_id, member_id, code, kind)
select m.arena_id, m.id, upper(substr(replace(m.id::text, '-', ''), 1, 8)), 'public'
  from public.members m
on conflict (arena_id, member_id, kind) do nothing;

-- ── Stats refresh ────────────────────────────────────────────────────────────

create or replace function app.member_stats_refresh(p_arena_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_visits int;
  v_hours numeric(12,2);
  v_spend numeric(12,2);
  v_avg_spend numeric(12,2);
  v_avg_dur numeric(12,2);
  v_first timestamptz;
  v_last timestamptz;
  v_last_station uuid;
  v_fav_game uuid;
  v_fav_station uuid;
  v_dow int;
  v_hour int;
begin
  select
    count(*)::int,
    coalesce(round(sum(extract(epoch from (coalesce(s.ended_at, now()) - s.started_at)) / 3600.0)::numeric, 2), 0),
    min(s.started_at),
    max(s.started_at),
    coalesce(round(avg(extract(epoch from (coalesce(s.ended_at, now()) - s.started_at)) / 60.0)::numeric, 2), 0)
  into v_visits, v_hours, v_first, v_last, v_avg_dur
  from public.sessions s
  where s.arena_id = p_arena_id
    and s.member_id = p_member_id
    and s.status <> 'cancelled';

  select coalesce(sum(o.total), 0)
    into v_spend
    from public.orders o
   where o.arena_id = p_arena_id
     and o.member_id = p_member_id
     and o.status = 'settled';

  v_avg_spend := case when v_visits > 0 then round(v_spend / v_visits, 2) else 0 end;

  select s.station_id into v_last_station
    from public.sessions s
   where s.arena_id = p_arena_id and s.member_id = p_member_id
   order by s.started_at desc nulls last
   limit 1;

  select s.game_id into v_fav_game
    from public.sessions s
   where s.arena_id = p_arena_id and s.member_id = p_member_id and s.game_id is not null
   group by s.game_id
   order by count(*) desc
   limit 1;

  select s.station_id into v_fav_station
    from public.sessions s
   where s.arena_id = p_arena_id and s.member_id = p_member_id
   group by s.station_id
   order by count(*) desc
   limit 1;

  select extract(dow from s.started_at)::int into v_dow
    from public.sessions s
   where s.arena_id = p_arena_id and s.member_id = p_member_id
   group by extract(dow from s.started_at)
   order by count(*) desc
   limit 1;

  select extract(hour from s.started_at)::int into v_hour
    from public.sessions s
   where s.arena_id = p_arena_id and s.member_id = p_member_id
   group by extract(hour from s.started_at)
   order by count(*) desc
   limit 1;

  insert into public.member_stats as ms (
    member_id, arena_id, visit_count, total_hours, total_spend, avg_spend,
    avg_duration_minutes, first_visit_at, last_visit_at, last_station_id,
    favourite_game_id, favourite_station_id, most_active_dow, most_active_hour,
    refreshed_at
  ) values (
    p_member_id, p_arena_id, coalesce(v_visits, 0), coalesce(v_hours, 0),
    coalesce(v_spend, 0), coalesce(v_avg_spend, 0), coalesce(v_avg_dur, 0),
    v_first, v_last, v_last_station, v_fav_game, v_fav_station, v_dow, v_hour, now()
  )
  on conflict (member_id) do update set
    visit_count = excluded.visit_count,
    total_hours = excluded.total_hours,
    total_spend = excluded.total_spend,
    avg_spend = excluded.avg_spend,
    avg_duration_minutes = excluded.avg_duration_minutes,
    first_visit_at = excluded.first_visit_at,
    last_visit_at = excluded.last_visit_at,
    last_station_id = excluded.last_station_id,
    favourite_game_id = excluded.favourite_game_id,
    favourite_station_id = excluded.favourite_station_id,
    most_active_dow = excluded.most_active_dow,
    most_active_hour = excluded.most_active_hour,
    refreshed_at = now();
end;
$$;

-- ── Extend member_search for codes / whatsapp ────────────────────────────────

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
        m.updated_at,
        ms.last_visit_at,
        ms.visit_count,
        ms.total_spend,
        mc.code as member_code
      from public.members m
      left join public.member_stats ms
        on ms.member_id = m.id and ms.arena_id = m.arena_id
      left join public.member_codes mc
        on mc.member_id = m.id and mc.arena_id = m.arena_id and mc.kind = 'public'
      left join public.member_profiles mp
        on mp.member_id = m.id and mp.arena_id = m.arena_id
      where m.arena_id = p_arena_id
        and m.deleted_at is null
        and (
          (v_phone is not null and m.phone = v_phone)
          or m.phone like '%' || regexp_replace(v_q, '[^0-9+]', '', 'g') || '%'
          or m.full_name ilike '%' || v_q || '%'
          or mc.code ilike v_q
          or (mp.whatsapp is not null and mp.whatsapp ilike '%' || v_q || '%')
          or (mp.email is not null and mp.email ilike '%' || v_q || '%')
          or (mp.nickname is not null and mp.nickname ilike '%' || v_q || '%')
        )
      order by
        case when v_phone is not null and m.phone = v_phone then 0 else 1 end,
        m.full_name
      limit v_limit
    ) t;

  return jsonb_build_object('members', v_rows, 'query', v_q, 'limit', v_limit);
end;
$$;

-- ── Extend member_get ────────────────────────────────────────────────────────

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
  v_profile jsonb;
  v_stats jsonb;
  v_tags jsonb;
  v_code text;
  v_outstanding numeric(12,2);
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

  perform app.member_stats_refresh(p_arena_id, p_member_id);

  select to_jsonb(mp) - 'member_id' - 'arena_id'
    into v_profile
    from public.member_profiles mp
   where mp.member_id = p_member_id and mp.arena_id = p_arena_id;

  select to_jsonb(ms) - 'member_id' - 'arena_id'
    into v_stats
    from public.member_stats ms
   where ms.member_id = p_member_id and ms.arena_id = p_arena_id;

  select mc.code into v_code
    from public.member_codes mc
   where mc.member_id = p_member_id and mc.arena_id = p_arena_id and mc.kind = 'public';

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'code', t.code, 'label', t.label, 'color', t.color
         ) order by t.label), '[]'::jsonb)
    into v_tags
    from public.member_tag_assignments a
    join public.member_tags t on t.id = a.tag_id and t.arena_id = a.arena_id
   where a.arena_id = p_arena_id and a.member_id = p_member_id;

  select coalesce(sum(o.total - o.paid_total), 0)
    into v_outstanding
    from public.orders o
   where o.arena_id = p_arena_id
     and o.member_id = p_member_id
     and o.status = 'open';

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

  return app.member_to_json(v_member)
    || jsonb_build_object(
      'member_code', v_code,
      'profile', coalesce(v_profile, '{}'::jsonb),
      'stats', coalesce(v_stats, '{}'::jsonb),
      'tags', coalesce(v_tags, '[]'::jsonb),
      'outstanding_balance', to_char(v_outstanding, 'FM999999990.00'),
      'recent_sessions', v_sessions
    );
end;
$$;

-- ── member_timeline ──────────────────────────────────────────────────────────

create or replace function public.member_timeline(
  p_arena_id  uuid,
  p_member_id uuid,
  p_limit     int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  if not exists (
    select 1 from public.members m
     where m.id = p_member_id and m.arena_id = p_arena_id and m.deleted_at is null
  ) then
    raise exception 'not_found: member' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.at desc), '[]'::jsonb)
    into v_rows
    from (
      select * from (
        select
          'session'::text as kind,
          s.id,
          s.started_at as at,
          s.status,
          st.name as station_name,
          g.title as game_title,
          null::text as amount,
          null::text as payment_method
        from public.sessions s
        left join public.stations st on st.id = s.station_id and st.arena_id = s.arena_id
        left join public.games g on g.id = s.game_id and g.arena_id = s.arena_id
        where s.arena_id = p_arena_id and s.member_id = p_member_id

        union all

        select
          'order'::text,
          o.id,
          coalesce(o.settled_at, o.created_at),
          o.status,
          null,
          null,
          to_char(o.total, 'FM999999990.00'),
          null
        from public.orders o
        where o.arena_id = p_arena_id and o.member_id = p_member_id

        union all

        select
          'payment'::text,
          p.id,
          p.created_at,
          'recorded',
          null,
          null,
          to_char(p.amount, 'FM999999990.00'),
          p.method
        from public.payments p
        join public.orders o on o.id = p.order_id and o.arena_id = p.arena_id
        where p.arena_id = p_arena_id and o.member_id = p_member_id
      ) u
      order by u.at desc
      limit v_limit
    ) t;

  return jsonb_build_object('member_id', p_member_id, 'events', v_rows);
end;
$$;

grant execute on function public.member_timeline(uuid, uuid, int) to authenticated;

-- ── Notes ────────────────────────────────────────────────────────────────────

create or replace function public.member_note_add(
  p_arena_id  uuid,
  p_member_id uuid,
  p_kind      text,
  p_body      text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_note public.member_notes;
begin
  perform app.require_permission(p_arena_id, 'member.update');

  if not exists (
    select 1 from public.members m
     where m.id = p_member_id and m.arena_id = p_arena_id and m.deleted_at is null
  ) then
    raise exception 'not_found: member' using errcode = 'P0001';
  end if;

  if p_kind is null or p_kind not in ('behaviour', 'damage', 'no_show', 'vip_pref', 'general') then
    raise exception 'validation_failed: invalid note kind' using errcode = 'P0001';
  end if;

  if p_body is null or length(btrim(p_body)) = 0 then
    raise exception 'validation_failed: note body is required' using errcode = 'P0001';
  end if;

  insert into public.member_notes (arena_id, member_id, kind, body, created_by_user_id)
  values (p_arena_id, p_member_id, p_kind, btrim(p_body), app.current_actor_id())
  returning * into v_note;

  perform app.audit(
    p_arena_id, 'member.note_added', 'member', p_member_id,
    jsonb_build_object('note_id', v_note.id, 'kind', p_kind)
  );

  return jsonb_build_object(
    'id', v_note.id,
    'kind', v_note.kind,
    'body', v_note.body,
    'created_at', v_note.created_at,
    'created_by_user_id', v_note.created_by_user_id
  );
end;
$$;

grant execute on function public.member_note_add(uuid, uuid, text, text) to authenticated;

create or replace function public.member_note_list(
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
  v_rows jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', n.id,
           'kind', n.kind,
           'body', n.body,
           'created_at', n.created_at,
           'created_by_user_id', n.created_by_user_id
         ) order by n.created_at desc), '[]'::jsonb)
    into v_rows
    from public.member_notes n
   where n.arena_id = p_arena_id
     and n.member_id = p_member_id
     and n.deleted_at is null;

  return jsonb_build_object('notes', v_rows);
end;
$$;

grant execute on function public.member_note_list(uuid, uuid) to authenticated;

-- ── Tags ─────────────────────────────────────────────────────────────────────

create or replace function public.member_tag_set(
  p_arena_id  uuid,
  p_member_id uuid,
  p_tag_codes text[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_codes text[] := coalesce(p_tag_codes, '{}');
  v_tags jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.update');

  if not exists (
    select 1 from public.members m
     where m.id = p_member_id and m.arena_id = p_arena_id and m.deleted_at is null
  ) then
    raise exception 'not_found: member' using errcode = 'P0001';
  end if;

  delete from public.member_tag_assignments a
   where a.arena_id = p_arena_id and a.member_id = p_member_id;

  insert into public.member_tag_assignments (arena_id, member_id, tag_id, assigned_by_user_id)
  select p_arena_id, p_member_id, t.id, app.current_actor_id()
    from public.member_tags t
   where t.arena_id = p_arena_id
     and t.code = any (v_codes);

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'code', t.code, 'label', t.label
         ) order by t.label), '[]'::jsonb)
    into v_tags
    from public.member_tag_assignments a
    join public.member_tags t on t.id = a.tag_id and t.arena_id = a.arena_id
   where a.arena_id = p_arena_id and a.member_id = p_member_id;

  return jsonb_build_object('tags', coalesce(v_tags, '[]'::jsonb));
end;
$$;

grant execute on function public.member_tag_set(uuid, uuid, text[]) to authenticated;

-- ── Profile update ───────────────────────────────────────────────────────────

create or replace function public.member_profile_update(
  p_arena_id uuid,
  p_member_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_profile public.member_profiles;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  perform app.require_permission(p_arena_id, 'member.update');

  insert into public.member_profiles (member_id, arena_id)
  values (p_member_id, p_arena_id)
  on conflict (member_id) do nothing;

  update public.member_profiles mp
     set nickname = case when v_patch ? 'nickname' then nullif(btrim(v_patch->>'nickname'), '') else mp.nickname end,
         email = case when v_patch ? 'email' then nullif(btrim(v_patch->>'email'), '') else mp.email end,
         whatsapp = case when v_patch ? 'whatsapp' then nullif(btrim(v_patch->>'whatsapp'), '') else mp.whatsapp end,
         gender = case when v_patch ? 'gender' then nullif(v_patch->>'gender', '') else mp.gender end,
         preferred_platform = case when v_patch ? 'preferred_platform' then nullif(v_patch->>'preferred_platform', '') else mp.preferred_platform end,
         skill_level = case when v_patch ? 'skill_level' then nullif(v_patch->>'skill_level', '') else mp.skill_level end,
         marketing_consent = case when v_patch ? 'marketing_consent' then (v_patch->>'marketing_consent')::boolean else mp.marketing_consent end,
         emergency_contact = case when v_patch ? 'emergency_contact' then v_patch->'emergency_contact' else mp.emergency_contact end,
         guardian = case when v_patch ? 'guardian' then v_patch->'guardian' else mp.guardian end,
         preferred_game_id = case when v_patch ? 'preferred_game_id' then nullif(v_patch->>'preferred_game_id', '')::uuid else mp.preferred_game_id end,
         preferred_station_id = case when v_patch ? 'preferred_station_id' then nullif(v_patch->>'preferred_station_id', '')::uuid else mp.preferred_station_id end
   where mp.member_id = p_member_id and mp.arena_id = p_arena_id
  returning * into v_profile;

  if v_profile.member_id is null then
    raise exception 'not_found: member' using errcode = 'P0001';
  end if;

  return to_jsonb(v_profile);
end;
$$;

grant execute on function public.member_profile_update(uuid, uuid, jsonb) to authenticated;

-- ── Analytics overview (Owner) ───────────────────────────────────────────────

create or replace function public.member_analytics_overview(p_arena_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_top jsonb;
  v_lapse jsonb;
  v_counts jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  select coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
    into v_top
    from (
      select m.id, m.full_name, app.mask_phone(m.phone) as phone_masked,
             ms.total_spend, ms.visit_count, ms.last_visit_at
        from public.member_stats ms
        join public.members m on m.id = ms.member_id and m.arena_id = ms.arena_id
       where ms.arena_id = p_arena_id and m.deleted_at is null
       order by ms.total_spend desc
       limit 20
    ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
    into v_lapse
    from (
      select m.id, m.full_name, app.mask_phone(m.phone) as phone_masked,
             ms.last_visit_at, ms.visit_count
        from public.member_stats ms
        join public.members m on m.id = ms.member_id and m.arena_id = ms.arena_id
       where ms.arena_id = p_arena_id
         and m.deleted_at is null
         and (ms.last_visit_at is null or ms.last_visit_at < now() - interval '90 days')
       order by ms.last_visit_at nulls first
       limit 50
    ) t;

  select jsonb_build_object(
           'members_total', (select count(*) from public.members where arena_id = p_arena_id and deleted_at is null),
           'blocked', (select count(*) from public.members where arena_id = p_arena_id and deleted_at is null and blocked),
           'visited_30d', (
             select count(*) from public.member_stats
              where arena_id = p_arena_id and last_visit_at >= now() - interval '30 days'
           )
         )
    into v_counts;

  return jsonb_build_object(
    'counts', v_counts,
    'top_spend', v_top,
    'no_visit_90d', v_lapse
  );
end;
$$;

grant execute on function public.member_analytics_overview(uuid) to authenticated;

-- AI stub (commercial AI0 pattern)
create or replace function public.insights_members(p_arena_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'member.view');
  raise exception 'not_implemented: insights_members'
    using errcode = 'P0001';
end;
$$;

grant execute on function public.insights_members(uuid) to authenticated;

-- Seed system tags when new arenas are provisioned — wrap via trigger on arenas
create or replace function app.seed_member_system_tags()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  insert into public.member_tags (arena_id, code, label, system)
  values
    (new.id, 'vip', 'VIP', true),
    (new.id, 'student', 'Student', true),
    (new.id, 'streamer', 'Streamer', true),
    (new.id, 'tournament', 'Tournament', true),
    (new.id, 'regular', 'Regular', true),
    (new.id, 'suspended', 'Suspended', true),
    (new.id, 'banned', 'Banned', true),
    (new.id, 'minor', 'Minor', true),
    (new.id, 'corporate', 'Corporate', true)
  on conflict (arena_id, code) do nothing;
  return new;
end;
$$;

create trigger arenas_seed_member_tags
  after insert on public.arenas
  for each row execute function app.seed_member_system_tags();
