-- M1 — `app` helper functions.
--
-- The internal surface every RPC is built on. All are SECURITY DEFINER, owned
-- by postgres, and unreachable through PostgREST (DATABASE.md §2).
--
-- Two of them are granted to `authenticated` because RLS policies are evaluated
-- with the invoker's privileges and must be able to call them. Everything else
-- stays definer-only.
--
-- Governing: DATABASE.md §2, §9, §10, §11 · SECURITY.md §3, §5, §6 · D04, D09,
-- D13, D16, D31, D36.

-- ── Actor and membership ─────────────────────────────────────────────────────

create function app.current_actor_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select auth.uid();
$$;

comment on function app.current_actor_id() is
  'The acting user. P0 returns auth.uid(). This is the single seam that future '
  'PIN switching occupies — no column, audit record or RPC signature changes '
  'when it does (D04).';

create function app.current_arena_ids()
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select au.arena_id
    from public.arena_users au
   where au.user_id = app.current_actor_id()
     and au.active;
$$;

comment on function app.current_arena_ids() is
  'Arenas the caller belongs to with active membership. SECURITY DEFINER is not '
  'incidental: a policy on arena_users that reads arena_users through the '
  'invoker''s rights recurses infinitely (SECURITY.md §3).';

create function app.is_arena_member(p_arena_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select exists (
    select 1 from app.current_arena_ids() a where a = p_arena_id
  );
$$;

create function app.has_permission(p_arena_id uuid, p_code text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select exists (
    select 1
      from public.arena_users au
      join public.roles r
        on r.id = au.role_id and r.arena_id = au.arena_id
      join public.role_permissions rp
        on rp.role_id = r.id and rp.arena_id = r.arena_id
     where au.arena_id = p_arena_id
       and au.user_id = app.current_actor_id()
       and au.active
       and r.deleted_at is null
       and rp.permission_code = p_code
  );
$$;

comment on function app.has_permission(uuid, text) is
  'Resolves role -> permissions for the caller in one arena. Authorisation is '
  'by permission code, never by role name (PERMISSIONS.md).';

create function app.require_permission(p_arena_id uuid, p_code text)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
begin
  -- The first statement of every mutating RPC. Membership is asserted here, so
  -- a client-supplied arena_id is never trusted (SECURITY.md §3, §5).
  --
  -- Both failures raise the same code: telling a caller that an arena exists
  -- but they lack a permission is itself a small leak.
  if p_arena_id is null then
    raise exception 'insufficient_privilege: no arena supplied'
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_arena_member(p_arena_id) then
    raise exception 'insufficient_privilege: not a member of that arena'
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_permission(p_arena_id, p_code) then
    raise exception 'insufficient_privilege: % is required', p_code
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

-- ── Business date ────────────────────────────────────────────────────────────

create function app.business_date(p_arena_id uuid, p_at timestamptz default now())
returns date
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_business_date date;
begin
  select ((p_at at time zone a.timezone) - s.business_day_start_time::interval)::date
    into v_business_date
    from public.arenas a
    join public.arena_settings s on s.arena_id = a.id
   where a.id = p_arena_id;

  if v_business_date is null then
    raise exception 'not_found: arena % has no settings row', p_arena_id
      using errcode = 'P0001';
  end if;

  return v_business_date;
end;
$$;

comment on function app.business_date(uuid, timestamptz) is
  'The only implementation of the business date (D09). Gaming centres trade '
  'past midnight, so nothing groups by created_at::date.';

create function app.current_shift_id(p_arena_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select s.id
    from public.shifts s
   where s.arena_id = p_arena_id
     and s.status = 'open';
$$;

comment on function app.current_shift_id(uuid) is
  'The single open shift, or null. One open shift per arena is enforced by a '
  'partial unique index (D30).';

-- ── Receipt numbering ────────────────────────────────────────────────────────
-- No jurisdiction's numbering rule appears here. The series key and the
-- rendered format are both arena configuration (D13 as amended by D31).

create function app.receipt_series(p_arena_id uuid, p_business_date date)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_mode        text;
  v_fixed       text;
  v_start_month int;
  v_start_year  int;
begin
  select s.receipt_series_mode, s.receipt_fixed_series, s.receipt_financial_year_start_month
    into v_mode, v_fixed, v_start_month
    from public.arena_settings s
   where s.arena_id = p_arena_id;

  if v_mode is null then
    raise exception 'not_found: arena % has no settings row', p_arena_id
      using errcode = 'P0001';
  end if;

  if v_mode = 'fixed' then
    return v_fixed;
  elsif v_mode = 'monthly' then
    return to_char(p_business_date, 'YYYY-MM');
  elsif v_mode = 'yearly' then
    return to_char(p_business_date, 'YYYY');
  elsif v_mode = 'financial_yearly' then
    -- Start month 1 makes this identical to `yearly` (DATABASE.md §10).
    if v_start_month = 1 then
      return to_char(p_business_date, 'YYYY');
    end if;
    v_start_year := extract(year from p_business_date)::int;
    if extract(month from p_business_date)::int < v_start_month then
      v_start_year := v_start_year - 1;
    end if;
    return v_start_year::text || '-' || lpad(((v_start_year + 1) % 100)::text, 2, '0');
  end if;

  raise exception 'validation_failed: unknown receipt_series_mode %', v_mode
    using errcode = 'P0001';
end;
$$;

comment on function app.receipt_series(uuid, date) is
  'The only place numbering policy lives (D31). An Indian arena restarts each '
  'April by setting receipt_series_mode and the FY start month — no code change.';

create function app.render_receipt_number(p_arena_id uuid, p_series text, p_sequence bigint)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_format  text;
  v_prefix  text;
  v_padding int;
begin
  select s.receipt_number_format, s.receipt_prefix, s.receipt_number_padding
    into v_format, v_prefix, v_padding
    from public.arena_settings s
   where s.arena_id = p_arena_id;

  if v_format is null then
    raise exception 'not_found: arena % has no settings row', p_arena_id
      using errcode = 'P0001';
  end if;

  return replace(
           replace(
             replace(v_format, '{prefix}', v_prefix),
             '{series}', coalesce(p_series, '')
           ),
           '{sequence}', lpad(p_sequence::text, v_padding, '0')
         );
end;
$$;

comment on function app.render_receipt_number(uuid, text, bigint) is
  'Substitutes {prefix}, {series} and {sequence} into the tenant''s '
  'receipt_number_format. Templates are data, so no format is embedded in SQL '
  'or Dart (D13).';

create function app.next_receipt_number(
  p_arena_id uuid,
  p_business_date date,
  out series_key text,
  out sequence_number bigint,
  out formatted_number text
)
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  -- The OUT parameters are named *_key / *_number rather than series / sequence
  -- so nothing in this body is ambiguous with a receipt_counters column.
  v_series   text;
  v_sequence bigint;
begin
  v_series := app.receipt_series(p_arena_id, p_business_date);

  -- The counter row is created on first use, so a new series (a new financial
  -- year, say) starts at 1 with no migration (D13, DATABASE.md §10).
  insert into public.receipt_counters (arena_id, series)
  values (p_arena_id, v_series)
  on conflict (arena_id, series) do nothing;

  select rc.next_number
    into v_sequence
    from public.receipt_counters rc
   where rc.arena_id = p_arena_id
     and rc.series = v_series
     for update;

  update public.receipt_counters rc
     set next_number = rc.next_number + 1,
         updated_at = now()
   where rc.arena_id = p_arena_id
     and rc.series = v_series;

  series_key       := v_series;
  sequence_number  := v_sequence;
  formatted_number := app.render_receipt_number(p_arena_id, v_series, v_sequence);
end;
$$;

comment on function app.next_receipt_number(uuid, date) is
  'Claims the next number in the arena''s current series under a row lock. '
  'Gap-free within a transaction: a rolled-back settlement releases the number.';

-- ── Phone normalisation ──────────────────────────────────────────────────────

create function app.normalise_phone(p_arena_id uuid, p_raw text)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_dial_code   text;
  v_digits      text;
  v_candidate   text;
  v_is_international boolean;
begin
  if p_raw is null or btrim(p_raw) = '' then
    raise exception 'validation_failed: a phone number is required'
      using errcode = 'P0001';
  end if;

  select s.default_phone_dial_code
    into v_dial_code
    from public.arena_settings s
   where s.arena_id = p_arena_id;

  if v_dial_code is null then
    raise exception 'not_found: arena % has no settings row', p_arena_id
      using errcode = 'P0001';
  end if;

  -- An input already starting `+` is taken as given; anything else is a
  -- national number for this arena's dial code (D36).
  v_is_international := btrim(p_raw) like '+%';
  v_digits := regexp_replace(p_raw, '[^0-9]', '', 'g');

  if not v_is_international then
    -- Strip a national trunk prefix: `098765 43210` and `9876543210` are the
    -- same subscriber, and uniqueness is on the canonical form.
    v_digits := ltrim(v_digits, '0');
    v_candidate := v_dial_code || v_digits;
  else
    v_candidate := '+' || v_digits;
  end if;

  -- A generic length floor, not a jurisdiction rule: it is what rejects
  -- obviously invalid input such as a five-digit string (DATABASE.md §16.7).
  if length(v_digits) < 7 then
    raise exception 'validation_failed: % is not a valid phone number', p_raw
      using errcode = 'P0001';
  end if;

  if v_candidate !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'validation_failed: % is not a valid phone number', p_raw
      using errcode = 'P0001';
  end if;

  return v_candidate;
end;
$$;

comment on function app.normalise_phone(uuid, text) is
  'Canonical E.164 using the arena''s default_phone_dial_code (D36). '
  'Normalisation is server-side because two clients normalising differently '
  'would make the uniqueness constraint meaningless.';

-- ── Audit ────────────────────────────────────────────────────────────────────

create function app.audit(
  p_arena_id    uuid,
  p_action      text,
  p_entity_type text,
  p_entity_id   uuid,
  p_metadata    jsonb default '{}'::jsonb,
  p_device_id   uuid default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  insert into public.audit_logs (
    arena_id, actor_user_id, action, entity_type, entity_id,
    metadata, device_id, business_date
  )
  values (
    p_arena_id, app.current_actor_id(), p_action, p_entity_type, p_entity_id,
    coalesce(p_metadata, '{}'::jsonb), p_device_id, app.business_date(p_arena_id, now())
  );
end;
$$;

comment on function app.audit(uuid, text, text, uuid, jsonb, uuid) is
  'Inserts an audit row in the caller''s transaction, so a client cannot '
  'perform an audited action and skip the record (D22). p_device_id is '
  'reported telemetry and authorises nothing (SECURITY.md §6).';

-- ── Idempotency ──────────────────────────────────────────────────────────────
-- The server-side store only. The client outbox is a Drift table on the device
-- and is never synchronised here (D16).

create function app.claim_idempotency(
  p_arena_id    uuid,
  p_key         text,
  p_operation   text,
  p_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_existing public.idempotency_keys;
begin
  if p_key is null or btrim(p_key) = '' then
    raise exception 'validation_failed: an idempotency key is required'
      using errcode = 'P0001';
  end if;

  select *
    into v_existing
    from public.idempotency_keys k
   where k.arena_id = p_arena_id
     and k.key = p_key
     for update;

  if not found then
    insert into public.idempotency_keys (
      arena_id, key, operation, request_fingerprint, status, actor_user_id
    )
    values (
      p_arena_id, p_key, p_operation, p_fingerprint, 'in_progress', app.current_actor_id()
    );
    return null;  -- miss: the caller proceeds
  end if;

  -- Same key, different arguments: a conflict, never a silent overwrite.
  if v_existing.request_fingerprint is distinct from p_fingerprint
     or v_existing.operation is distinct from p_operation then
    raise exception 'idempotency_key_reuse: key % was already used with different arguments',
      p_key
      using errcode = 'P0001';
  end if;

  if v_existing.status = 'succeeded' then
    -- Replay: return the stored response rather than repeating side effects.
    -- jsonb 'null' rather than SQL NULL, so a caller can still distinguish a
    -- hit from a miss.
    return coalesce(v_existing.response, 'null'::jsonb);
  end if;

  if v_existing.status = 'in_progress' then
    raise exception 'operation_in_progress: % is already running under key %',
      p_operation, p_key
      using errcode = 'P0001';
  end if;

  -- `failed` with a matching fingerprint is a legitimate retry of a rejected
  -- attempt (OFFLINE.md §5), so the claim is re-opened.
  update public.idempotency_keys k
     set status = 'in_progress',
         response = null,
         actor_user_id = app.current_actor_id()
   where k.arena_id = p_arena_id
     and k.key = p_key;

  return null;
end;
$$;

comment on function app.claim_idempotency(uuid, text, text, text) is
  'Returns the stored response on replay, or SQL NULL to proceed '
  '(DATABASE.md §11). Takes the operation name as well as the fingerprint '
  'because idempotency_keys.operation is NOT NULL.';

create function app.complete_idempotency(p_arena_id uuid, p_key text, p_response jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  update public.idempotency_keys k
     set status = 'succeeded',
         response = coalesce(p_response, 'null'::jsonb)
   where k.arena_id = p_arena_id
     and k.key = p_key;

  if not found then
    raise exception 'not_found: no idempotency claim for key %', p_key
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function app.complete_idempotency(uuid, text, jsonb) is
  'Step 8 of the mutating-RPC skeleton: store the authoritative response so a '
  'replay returns it (SECURITY.md §5).';

-- ── Privileges ───────────────────────────────────────────────────────────────
--
-- Only the helpers an RLS policy must evaluate are reachable by `authenticated`.
-- Everything else is callable solely from inside a SECURITY DEFINER RPC.

revoke all on all functions in schema app from public;

grant execute on function app.current_actor_id() to authenticated;
grant execute on function app.current_arena_ids() to authenticated;
grant execute on function app.is_arena_member(uuid) to authenticated;
grant execute on function app.has_permission(uuid, text) to authenticated;
