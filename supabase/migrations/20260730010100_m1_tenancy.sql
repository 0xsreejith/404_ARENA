-- M1 — tenancy and identity.
--
-- organizations · arenas · profiles · permissions · roles · role_permissions
-- arena_users · devices
--
-- The arena is the operational tenant boundary (D02). Every tenant-owned table
-- below declares UNIQUE (id, arena_id) purely as a composite foreign-key
-- target, and every relationship between two tenant-owned tables is composite
-- (D03). That makes a cross-arena reference impossible at the storage layer,
-- independently of RLS or application code.
--
-- Governing: DATABASE.md §1, §3 · SECURITY.md §3, §7 · D02, D03, D04, D17.

-- ── organizations ────────────────────────────────────────────────────────────
-- Not tenant-owned. A grouping label only in P0 (D02).

create table public.organizations (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.organizations is
  'Owns arenas. In P0 a grouping label only — no cross-arena read, aggregation '
  'or configuration inheritance (D02).';

create trigger organizations_touch_updated_at
  before update on public.organizations
  for each row execute function app.touch_updated_at();

-- ── arenas ───────────────────────────────────────────────────────────────────
-- The tenant boundary. Children reference arenas(id) directly.

create table public.arenas (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid        not null references public.organizations (id) on delete restrict,
  name            text        not null check (length(btrim(name)) > 0),
  timezone        text        not null check (length(btrim(timezone)) > 0),
  currency        text        not null check (currency ~ '^[A-Z]{3}$'),
  phone           text        null,
  address         text        null,
  active          boolean     not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.arenas is
  'The operational tenant boundary (D02). timezone is an IANA name and currency '
  'an ISO 4217 code — both tenant configuration, never assumed in code.';
comment on column public.arenas.currency is
  'ISO 4217. P0 assumes a 2-decimal minor unit (D01). Set per tenant by '
  'provision_arena; no currency is hardcoded anywhere.';

create index arenas_organization_id_idx on public.arenas (organization_id);

create trigger arenas_touch_updated_at
  before update on public.arenas
  for each row execute function app.touch_updated_at();

-- ── profiles ─────────────────────────────────────────────────────────────────
-- Not tenant-owned. profiles.id = auth.users.id (D04). One Supabase user per
-- real staff member; there is no shared-device account.

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete restrict,
  display_name text        not null check (length(btrim(display_name)) > 0),
  phone        text        null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.profiles is
  'One row per authenticated staff user, keyed to auth.users (D04). Every '
  'actor column in the schema references this table. Readable only to users '
  'sharing an arena (SECURITY.md §4).';

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function app.touch_updated_at();

-- ── permissions ──────────────────────────────────────────────────────────────
-- Global catalogue, not tenant-owned. Adding a code is a migration; it grants
-- nothing until a role references it (PERMISSIONS.md §1).

create table public.permissions (
  code        text primary key check (code ~ '^[a-z_]+\.[a-z_]+$'),
  description text not null check (length(btrim(description)) > 0),
  category    text not null check (length(btrim(category)) > 0)
);

comment on table public.permissions is
  'The P0 permission catalogue (PERMISSIONS.md §1). Authorisation is by code, '
  'never by role name. Seeded by its own migration, not by provision_arena.';

-- ── roles ────────────────────────────────────────────────────────────────────
-- arena_id is NOT NULL specifically so no role is ever shared across tenants
-- (audit finding C11, SECURITY.md §7).

create table public.roles (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null references public.arenas (id) on delete restrict,
  code       text        not null check (length(btrim(code)) > 0),
  name       text        not null check (length(btrim(name)) > 0),
  is_system  boolean     not null default false,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, arena_id)
);

comment on table public.roles is
  'Arena-scoped collections of permission codes. arena_id is NOT NULL so one '
  'tenant can never alter another tenant''s permission set (C11).';
comment on column public.roles.is_system is
  'System roles seeded by provision_arena cannot be deleted; their permission '
  'sets can be edited (PERMISSIONS.md §3).';

create unique index roles_arena_code_live_idx
  on public.roles (arena_id, code) where deleted_at is null;
create index roles_arena_id_idx on public.roles (arena_id);

create trigger roles_touch_updated_at
  before update on public.roles
  for each row execute function app.touch_updated_at();

-- ── role_permissions ─────────────────────────────────────────────────────────
-- Join table: no id, no timestamps (DATABASE.md §1.3).

create table public.role_permissions (
  arena_id        uuid not null,
  role_id         uuid not null,
  permission_code text not null references public.permissions (code) on delete restrict,
  primary key (role_id, permission_code),
  foreign key (role_id, arena_id) references public.roles (id, arena_id) on delete restrict
);

comment on table public.role_permissions is
  'Arena-scoped by composite FK into roles, so a permission grant cannot cross '
  'a tenant boundary (C11, D03).';

create index role_permissions_permission_code_idx on public.role_permissions (permission_code);
create index role_permissions_arena_id_idx on public.role_permissions (arena_id);

-- ── arena_users ──────────────────────────────────────────────────────────────
-- Membership. Deactivated via `active`, never deleted (D17).
--
-- No staff_pin_hash column: PIN switching is deferred and will arrive in its
-- own table with no client read access (D04).

create table public.arena_users (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null references public.arenas (id) on delete restrict,
  user_id    uuid        not null references public.profiles (id) on delete restrict,
  role_id    uuid        not null,
  active     boolean     not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, arena_id),
  unique (arena_id, user_id),
  foreign key (role_id, arena_id) references public.roles (id, arena_id) on delete restrict
);

comment on table public.arena_users is
  'One role per user per arena in P0, no per-user overrides (PERMISSIONS.md §3). '
  'This is the record app.current_arena_ids() resolves.';

create index arena_users_arena_id_idx on public.arena_users (arena_id);
create index arena_users_user_id_idx on public.arena_users (user_id);
create index arena_users_role_id_idx on public.arena_users (role_id);

create trigger arena_users_touch_updated_at
  before update on public.arena_users
  for each row execute function app.touch_updated_at();

-- ── devices ──────────────────────────────────────────────────────────────────
-- Operational telemetry. device_id is client-asserted and authorises nothing
-- (SECURITY.md §6).

create table public.devices (
  id                     uuid primary key,
  arena_id               uuid        not null references public.arenas (id) on delete restrict,
  name                   text        not null check (length(btrim(name)) > 0),
  platform               text        not null check (platform in ('android', 'ios')),
  app_version            text        null,
  registered_by_user_id  uuid        not null references public.profiles (id) on delete restrict,
  last_seen_at           timestamptz null,
  active                 boolean     not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (id, arena_id)
);

comment on table public.devices is
  'Client-generated id, stable per install (D17). Telemetry only — nothing is '
  'authorised on the basis of a device (SECURITY.md §6).';

create index devices_arena_id_idx on public.devices (arena_id);
create index devices_registered_by_user_id_idx on public.devices (registered_by_user_id);

create trigger devices_touch_updated_at
  before update on public.devices
  for each row execute function app.touch_updated_at();
