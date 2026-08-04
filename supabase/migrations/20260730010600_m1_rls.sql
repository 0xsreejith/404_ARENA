-- M1 — privileges and Row Level Security.
--
-- Five independent layers defend authorisation (SECURITY.md §1). This migration
-- lays down the first two:
--
--   Layer 1 — PostgreSQL privileges. `authenticated` has NO insert, update or
--             delete privilege on ANY table in public. Writes have no client
--             path by construction; this is the primary write control, not RLS.
--   Layer 2 — Row Level Security on every table, scoping reads to the caller's
--             arenas. A table with RLS enabled and no policy denies everything,
--             which is the correct default for the tables with no client read.
--
-- Governing: SECURITY.md §4, §5, §8 · D05, D19.

-- ── Layer 1: privileges ──────────────────────────────────────────────────────
--
-- Start from nothing for both client roles, then grant SELECT back where a read
-- path is intended. anon is never granted anything: there is no unauthenticated
-- surface in P0.

revoke all on all tables in schema public from anon, authenticated;

-- service_role is a backend/administrative credential outside the client
-- security model (D37). It bypasses RLS by design; the append-only triggers
-- still refuse it (SECURITY.md §10).
grant all on all tables in schema public to service_role;

grant select on table
  public.organizations,
  public.arenas,
  public.arena_settings,
  public.profiles,
  public.permissions,
  public.roles,
  public.role_permissions,
  public.arena_users,
  public.devices,
  public.zones,
  public.station_types,
  public.stations,
  public.games,
  public.billing_plans,
  public.tax_rates,
  public.tax_rate_components,
  public.products,
  public.product_stock,
  public.inventory_movements,
  public.shifts,
  public.sessions,
  public.orders,
  public.order_items,
  public.payments,
  public.audit_logs
to authenticated;

-- Deliberately absent from the grant above, and asserted in pgTAP:
--
--   members            no direct client read at all (D19, SECURITY.md §8)
--   receipt_counters   no client read
--   idempotency_keys   no client read

-- ── Layer 2: RLS on every table ──────────────────────────────────────────────

alter table public.organizations        enable row level security;
alter table public.arenas               enable row level security;
alter table public.arena_settings       enable row level security;
alter table public.profiles             enable row level security;
alter table public.permissions          enable row level security;
alter table public.roles                enable row level security;
alter table public.role_permissions     enable row level security;
alter table public.arena_users          enable row level security;
alter table public.devices              enable row level security;
alter table public.zones                enable row level security;
alter table public.station_types        enable row level security;
alter table public.stations             enable row level security;
alter table public.games                enable row level security;
alter table public.billing_plans        enable row level security;
alter table public.tax_rates            enable row level security;
alter table public.tax_rate_components  enable row level security;
alter table public.members              enable row level security;
alter table public.products             enable row level security;
alter table public.inventory_movements  enable row level security;
alter table public.product_stock        enable row level security;
alter table public.shifts               enable row level security;
alter table public.sessions             enable row level security;
alter table public.orders               enable row level security;
alter table public.order_items          enable row level security;
alter table public.payments             enable row level security;
alter table public.receipt_counters     enable row level security;
alter table public.idempotency_keys     enable row level security;
alter table public.audit_logs           enable row level security;

-- ── Read policies ────────────────────────────────────────────────────────────
--
-- No table has an INSERT, UPDATE or DELETE policy for `authenticated`. That is
-- not an omission: writes are unreachable at the privilege layer, and adding a
-- write policy would be the first step towards a client-writable money column.

-- Non-tenant-owned tables, whose read rule differs from the standard shape.

create policy read_own_organizations on public.organizations
  for select to authenticated
  using (
    exists (
      select 1
        from public.arenas a
       where a.organization_id = organizations.id
         and a.id in (select app.current_arena_ids())
    )
  );

create policy read_shared_profiles on public.profiles
  for select to authenticated
  using (
    id = app.current_actor_id()
    or exists (
      select 1
        from public.arena_users au
       where au.user_id = profiles.id
         and au.arena_id in (select app.current_arena_ids())
    )
  );

comment on policy read_shared_profiles on public.profiles is
  'A globally readable profiles table is cross-tenant staff enumeration '
  '(SECURITY.md §4).';

create policy read_permissions on public.permissions
  for select to authenticated
  using (true);

comment on policy read_permissions on public.permissions is
  'A code list, not tenant data. Readable by every authenticated user; it '
  'grants nothing on its own (PERMISSIONS.md §1).';

-- Tenant-owned tables: the standard shape.

create policy read_own_arena on public.arenas
  for select to authenticated
  using (id in (select app.current_arena_ids()));

create policy read_own_arena on public.arena_settings
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.roles
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.role_permissions
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.arena_users
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.devices
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.zones
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.station_types
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.stations
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.games
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.billing_plans
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.tax_rates
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.tax_rate_components
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.products
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.product_stock
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.inventory_movements
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.shifts
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.sessions
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.orders
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.order_items
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

create policy read_own_arena on public.payments
  for select to authenticated
  using (arena_id in (select app.current_arena_ids()));

-- audit_logs is arena-scoped AND permission-gated (SECURITY.md §4).

create policy read_own_arena_with_report_view on public.audit_logs
  for select to authenticated
  using (
    arena_id in (select app.current_arena_ids())
    and app.has_permission(arena_id, 'report.view')
  );

-- members, receipt_counters and idempotency_keys deliberately have NO policy.
-- RLS is enabled, so they deny everything. For members that is belt and braces
-- on top of the revoked SELECT privilege: there is no query a client can write
-- that returns the member table (SECURITY.md §8).
