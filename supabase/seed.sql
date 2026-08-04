-- Fixture seed — development and staging only.
--
-- NOT a migration. This file never runs against production: `supabase db reset`
-- only ever targets the local stack, migrations are the only sanctioned path to
-- a remote database, and `scripts/db.sh seed` refuses the production
-- environment outright (D33, D34).
--
-- Two things happen here, and they are different:
--
--   1. A tenant is created through provision_arena — the same call any other
--      tenant uses. Nothing about it is compiled into the product; the values
--      below are seed parameters, overridable per environment.
--
--   2. `[FIXTURE]`-prefixed pricing, tax and catalogue rows are added. These are
--      the test vectors in DATABASE.md §16, not commercial rates. The prefix
--      exists so they can never be mistaken for real configuration, and real
--      production pricing is entered by a tenant user before M4 acceptance (D33).
--
-- Overridable settings, all with a pilot-shaped default:
--
--   arena_os.seed_organization_name   arena_os.seed_arena_name
--   arena_os.seed_timezone            arena_os.seed_currency
--   arena_os.seed_dial_code           arena_os.seed_password
--
-- arena_os.seed_password is empty by default, which creates accounts that
-- cannot sign in with a password. Supply one explicitly for an environment
-- where you need to sign in (see scripts/db.sh seed).

do $seed$
declare
  v_org_name  text := coalesce(current_setting('arena_os.seed_organization_name', true), '404 Labs');
  v_name      text := coalesce(current_setting('arena_os.seed_arena_name', true), '404 Arena');
  v_timezone  text := coalesce(current_setting('arena_os.seed_timezone', true), 'Asia/Kolkata');
  v_currency  text := coalesce(current_setting('arena_os.seed_currency', true), 'INR');
  v_dial_code text := coalesce(current_setting('arena_os.seed_dial_code', true), '+91');
  v_password  text := coalesce(current_setting('arena_os.seed_password', true), '');

  v_org_id   uuid := '5eed0000-0000-4000-8000-000000000001';
  v_owner    uuid := '5eed0000-0000-4000-8000-00000000000a';
  v_manager  uuid := '5eed0000-0000-4000-8000-00000000000b';
  v_staff    uuid := '5eed0000-0000-4000-8000-00000000000c';

  v_arena_id      uuid;
  v_zone_id       uuid;
  v_type_pc       uuid;
  v_type_console  uuid;
  v_rate_intra    uuid;
  v_rate_inter    uuid;
  v_product_id    uuid;
  v_user          record;
  v_station       record;
begin
  -- ── Guards ─────────────────────────────────────────────────────────────────

  if exists (select 1 from public.payments)
     or exists (select 1 from public.orders where status = 'settled') then
    raise exception
      'refusing to seed: this database already holds settled orders or payments. '
      'Fixture data belongs in development and staging only (D33, D34).';
  end if;

  if exists (select 1 from public.arenas a where a.name = v_name) then
    raise notice 'seed: "%" already exists, nothing to do', v_name;
    return;
  end if;

  -- ── Staff accounts ─────────────────────────────────────────────────────────

  for v_user in
    select * from (values
      (v_owner,   'owner@arena-os.local',   'Seed Owner',   'owner'),
      (v_manager, 'manager@arena-os.local', 'Seed Manager', 'manager'),
      (v_staff,   'staff@arena-os.local',   'Seed Staff',   'staff')
    ) as u(id, email, display_name, role_code)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change, reauthentication_token
    )
    values (
      '00000000-0000-0000-0000-000000000000', v_user.id, 'authenticated', 'authenticated',
      v_user.email,
      case when v_password = '' then ''
           else extensions.crypt(v_password, extensions.gen_salt('bf')) end,
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('display_name', v_user.display_name),
      now(), now(),
      '', '', '', '', ''
    )
    on conflict (id) do nothing;

    insert into auth.identities (
      id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    )
    values (
      gen_random_uuid(), v_user.id::text, v_user.id,
      jsonb_build_object('sub', v_user.id::text, 'email', v_user.email, 'email_verified', true),
      'email', now(), now(), now()
    )
    on conflict do nothing;

    insert into public.profiles (id, display_name)
    values (v_user.id, v_user.display_name)
    on conflict (id) do nothing;
  end loop;

  insert into public.organizations (id, name)
  values (v_org_id, v_org_name)
  on conflict (id) do nothing;

  -- ── The tenant, through the same call any other tenant uses ────────────────

  v_arena_id := public.provision_arena(
    v_org_id, v_name, v_timezone, v_currency, v_dial_code, v_owner
  );

  for v_user in
    select * from (values (v_manager, 'manager'), (v_staff, 'staff')) as u(id, role_code)
  loop
    insert into public.arena_users (arena_id, user_id, role_id)
    select v_arena_id, v_user.id, r.id
      from public.roles r
     where r.arena_id = v_arena_id and r.code = v_user.role_code;
  end loop;

  -- ── §16.1 fixture arena configuration ──────────────────────────────────────
  -- Tax-inclusive pricing and a financial-year receipt series, both expressed
  -- as rows (D31, D32).

  update public.arena_settings
     set prices_include_tax = true,
         business_day_start_time = '06:00',
         receipt_prefix = 'FIX/',
         receipt_series_mode = 'financial_yearly',
         receipt_financial_year_start_month = 4,
         receipt_number_format = '{prefix}{series}/{sequence}',
         receipt_number_padding = 6
   where arena_id = v_arena_id;

  -- ── §16.2 fixture tax rates ────────────────────────────────────────────────
  -- Two shapes, so the multi-component schema is exercised both ways. P0 never
  -- selects the inter-state rate automatically: place-of-supply resolution is
  -- post-MVP (D31).

  insert into public.tax_rates (arena_id, name)
  values (v_arena_id, '[FIXTURE] GST 18% (Intra-state)')
  returning id into v_rate_intra;

  insert into public.tax_rate_components (arena_id, tax_rate_id, name, percent, sort_order)
  values (v_arena_id, v_rate_intra, 'CGST', 9.00, 1),
         (v_arena_id, v_rate_intra, 'SGST', 9.00, 2);

  insert into public.tax_rates (arena_id, name)
  values (v_arena_id, '[FIXTURE] GST 18% (Inter-state)')
  returning id into v_rate_inter;

  insert into public.tax_rate_components (arena_id, tax_rate_id, name, percent, sort_order)
  values (v_arena_id, v_rate_inter, 'IGST', 18.00, 1);

  update public.arena_settings
     set default_play_tax_rate_id = v_rate_intra,
         default_product_tax_rate_id = v_rate_intra
   where arena_id = v_arena_id;

  -- ── A fixture floor ────────────────────────────────────────────────────────

  select id into v_zone_id from public.zones where arena_id = v_arena_id limit 1;

  insert into public.station_types (arena_id, code, name, sort_order)
  values (v_arena_id, 'fixture_pc', '[FIXTURE] PC', 1)
  returning id into v_type_pc;

  insert into public.station_types (arena_id, code, name, sort_order)
  values (v_arena_id, 'fixture_console', '[FIXTURE] Console', 2)
  returning id into v_type_console;

  for v_station in
    select * from (values
      ('[FIXTURE] PC-01', 1), ('[FIXTURE] PC-02', 2), ('[FIXTURE] PC-03', 3)
    ) as s(name, sort_order)
  loop
    insert into public.stations (arena_id, zone_id, station_type_id, name, sort_order)
    values (v_arena_id, v_zone_id, v_type_pc, v_station.name, v_station.sort_order);
  end loop;

  insert into public.stations (arena_id, zone_id, station_type_id, name, seat_capacity, sort_order)
  values (v_arena_id, v_zone_id, v_type_console, '[FIXTURE] Console-01', 4, 4);

  insert into public.games (arena_id, title)
  values (v_arena_id, '[FIXTURE] Game One'), (v_arena_id, '[FIXTURE] Game Two');

  -- ── §16.3 fixture billing plans ────────────────────────────────────────────
  -- Test vectors, not commercial rates. Expected outputs: DATABASE.md §16.4.

  insert into public.billing_plans (
    arena_id, station_type_id, name, type, hourly_rate,
    grace_minutes, minimum_billable_minutes, rounding_increment_minutes, rounding_mode, sort_order
  )
  values (v_arena_id, v_type_pc, '[FIXTURE] PC Open Play', 'open_time', 120.00,
          5, 30, 15, 'up', 1);

  insert into public.billing_plans (
    arena_id, station_type_id, name, type, duration_minutes, fixed_price,
    grace_minutes, sort_order
  )
  values (v_arena_id, v_type_console, '[FIXTURE] Console 1-Hour Pack', 'fixed_duration',
          60, 150.00, 5, 2);

  -- ── Fixture products, with opening stock ───────────────────────────────────

  for v_user in
    select * from (values
      ('[FIXTURE] Cola', 'FIX-COLA', 100.00), ('[FIXTURE] Crisps', 'FIX-CRISP', 50.00)
    ) as p(name, sku, price)
  loop
    insert into public.products (arena_id, name, sku, selling_price, low_stock_threshold)
    values (v_arena_id, v_user.name, v_user.sku, v_user.price, 5)
    returning id into v_product_id;

    insert into public.inventory_movements (
      id, arena_id, product_id, type, quantity, actor_user_id, business_date, note
    )
    values (gen_random_uuid(), v_arena_id, v_product_id, 'opening', 24.000, v_owner,
            app.business_date(v_arena_id, now()), 'Fixture opening stock');
  end loop;

  -- Epic 5 gate: settle requires an open shift (D08). Until Epic 6 shift RPCs,
  -- seed opens one so local trading / checkout can be exercised end-to-end.
  insert into public.shifts (
    id, arena_id, business_date, status, opened_by_user_id, opened_at, opening_float
  )
  values (
    '5eed0000-0000-4000-8000-0000000000f1',
    v_arena_id,
    app.business_date(v_arena_id, now()),
    'open',
    v_owner,
    now(),
    500.00
  )
  on conflict do nothing;

  raise notice 'seed: "%" provisioned as % with [FIXTURE] pricing', v_name, v_arena_id;
end;
$seed$;
