-- M1 — provision_arena.
--
-- A tenant must be creatable with no code change and no manual SQL. That is
-- M10's acceptance criterion, but the function it depends on lands in M1, so it
-- is proved here (DATABASE.md §15).

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(16);

insert into auth.users (id, email)
values ('cccc0000-0000-4000-8000-0000000000c9', 'c.owner@arena-os.test');
insert into public.profiles (id, display_name)
values ('cccc0000-0000-4000-8000-0000000000c9', 'C Owner');
insert into public.organizations (id, name)
values ('cccc0000-0000-4000-8000-0000000000f3', 'Organisation Three');

select public.provision_arena(
  'cccc0000-0000-4000-8000-0000000000f3', 'Arena C', 'America/New_York', 'CAD', '+1',
  'cccc0000-0000-4000-8000-0000000000c9'
) as arena_c \gset

-- ── What a new tenant receives ───────────────────────────────────────────────

select is(
  (select count(*) from public.arena_settings where arena_id = :'arena_c')::int, 1,
  'a settings row is created with the arena (step 2)'
);

select results_eq(
  format(
    $$ select code, is_system from public.roles where arena_id = %L order by code $$,
    :'arena_c'
  ),
  $$ values ('manager', true), ('owner', true), ('staff', true) $$,
  'the three system roles are seeded and cannot be deleted (step 3, PERMISSIONS.md §2)'
);

select results_eq(
  format(
    $$ select r.code, count(rp.permission_code)::int
         from public.roles r
         left join public.role_permissions rp on rp.role_id = r.id
        where r.arena_id = %L
        group by r.code order by r.code $$,
    :'arena_c'
  ),
  $$ values ('manager', 29), ('owner', 33), ('staff', 16) $$,
  'the seeded permission sets match PERMISSIONS.md §2 exactly'
);

select is_empty(
  format(
    $$ select rp.permission_code
         from public.role_permissions rp
         join public.roles r on r.id = rp.role_id
        where r.arena_id = %L and r.code = 'staff'
          and rp.permission_code in ('report.view', 'discount.apply', 'order.void',
                                     'shift.close', 'pricing.manage', 'permissions.manage') $$,
    :'arena_c'
  ),
  'the staff role holds none of the manager or owner codes'
);

select results_eq(
  format(
    $$ select r.code from public.arena_users au
         join public.roles r on r.id = au.role_id
        where au.arena_id = %L and au.user_id = %L and au.active $$,
    :'arena_c', 'cccc0000-0000-4000-8000-0000000000c9'
  ),
  $$ values ('owner') $$,
  'the owner is bound to the owner role (step 4)'
);

select is(
  (select count(*) from public.zones where arena_id = :'arena_c')::int, 1,
  'a default zone exists, so a tenant never faces an empty floor (step 5)'
);

select results_eq(
  format(
    $$ select tr.name, tr.percent, c.name, c.percent
         from public.tax_rates tr
         join public.tax_rate_components c on c.tax_rate_id = tr.id
        where tr.arena_id = %L $$,
    :'arena_c'
  ),
  $$ values ('No tax', 0.00::numeric(5,2), 'Tax', 0.00::numeric(5,2)) $$,
  'a zero rate with a single component is seeded — never another jurisdiction''s '
  'tax law (step 6, D31)'
);

select results_eq(
  format(
    $$ select default_play_tax_rate_id = default_product_tax_rate_id,
              default_play_tax_rate_id is not null
         from public.arena_settings where arena_id = %L $$,
    :'arena_c'
  ),
  $$ values (true, true) $$,
  'both tax defaults point at the seeded rate, after it exists (step 7)'
);

-- ── What a new tenant deliberately does NOT receive ──────────────────────────

select is_empty(
  format(
    $$ select 'billing_plans' from public.billing_plans where arena_id = %L
       union all select 'products' from public.products where arena_id = %L
       union all select 'station_types' from public.station_types where arena_id = %L
       union all select 'games' from public.games where arena_id = %L
       union all select 'stations' from public.stations where arena_id = %L $$,
    :'arena_c', :'arena_c', :'arena_c', :'arena_c', :'arena_c'
  ),
  'no billing plans, products, station types, games or stations: pricing and the '
  'catalogue are tenant configuration (D33, DATABASE.md §15)'
);

select is_empty(
  format($$ select series from public.receipt_counters where arena_id = %L $$, :'arena_c'),
  'receipt_counters rows are not pre-created — order_settle inserts one the first '
  'time a series is used, so any receipt_series_mode works (§10)'
);

select results_eq(
  format(
    $$ select action, entity_type from public.audit_logs where arena_id = %L $$,
    :'arena_c'
  ),
  $$ values ('arena_user.changed', 'arena_user') $$,
  'binding the owner is audited, like every other change to access (D22)'
);

-- ── Validation ───────────────────────────────────────────────────────────────

select throws_like(
  $$ select public.provision_arena('cccc0000-0000-4000-8000-0000000000f3', 'Bad tz',
       'Mars/Olympus', 'CAD', '+1', 'cccc0000-0000-4000-8000-0000000000c9') $$,
  'validation_failed:%',
  'an unknown IANA timezone is rejected'
);

select throws_like(
  $$ select public.provision_arena('cccc0000-0000-4000-8000-0000000000f3', 'Bad currency',
       'UTC', 'rupees', '+1', 'cccc0000-0000-4000-8000-0000000000c9') $$,
  'validation_failed:%',
  'a currency that is not an ISO 4217 code is rejected'
);

select throws_like(
  $$ select public.provision_arena('cccc0000-0000-4000-8000-0000000000f3', 'Bad dial code',
       'UTC', 'CAD', '0091', 'cccc0000-0000-4000-8000-0000000000c9') $$,
  'validation_failed:%',
  'a dial code that is not in +NN form is rejected'
);

select throws_like(
  $$ select public.provision_arena('cccc0000-0000-4000-8000-0000000000f3', 'No such owner',
       'UTC', 'CAD', '+1', '00000000-0000-4000-8000-000000000000') $$,
  'not_found:%',
  'the owner must already have a profile'
);

-- ── The new tenant is isolated from the existing ones ────────────────────────

select pg_temp.become('cccc0000-0000-4000-8000-0000000000c9');
set local role authenticated;

select is_empty(
  format(
    $$ select 'arenas' from public.arenas where id <> %L
       union all select 'stations' from public.stations
       union all select 'sessions' from public.sessions
       union all select 'orders'   from public.orders
       union all select 'payments' from public.payments $$,
    :'arena_c'
  ),
  'the freshly provisioned tenant observes nothing of the tenants that already '
  'existed — provisioning creates a genuinely isolated arena'
);

reset role;
select * from finish();
rollback;
