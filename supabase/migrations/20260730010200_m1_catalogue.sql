-- M1 — floor, pricing and tax configuration.
--
-- zones · station_types · stations · games · tax_rates · tax_rate_components
-- arena_settings · billing_plans · products
--
-- Everything in this migration is tenant configuration. No rate, package price,
-- grace period, rounding increment, tax percentage or component name appears
-- here or in any function body (D31, D33). Rows come from provision_arena or
-- from a tenant holding `pricing.manage`.
--
-- Ordering matters: arena_settings carries composite foreign keys into
-- tax_rates, so tax_rates must exist first (DATABASE.md §15, step 7).
--
-- Governing: DATABASE.md §4, §5, §7 · D10, D12, D27, D31, D32, D33.

-- ── zones ────────────────────────────────────────────────────────────────────

create table public.zones (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null references public.arenas (id) on delete restrict,
  name       text        not null check (length(btrim(name)) > 0),
  sort_order int         not null default 0,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, arena_id)
);

comment on table public.zones is
  'Floor grouping. provision_arena seeds one default zone so a tenant never '
  'faces an empty floor (DATABASE.md §4).';

create unique index zones_arena_name_live_idx
  on public.zones (arena_id, name) where deleted_at is null;
create index zones_arena_updated_at_idx on public.zones (arena_id, updated_at);

create trigger zones_touch_updated_at
  before update on public.zones
  for each row execute function app.touch_updated_at();

-- ── station_types ────────────────────────────────────────────────────────────
-- Replaces the free-text stations.type: a billing plan cannot reference free
-- text, and free text violates the no-hardcoding rule (D27).

create table public.station_types (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null references public.arenas (id) on delete restrict,
  code       text        not null check (length(btrim(code)) > 0),
  name       text        not null check (length(btrim(name)) > 0),
  sort_order int         not null default 0,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, arena_id)
);

comment on table public.station_types is
  'Arena-scoped station types (D27). Codes are tenant data — provision_arena '
  'seeds none, because an empty catalogue is the correct starting state.';

create unique index station_types_arena_code_live_idx
  on public.station_types (arena_id, code) where deleted_at is null;
create index station_types_arena_updated_at_idx on public.station_types (arena_id, updated_at);

create trigger station_types_touch_updated_at
  before update on public.station_types
  for each row execute function app.touch_updated_at();

-- ── stations ─────────────────────────────────────────────────────────────────
-- No hourly_rate column: price lives on billing_plans (D10, audit C3).
-- status is the OPERATIONAL status only; play state is derived client-side and
-- stored nowhere (D06, UI_SPEC.md §3).

create table public.stations (
  id              uuid primary key default gen_random_uuid(),
  arena_id        uuid        not null references public.arenas (id) on delete restrict,
  zone_id         uuid        not null,
  station_type_id uuid        not null,
  name            text        not null check (length(btrim(name)) > 0),
  seat_capacity   int         not null default 1 check (seat_capacity >= 1),
  status          text        not null default 'active'
                    check (status in ('active', 'maintenance', 'inactive')),
  status_reason   text        null,
  sort_order      int         not null default 0,
  deleted_at      timestamptz null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, arena_id),
  constraint stations_status_reason_required
    check (status = 'active' or status_reason is not null),
  foreign key (zone_id, arena_id)
    references public.zones (id, arena_id) on delete restrict,
  foreign key (station_type_id, arena_id)
    references public.station_types (id, arena_id) on delete restrict
);

comment on column public.stations.status is
  'Operational status only: active | maintenance | inactive (D06). '
  'idle/live/ending/overtime/paused are derived by the client and never stored.';

create unique index stations_arena_name_live_idx
  on public.stations (arena_id, name) where deleted_at is null;
create index stations_arena_zone_live_idx
  on public.stations (arena_id, zone_id) where deleted_at is null;
create index stations_arena_updated_at_idx on public.stations (arena_id, updated_at);
create index stations_station_type_id_idx on public.stations (station_type_id);
create index stations_zone_id_idx on public.stations (zone_id);

create trigger stations_touch_updated_at
  before update on public.stations
  for each row execute function app.touch_updated_at();

-- ── games ────────────────────────────────────────────────────────────────────
-- station_games and session_games are not created in P0 (D28): the picker lists
-- all live games for the arena.

create table public.games (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null references public.arenas (id) on delete restrict,
  title      text        not null check (length(btrim(title)) > 0),
  rating     text        null,
  deleted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, arena_id)
);

create unique index games_arena_title_live_idx
  on public.games (arena_id, title) where deleted_at is null;
create index games_arena_updated_at_idx on public.games (arena_id, updated_at);

create trigger games_touch_updated_at
  before update on public.games
  for each row execute function app.touch_updated_at();

-- ── tax_rates ────────────────────────────────────────────────────────────────
-- A named container for one or more components. `percent` is the
-- trigger-maintained sum of live components and is never written by a client
-- (D31). Components are the source of truth.

create table public.tax_rates (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid           not null references public.arenas (id) on delete restrict,
  name       text           not null check (length(btrim(name)) > 0),
  percent    numeric(5, 2)  not null default 0 check (percent >= 0 and percent <= 100),
  deleted_at timestamptz    null,
  created_at timestamptz    not null default now(),
  updated_at timestamptz    not null default now(),
  unique (id, arena_id)
);

comment on column public.tax_rates.percent is
  'Trigger-maintained sum of live tax_rate_components (D31). Never written '
  'directly. An order line snapshots the rate, so editing it changes future '
  'orders only.';

create unique index tax_rates_arena_name_live_idx
  on public.tax_rates (arena_id, name) where deleted_at is null;
create index tax_rates_arena_updated_at_idx on public.tax_rates (arena_id, updated_at);

create trigger tax_rates_touch_updated_at
  before update on public.tax_rates
  for each row execute function app.touch_updated_at();

-- ── tax_rate_components ──────────────────────────────────────────────────────
-- CGST + SGST, a single IGST, a single VAT line, or anything else a
-- jurisdiction needs: all of it is tenant data (D31).

create table public.tax_rate_components (
  id          uuid primary key default gen_random_uuid(),
  arena_id    uuid          not null references public.arenas (id) on delete restrict,
  tax_rate_id uuid          not null,
  name        text          not null check (length(btrim(name)) > 0),
  percent     numeric(5, 2) not null check (percent >= 0 and percent <= 100),
  sort_order  int           not null default 0,
  deleted_at  timestamptz   null,
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now(),
  unique (id, arena_id),
  foreign key (tax_rate_id, arena_id)
    references public.tax_rates (id, arena_id) on delete restrict
);

comment on table public.tax_rate_components is
  'The source of truth for a rate''s value (D31). sort_order drives both '
  'display and the deterministic largest-remainder allocation of odd minor '
  'units (DATABASE.md §10).';

create unique index tax_rate_components_arena_rate_name_live_idx
  on public.tax_rate_components (arena_id, tax_rate_id, name) where deleted_at is null;
create index tax_rate_components_tax_rate_id_idx on public.tax_rate_components (tax_rate_id);
create index tax_rate_components_arena_updated_at_idx
  on public.tax_rate_components (arena_id, updated_at);

create trigger tax_rate_components_touch_updated_at
  before update on public.tax_rate_components
  for each row execute function app.touch_updated_at();

create function app.sync_tax_rate_percent()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
declare
  v_arena_id    uuid;
  v_rate_id     uuid;
  v_sum         numeric(12, 2);
  v_live_count  int;
  v_rate_live   boolean;
begin
  v_arena_id := coalesce(new.arena_id, old.arena_id);
  v_rate_id  := coalesce(new.tax_rate_id, old.tax_rate_id);

  select coalesce(sum(c.percent), 0), count(*)
    into v_sum, v_live_count
    from public.tax_rate_components c
   where c.tax_rate_id = v_rate_id
     and c.arena_id = v_arena_id
     and c.deleted_at is null;

  select (r.deleted_at is null)
    into v_rate_live
    from public.tax_rates r
   where r.id = v_rate_id and r.arena_id = v_arena_id;

  -- Fail with a readable message rather than tripping the percent <= 100 CHECK
  -- on tax_rates (DATABASE.md §5).
  if v_sum > 100 then
    raise exception
      'validation_failed: tax rate components sum to %, which exceeds 100', v_sum
      using errcode = 'P0001';
  end if;

  -- A live rate must keep at least one live component. A jurisdiction with no
  -- split configures a single component (D31).
  if v_live_count = 0 and coalesce(v_rate_live, false) then
    raise exception
      'validation_failed: a tax rate must keep at least one live component'
      using errcode = 'P0001';
  end if;

  update public.tax_rates
     set percent = v_sum
   where id = v_rate_id
     and arena_id = v_arena_id
     and percent is distinct from v_sum;

  return null;
end;
$$;

comment on function app.sync_tax_rate_percent() is
  'Keeps tax_rates.percent equal to the sum of its live components and refuses '
  'to leave a live rate with none (D31, SECURITY.md §15 assertion 18).';

create trigger tax_rate_components_sync_percent
  after insert or update or delete on public.tax_rate_components
  for each row execute function app.sync_tax_rate_percent();

-- ── arena_settings ───────────────────────────────────────────────────────────
-- One row per arena, PRIMARY KEY (arena_id), no id: it is 1:1 with the arena
-- and nothing references it (DATABASE.md §1.3).
--
-- Every value a tenant can differ on lives here. Nothing here is hardcoded in
-- Flutter or in a function body.

create table public.arena_settings (
  arena_id                           uuid        primary key
                                       references public.arenas (id) on delete restrict,
  business_day_start_time            time        not null default '06:00',
  prices_include_tax                 boolean     not null default true,
  default_play_tax_rate_id           uuid        null,
  default_product_tax_rate_id        uuid        null,
  receipt_prefix                     text        not null default '',
  receipt_series_mode                text        not null default 'fixed'
    check (receipt_series_mode in ('fixed', 'monthly', 'yearly', 'financial_yearly')),
  receipt_fixed_series               text        not null default '',
  receipt_financial_year_start_month int         not null default 1
    check (receipt_financial_year_start_month between 1 and 12),
  receipt_number_format              text        not null default '{prefix}{series}{sequence}',
  receipt_number_padding             int         not null default 6
    check (receipt_number_padding between 0 and 20),
  default_phone_dial_code            text        not null
    check (default_phone_dial_code ~ '^\+[1-9][0-9]{0,3}$'),
  low_stock_enabled                  boolean     not null default true,
  ending_threshold_minutes           int         not null default 10
    check (ending_threshold_minutes >= 0),
  max_clock_skew_minutes             int         not null default 15
    check (max_clock_skew_minutes >= 0),
  created_at                         timestamptz not null default now(),
  updated_at                         timestamptz not null default now(),
  foreign key (default_play_tax_rate_id, arena_id)
    references public.tax_rates (id, arena_id) on delete restrict,
  foreign key (default_product_tax_rate_id, arena_id)
    references public.tax_rates (id, arena_id) on delete restrict
);

comment on table public.arena_settings is
  'Per-tenant configuration. Business day, tax mode, receipt numbering policy '
  'and phone dial code all live here so no jurisdiction is compiled into code '
  '(D09, D31, D32, D36).';
comment on column public.arena_settings.receipt_series_mode is
  'fixed | monthly | yearly | financial_yearly. A financial-year rollover is '
  'configuration, never a code change (D13 as amended by D31).';
comment on column public.arena_settings.prices_include_tax is
  'When true every configured price is the final price the customer pays and '
  'tax is extracted from it (D32). Both branches are supported.';

create index arena_settings_default_play_tax_rate_id_idx
  on public.arena_settings (default_play_tax_rate_id);
create index arena_settings_default_product_tax_rate_id_idx
  on public.arena_settings (default_product_tax_rate_id);

create trigger arena_settings_touch_updated_at
  before update on public.arena_settings
  for each row execute function app.touch_updated_at();

-- ── billing_plans ────────────────────────────────────────────────────────────
-- Exactly two plan types in P0 (D10). pricing_rules is not created.

create table public.billing_plans (
  id                         uuid primary key default gen_random_uuid(),
  arena_id                   uuid           not null references public.arenas (id) on delete restrict,
  station_type_id            uuid           null,
  name                       text           not null check (length(btrim(name)) > 0),
  type                       text           not null check (type in ('open_time', 'fixed_duration')),
  hourly_rate                numeric(12, 2) null,
  duration_minutes           int            null,
  fixed_price                numeric(12, 2) null,
  grace_minutes              int            not null default 0 check (grace_minutes >= 0),
  rounding_increment_minutes int            not null default 1
    check (rounding_increment_minutes >= 1),
  rounding_mode              text           not null default 'up'
    check (rounding_mode in ('up', 'nearest', 'down')),
  minimum_billable_minutes   int            not null default 0
    check (minimum_billable_minutes >= 0),
  sort_order                 int            not null default 0,
  deleted_at                 timestamptz    null,
  created_at                 timestamptz    not null default now(),
  updated_at                 timestamptz    not null default now(),
  unique (id, arena_id),
  constraint billing_plans_shape check (
    (type = 'open_time'
       and hourly_rate is not null and hourly_rate >= 0
       and duration_minutes is null and fixed_price is null)
    or
    (type = 'fixed_duration'
       and duration_minutes is not null and duration_minutes > 0
       and fixed_price is not null and fixed_price >= 0
       and hourly_rate is null)
  ),
  foreign key (station_type_id, arena_id)
    references public.station_types (id, arena_id) on delete restrict
);

comment on table public.billing_plans is
  'open_time (hourly) and fixed_duration (package) only in P0 (D10). '
  'station_type_id null means the plan applies to every station type.';
comment on column public.billing_plans.rounding_increment_minutes is
  'open_time only. For a package the block IS the increment (DATABASE.md §9).';
comment on column public.billing_plans.minimum_billable_minutes is
  'open_time only. For a package the block IS the minimum (DATABASE.md §9).';
comment on column public.billing_plans.grace_minutes is
  'Applies to both types at different boundaries: total elapsed for open_time, '
  'the overrun for fixed_duration (DATABASE.md §9, audit §10).';

create unique index billing_plans_arena_name_live_idx
  on public.billing_plans (arena_id, name) where deleted_at is null;
create index billing_plans_station_type_id_idx on public.billing_plans (station_type_id);
create index billing_plans_arena_updated_at_idx on public.billing_plans (arena_id, updated_at);

create trigger billing_plans_touch_updated_at
  before update on public.billing_plans
  for each row execute function app.touch_updated_at();

-- ── products ─────────────────────────────────────────────────────────────────
-- No stock column: stock is derived from signed movements (D20).

create table public.products (
  id                  uuid primary key default gen_random_uuid(),
  arena_id            uuid            not null references public.arenas (id) on delete restrict,
  name                text            not null check (length(btrim(name)) > 0),
  sku                 text            null,
  selling_price       numeric(12, 2)  not null check (selling_price >= 0),
  cost_price          numeric(12, 2)  null check (cost_price is null or cost_price >= 0),
  tax_rate_id         uuid            null,
  low_stock_threshold numeric(12, 3)  not null default 0,
  deleted_at          timestamptz     null,
  created_at          timestamptz     not null default now(),
  updated_at          timestamptz     not null default now(),
  unique (id, arena_id),
  foreign key (tax_rate_id, arena_id)
    references public.tax_rates (id, arena_id) on delete restrict
);

comment on column public.products.selling_price is
  'Tax treatment follows arena_settings.prices_include_tax (D32). Under the '
  'inclusive mode this is the final price the customer pays.';
comment on column public.products.tax_rate_id is
  'Overrides arena_settings.default_product_tax_rate_id when set (D12).';

create unique index products_arena_name_live_idx
  on public.products (arena_id, name) where deleted_at is null;
create unique index products_arena_sku_live_idx
  on public.products (arena_id, sku) where sku is not null and deleted_at is null;
create index products_tax_rate_id_idx on public.products (tax_rate_id);
create index products_arena_updated_at_idx on public.products (arena_id, updated_at);

create trigger products_touch_updated_at
  before update on public.products
  for each row execute function app.touch_updated_at();
