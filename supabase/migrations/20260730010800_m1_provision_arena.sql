-- M1 — provision_arena.
--
-- Creates a fully usable tenant in one transaction (DATABASE.md §15). A second
-- arena must need this call and nothing else — that is the M10 acceptance
-- criterion, and it is why nothing about any particular tenant appears below.
--
-- What it deliberately does NOT seed: billing plans, products, station types,
-- games, receipt_counters. Pricing is configuration a tenant supplies (D33),
-- an empty catalogue is the correct starting state, and order_settle inserts a
-- counter row the first time a series is used (§10).
--
-- Execute is NOT granted to `authenticated`. There is no permission code for
-- creating an arena in the P0 catalogue, and a self-serve provisioning path is
-- M10 work; until then this is an administrative call made with service_role.

create function public.provision_arena(
  p_organization_id         uuid,
  p_name                    text,
  p_timezone                text,
  p_currency                text,
  p_default_phone_dial_code text,
  p_owner_user_id           uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_arena_id       uuid;
  v_owner_role_id  uuid;
  v_manager_role_id uuid;
  v_staff_role_id  uuid;
  v_tax_rate_id    uuid;
  v_staff_codes    text[] := array[
    'session.view', 'session.start', 'session.pause', 'session.resume',
    'session.extend', 'session.stop',
    'station.view',
    'member.view', 'member.create',
    'product.view', 'inventory.view', 'inventory.sell',
    'shift.view', 'shift.open',
    'payment.create', 'payment.view'
  ];
  v_manager_extra_codes text[] := array[
    'session.cancel',
    'station.update', 'station.maintenance',
    'member.update', 'member.block',
    'product.manage', 'inventory.adjust', 'inventory.receive',
    'shift.close',
    'discount.apply', 'order.void',
    'report.view', 'staff.view'
  ];
begin
  -- ── Validate ───────────────────────────────────────────────────────────────

  if p_name is null or btrim(p_name) = '' then
    raise exception 'validation_failed: an arena name is required'
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'not_found: organization %', p_organization_id
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.profiles pr where pr.id = p_owner_user_id) then
    raise exception 'not_found: owner profile %', p_owner_user_id
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from pg_catalog.pg_timezone_names t where t.name = p_timezone) then
    raise exception 'validation_failed: % is not a known IANA timezone', p_timezone
      using errcode = 'P0001';
  end if;

  if p_currency !~ '^[A-Z]{3}$' then
    raise exception 'validation_failed: % is not an ISO 4217 currency code', p_currency
      using errcode = 'P0001';
  end if;

  if p_default_phone_dial_code !~ '^\+[1-9][0-9]{0,3}$' then
    raise exception 'validation_failed: % is not a valid dial code', p_default_phone_dial_code
      using errcode = 'P0001';
  end if;

  -- ── 1. The arena ───────────────────────────────────────────────────────────

  insert into public.arenas (organization_id, name, timezone, currency)
  values (p_organization_id, btrim(p_name), p_timezone, p_currency)
  returning id into v_arena_id;

  -- ── 2. Settings, with tax-rate defaults left null for now ──────────────────
  -- Everything else takes the column default. A tenant edits these with
  -- `pricing.manage` and `arena.settings`; none of it is compiled in.

  insert into public.arena_settings (arena_id, default_phone_dial_code)
  values (v_arena_id, p_default_phone_dial_code);

  -- ── 3. System roles and their permission sets ──────────────────────────────
  -- Starting points, not a fixed policy: a tenant may edit them or add roles
  -- (PERMISSIONS.md §2). is_system stops them being deleted.

  insert into public.roles (arena_id, code, name, is_system)
  values (v_arena_id, 'owner', 'Owner', true)
  returning id into v_owner_role_id;

  insert into public.roles (arena_id, code, name, is_system)
  values (v_arena_id, 'manager', 'Manager', true)
  returning id into v_manager_role_id;

  insert into public.roles (arena_id, code, name, is_system)
  values (v_arena_id, 'staff', 'Staff', true)
  returning id into v_staff_role_id;

  -- owner holds every code in the catalogue.
  insert into public.role_permissions (arena_id, role_id, permission_code)
  select v_arena_id, v_owner_role_id, p.code
    from public.permissions p;

  insert into public.role_permissions (arena_id, role_id, permission_code)
  select v_arena_id, v_manager_role_id, code
    from unnest(v_staff_codes || v_manager_extra_codes) as code;

  insert into public.role_permissions (arena_id, role_id, permission_code)
  select v_arena_id, v_staff_role_id, code
    from unnest(v_staff_codes) as code;

  -- ── 4. Bind the owner ──────────────────────────────────────────────────────

  insert into public.arena_users (arena_id, user_id, role_id)
  values (v_arena_id, p_owner_user_id, v_owner_role_id);

  -- ── 5. A default zone, so a tenant never faces an empty floor ──────────────
  -- A renameable default, not a fixture.

  insert into public.zones (arena_id, name, sort_order)
  values (v_arena_id, 'Main floor', 0);

  -- ── 6. A zero-rate tax rate with a single component ────────────────────────
  -- A tenant is never blocked and is never pre-assigned another jurisdiction's
  -- tax law (D31). Real rates and their splits are entered as tenant data.

  insert into public.tax_rates (arena_id, name)
  values (v_arena_id, 'No tax')
  returning id into v_tax_rate_id;

  insert into public.tax_rate_components (arena_id, tax_rate_id, name, percent, sort_order)
  values (v_arena_id, v_tax_rate_id, 'Tax', 0, 1);

  -- ── 7. Point both tax defaults at it ───────────────────────────────────────
  -- After step 6, because arena_settings carries composite foreign keys into
  -- tax_rates (DATABASE.md §15).

  update public.arena_settings
     set default_play_tax_rate_id = v_tax_rate_id,
         default_product_tax_rate_id = v_tax_rate_id
   where arena_id = v_arena_id;

  perform app.audit(
    v_arena_id,
    'arena_user.changed',
    'arena_user',
    p_owner_user_id,
    jsonb_build_object('reason', 'provisioned', 'role_code', 'owner')
  );

  return v_arena_id;
end;
$$;

comment on function public.provision_arena(uuid, text, text, text, text, uuid) is
  'Creates a fully usable arena in one transaction (DATABASE.md §15). Returns '
  'the new arena id. Seeds a zero-rate tax rate and a default zone, and no '
  'billing plans, products or station types (D33). Administrative only in M1: '
  'a self-serve path is M10.';

revoke all on function public.provision_arena(uuid, text, text, text, text, uuid)
  from public, anon, authenticated;

grant execute on function public.provision_arena(uuid, text, text, text, text, uuid)
  to service_role;
