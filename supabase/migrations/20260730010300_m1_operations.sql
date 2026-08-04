-- M1 — operational and financial tables.
--
-- members · shifts · sessions · orders · order_items · payments
-- product_stock · inventory_movements · receipt_counters · idempotency_keys
-- audit_logs
--
-- Money is numeric(12,2) throughout. There is no float, real, double precision
-- or money column anywhere in this schema (D01).
--
-- Governing: DATABASE.md §6–§12 · SECURITY.md §5, §8, §10 · D01, D07, D08,
-- D09, D16, D19, D20, D21, D22, D30.

-- ── members ──────────────────────────────────────────────────────────────────
-- The only personal data in the system. `authenticated` gets no SELECT
-- privilege at all — that is a revoked privilege, not a policy (SECURITY.md §8).

create table public.members (
  id                 uuid primary key,
  arena_id           uuid        not null references public.arenas (id) on delete restrict,
  full_name          text        not null check (length(btrim(full_name)) > 0),
  phone              text        not null check (phone ~ '^\+[1-9][0-9]{6,14}$'),
  dob                date        null,
  blocked            boolean     not null default false,
  blocked_reason     text        null,
  notes              text        null,
  created_by_user_id uuid        not null references public.profiles (id) on delete restrict,
  deleted_at         timestamptz null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (id, arena_id),
  constraint members_blocked_reason_required
    check (blocked = false or blocked_reason is not null)
);

comment on table public.members is
  'Client-generated id (D17). Never replicated to a device and excluded from '
  'sync_pull (D19). All reads go through RPCs.';
comment on column public.members.phone is
  'Canonical E.164, normalised server-side by app.normalise_phone using the '
  'arena''s dial code (D36). Uniqueness is on the canonical form, so two '
  'spellings of one number cannot both exist.';

create unique index members_arena_phone_live_idx
  on public.members (arena_id, phone) where deleted_at is null;
create index members_arena_full_name_trgm_idx
  on public.members using gin (arena_id, full_name extensions.gin_trgm_ops)
  where deleted_at is null;
create index members_created_by_user_id_idx on public.members (created_by_user_id);
create index members_arena_updated_at_idx on public.members (arena_id, updated_at);

create trigger members_touch_updated_at
  before update on public.members
  for each row execute function app.touch_updated_at();

-- ── shifts ───────────────────────────────────────────────────────────────────
-- Payments own the shift (D08). One open shift per arena (D30).

create table public.shifts (
  id                 uuid primary key default gen_random_uuid(),
  arena_id           uuid           not null references public.arenas (id) on delete restrict,
  business_date      date           not null,
  status             text           not null check (status in ('open', 'closed')),
  opened_by_user_id  uuid           not null references public.profiles (id) on delete restrict,
  opened_at          timestamptz    not null,
  opening_float      numeric(12, 2) not null check (opening_float >= 0),
  closed_by_user_id  uuid           null references public.profiles (id) on delete restrict,
  closed_at          timestamptz    null,
  expected_cash      numeric(12, 2) null,
  counted_cash       numeric(12, 2) null,
  variance           numeric(12, 2) generated always as (counted_cash - expected_cash) stored,
  notes              text           null,
  created_at         timestamptz    not null default now(),
  updated_at         timestamptz    not null default now(),
  unique (id, arena_id),
  constraint shifts_closed_shape check (
    status = 'open'
    or (closed_at is not null and closed_by_user_id is not null
        and expected_cash is not null and counted_cash is not null)
  )
);

comment on table public.shifts is
  'Cash reconciliation follows payments.shift_id, never session ownership (D08). '
  'Cash paid out of the drawer is not modelled in P0 and shows as negative '
  'variance (D29).';

create unique index shifts_one_open_per_arena
  on public.shifts (arena_id) where status = 'open';
create index shifts_arena_business_date_idx on public.shifts (arena_id, business_date);
create index shifts_arena_updated_at_idx on public.shifts (arena_id, updated_at);
create index shifts_opened_by_user_id_idx on public.shifts (opened_by_user_id);
create index shifts_closed_by_user_id_idx on public.shifts (closed_by_user_id);

create trigger shifts_touch_updated_at
  before update on public.shifts
  for each row execute function app.touch_updated_at();

create trigger shifts_business_date_immutable
  before update on public.shifts
  for each row execute function app.forbid_business_date_change();

create function app.shifts_guard_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  if old.status = 'closed' then
    -- A closed shift is a financial record. Nothing about it moves afterwards.
    if (to_jsonb(new) - 'updated_at' - 'variance')
       is distinct from (to_jsonb(old) - 'updated_at' - 'variance') then
      raise exception 'invalid_state: a closed shift is immutable (D21)'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

comment on function app.shifts_guard_transition() is
  'open -> closed is the only shift transition, and closed is terminal '
  '(API.md §8). Enforced in the database as well as in the RPC.';

create trigger shifts_guard_transition
  before update on public.shifts
  for each row execute function app.shifts_guard_transition();

-- ── sessions ─────────────────────────────────────────────────────────────────
-- Stored status is exhaustively active | paused | completed | cancelled (D06).
-- Presentation state is derived by the client and stored nowhere.

create table public.sessions (
  id                   uuid primary key,
  arena_id             uuid        not null references public.arenas (id) on delete restrict,
  station_id           uuid        not null,
  member_id            uuid        null,
  game_id              uuid        null,
  billing_plan_id      uuid        not null,
  opened_in_shift_id   uuid        null,
  status               text        not null
    check (status in ('active', 'paused', 'completed', 'cancelled')),
  player_count         int         not null default 1 check (player_count >= 1),
  started_by_user_id   uuid        not null references public.profiles (id) on delete restrict,
  started_at           timestamptz not null,
  planned_end_at       timestamptz null,
  paused_at            timestamptz null,
  total_paused_seconds int         not null default 0 check (total_paused_seconds >= 0),
  ended_by_user_id     uuid        null references public.profiles (id) on delete restrict,
  ended_at             timestamptz null,
  end_reason           text        null
    check (end_reason is null or end_reason in ('normal', 'cancelled', 'no_show')),
  pricing_snapshot     jsonb       not null,
  client_created_at    timestamptz null,
  business_date        date        not null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (id, arena_id),
  constraint sessions_paused_shape check ((status = 'paused') = (paused_at is not null)),
  constraint sessions_terminal_shape check (
    status not in ('completed', 'cancelled')
    or (ended_at is not null and ended_by_user_id is not null and end_reason is not null)
  ),
  constraint sessions_ended_after_started check (ended_at is null or ended_at >= started_at),
  foreign key (station_id, arena_id)
    references public.stations (id, arena_id) on delete restrict,
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete restrict,
  foreign key (game_id, arena_id)
    references public.games (id, arena_id) on delete restrict,
  foreign key (billing_plan_id, arena_id)
    references public.billing_plans (id, arena_id) on delete restrict,
  foreign key (opened_in_shift_id, arena_id)
    references public.shifts (id, arena_id) on delete restrict
);

comment on column public.sessions.opened_in_shift_id is
  'Informational only. Never appears in a cash or revenue calculation — that '
  'follows payments.shift_id (D08).';
comment on column public.sessions.pricing_snapshot is
  'Captured at session_start and never modified (D11). Billing reads the '
  'snapshot, so editing a plan cannot change a historical bill.';
comment on column public.sessions.planned_end_at is
  'Set for fixed_duration plans, null for open_time. Open-time sessions '
  'therefore never render ending or overtime (D06).';

-- This one constraint is what makes concurrent and offline session starts safe
-- (OFFLINE.md §4). Removing it reintroduces station double-booking.
create unique index sessions_one_live_per_station
  on public.sessions (station_id) where status in ('active', 'paused');

create index sessions_arena_station_live_idx
  on public.sessions (arena_id, station_id) where status in ('active', 'paused');
create index sessions_arena_business_date_completed_idx
  on public.sessions (arena_id, business_date) where status = 'completed';
create index sessions_arena_updated_at_idx on public.sessions (arena_id, updated_at);
create index sessions_member_id_idx on public.sessions (member_id);
create index sessions_game_id_idx on public.sessions (game_id);
create index sessions_billing_plan_id_idx on public.sessions (billing_plan_id);
create index sessions_opened_in_shift_id_idx on public.sessions (opened_in_shift_id);
create index sessions_started_by_user_id_idx on public.sessions (started_by_user_id);
create index sessions_ended_by_user_id_idx on public.sessions (ended_by_user_id);

create trigger sessions_touch_updated_at
  before update on public.sessions
  for each row execute function app.touch_updated_at();

create trigger sessions_business_date_immutable
  before update on public.sessions
  for each row execute function app.forbid_business_date_change();

create function app.sessions_guard_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status in ('completed', 'cancelled') then
    raise exception 'invalid_state: session % is terminal (%) and cannot move to %',
      old.id, old.status, new.status
      using errcode = 'P0001';
  end if;

  if old.status = 'active' and new.status not in ('paused', 'completed', 'cancelled') then
    raise exception 'invalid_state: session % cannot move from active to %', old.id, new.status
      using errcode = 'P0001';
  end if;

  if old.status = 'paused' and new.status not in ('active', 'completed', 'cancelled') then
    raise exception 'invalid_state: session % cannot move from paused to %', old.id, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function app.sessions_guard_transition() is
  'active -> paused|completed|cancelled, paused -> active|completed|cancelled, '
  'completed and cancelled terminal (DATABASE.md §9). The RPCs enforce this too; '
  'the trigger is layer 4 (SECURITY.md §1).';

create trigger sessions_guard_transition
  before update on public.sessions
  for each row execute function app.sessions_guard_transition();

-- ── orders ───────────────────────────────────────────────────────────────────
-- No shift_id column: a shift column on the order invites incorrect
-- reconciliation (D08).

create table public.orders (
  id                              uuid primary key,
  arena_id                        uuid           not null
                                    references public.arenas (id) on delete restrict,
  session_id                      uuid           null,
  member_id                       uuid           null,
  status                          text           not null
    check (status in ('open', 'settled', 'void')),
  subtotal                        numeric(12, 2) not null default 0,
  discount_kind                   text           null
    check (discount_kind is null or discount_kind in ('flat', 'percent')),
  discount_value                  numeric(12, 2) null
    check (discount_value is null or discount_value >= 0),
  discount_total                  numeric(12, 2) not null default 0 check (discount_total >= 0),
  discount_reason                 text           null,
  discount_authorised_by_user_id  uuid           null
                                    references public.profiles (id) on delete restrict,
  tax_total                       numeric(12, 2) not null default 0,
  total                           numeric(12, 2) not null default 0,
  paid_total                      numeric(12, 2) not null default 0,
  balance_due                     numeric(12, 2) generated always as (total - paid_total) stored,
  receipt_sequence                bigint         null,
  receipt_number                  text           null,
  void_reason                     text           null,
  opened_by_user_id               uuid           not null
                                    references public.profiles (id) on delete restrict,
  settled_by_user_id              uuid           null
                                    references public.profiles (id) on delete restrict,
  settled_at                      timestamptz    null,
  business_date                   date           not null,
  created_at                      timestamptz    not null default now(),
  updated_at                      timestamptz    not null default now(),
  unique (id, arena_id),
  constraint orders_discount_shape check (
    discount_kind is null
    or (discount_value is not null
        and discount_reason is not null
        and discount_authorised_by_user_id is not null)
  ),
  constraint orders_percent_discount_bound
    check (discount_kind is distinct from 'percent' or discount_value <= 100),
  constraint orders_settled_shape check (
    status <> 'settled'
    or (receipt_number is not null and settled_at is not null
        and settled_by_user_id is not null and total = paid_total)
  ),
  constraint orders_void_shape check (status <> 'void' or void_reason is not null),
  foreign key (session_id, arena_id)
    references public.sessions (id, arena_id) on delete restrict,
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete restrict
);

comment on table public.orders is
  'A checkout order belongs to at most one session (D07). Orders are never '
  'deleted; settled and void are terminal.';
comment on column public.orders.paid_total is
  'Trigger-maintained from payments. The only column that may change on a '
  'settled order (D21).';

-- One live order per session. Voided orders are excluded so a session whose
-- order was voided can be checked out again (D07, API.md §5).
create unique index orders_one_live_per_session
  on public.orders (session_id) where session_id is not null and status <> 'void';
create unique index orders_arena_receipt_number_idx
  on public.orders (arena_id, receipt_number) where receipt_number is not null;
create index orders_arena_business_date_status_idx
  on public.orders (arena_id, business_date, status);
create index orders_arena_updated_at_idx on public.orders (arena_id, updated_at);
create index orders_member_id_idx on public.orders (member_id);
create index orders_opened_by_user_id_idx on public.orders (opened_by_user_id);
create index orders_settled_by_user_id_idx on public.orders (settled_by_user_id);
create index orders_discount_authorised_by_user_id_idx
  on public.orders (discount_authorised_by_user_id);

create trigger orders_touch_updated_at
  before update on public.orders
  for each row execute function app.touch_updated_at();

create trigger orders_business_date_immutable
  before update on public.orders
  for each row execute function app.forbid_business_date_change();

create function app.orders_guard_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  -- A receipt number is never reissued or reused (SECURITY.md §10).
  if old.receipt_number is not null
     and new.receipt_number is distinct from old.receipt_number then
    raise exception 'invalid_state: receipt_number is immutable once assigned (D13)'
      using errcode = 'P0001';
  end if;
  if old.receipt_sequence is not null
     and new.receipt_sequence is distinct from old.receipt_sequence then
    raise exception 'invalid_state: receipt_sequence is immutable once assigned (D13)'
      using errcode = 'P0001';
  end if;

  -- balance_due is generated, so it is null in NEW during a BEFORE trigger and
  -- must be excluded from the comparison.
  if old.status = 'settled'
     and (to_jsonb(new) - 'paid_total' - 'updated_at' - 'balance_due')
         is distinct from (to_jsonb(old) - 'paid_total' - 'updated_at' - 'balance_due') then
    raise exception
      'invalid_state: a settled order is immutable except for paid_total (D21)'
      using errcode = 'P0001';
  end if;

  if old.status = 'void'
     and (to_jsonb(new) - 'updated_at' - 'balance_due')
         is distinct from (to_jsonb(old) - 'updated_at' - 'balance_due') then
    raise exception 'invalid_state: a voided order is immutable (D07)'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function app.orders_guard_immutable() is
  'settled and void are terminal, and no path transitions an order out of '
  'settled (SECURITY.md §10, §15 assertion 13).';

create trigger orders_guard_immutable
  before update on public.orders
  for each row execute function app.orders_guard_immutable();

-- ── order_items ──────────────────────────────────────────────────────────────

create table public.order_items (
  id               uuid primary key,
  arena_id         uuid           not null references public.arenas (id) on delete restrict,
  order_id         uuid           not null,
  type             text           not null check (type in ('play', 'product', 'adjustment')),
  session_id       uuid           null,
  product_id       uuid           null,
  name_snapshot    text           not null check (length(btrim(name_snapshot)) > 0),
  description      text           null,
  quantity         numeric(12, 3) not null check (quantity > 0),
  unit_price       numeric(12, 2) not null check (unit_price >= 0),
  line_subtotal    numeric(12, 2) not null,
  discount_amount  numeric(12, 2) not null default 0,
  taxable_amount   numeric(12, 2) not null,
  tax_rate_id      uuid           null,
  tax_rate_snapshot jsonb         not null,
  tax_amount       numeric(12, 2) not null default 0,
  line_total       numeric(12, 2) not null,
  sort_order       int            not null default 0,
  created_at       timestamptz    not null default now(),
  updated_at       timestamptz    not null default now(),
  unique (id, arena_id),
  constraint order_items_play_shape check (type <> 'play' or session_id is not null),
  constraint order_items_product_shape check (type <> 'product' or product_id is not null),
  foreign key (order_id, arena_id)
    references public.orders (id, arena_id) on delete restrict,
  foreign key (session_id, arena_id)
    references public.sessions (id, arena_id) on delete restrict,
  foreign key (product_id, arena_id)
    references public.products (id, arena_id) on delete restrict,
  foreign key (tax_rate_id, arena_id)
    references public.tax_rates (id, arena_id) on delete restrict
);

comment on column public.order_items.tax_rate_snapshot is
  'Immutable multi-component snapshot, schema_version 1 (D12, D31). Carries '
  'every component with its configured percent AND its computed amount, so a '
  'settled order needs no current configuration to reconstruct.';

create unique index order_items_one_play_line_per_order
  on public.order_items (order_id) where type = 'play';
create index order_items_order_id_idx on public.order_items (order_id);
create index order_items_arena_id_idx on public.order_items (arena_id);
create index order_items_session_id_idx on public.order_items (session_id);
create index order_items_product_id_idx on public.order_items (product_id);
create index order_items_tax_rate_id_idx on public.order_items (tax_rate_id);

create trigger order_items_touch_updated_at
  before update on public.order_items
  for each row execute function app.touch_updated_at();

-- ── payments ─────────────────────────────────────────────────────────────────
-- Append-only. No updated_at: a row never changes (DATABASE.md §1.3, §1.7).

create table public.payments (
  id                  uuid primary key,
  arena_id            uuid           not null references public.arenas (id) on delete restrict,
  order_id            uuid           not null,
  shift_id            uuid           not null,
  method              text           not null check (method in ('cash', 'upi', 'card')),
  amount              numeric(12, 2) not null check (amount <> 0),
  reverses_payment_id uuid           null,
  reference           text           null,
  actor_user_id       uuid           not null references public.profiles (id) on delete restrict,
  business_date       date           not null,
  created_at          timestamptz    not null default now(),
  unique (id, arena_id),
  constraint payments_reversal_shape check (
    (reverses_payment_id is null and amount > 0)
    or (reverses_payment_id is not null and amount < 0)
  ),
  foreign key (order_id, arena_id)
    references public.orders (id, arena_id) on delete restrict,
  foreign key (shift_id, arena_id)
    references public.shifts (id, arena_id) on delete restrict,
  foreign key (reverses_payment_id, arena_id)
    references public.payments (id, arena_id) on delete restrict
);

comment on table public.payments is
  'Append-only and signed. P0 inserts only positive rows; the reversal shape '
  'exists so refunds need no schema change (D21).';
comment on column public.payments.shift_id is
  'The only shift linkage used for cash reconciliation (D08). Set server-side '
  'to the shift open at the moment the payment is recorded.';

create index payments_arena_shift_method_idx on public.payments (arena_id, shift_id, method);
create index payments_order_id_idx on public.payments (order_id);
create index payments_shift_id_idx on public.payments (shift_id);
create index payments_reverses_payment_id_idx on public.payments (reverses_payment_id);
create index payments_actor_user_id_idx on public.payments (actor_user_id);
create index payments_arena_business_date_idx on public.payments (arena_id, business_date);

create trigger payments_append_only
  before update or delete on public.payments
  for each row execute function app.forbid_mutation();

create function app.sync_order_paid_total()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  update public.orders o
     set paid_total = (
           select coalesce(sum(p.amount), 0)
             from public.payments p
            where p.order_id = new.order_id
              and p.arena_id = new.arena_id
         )
   where o.id = new.order_id
     and o.arena_id = new.arena_id;
  return null;
end;
$$;

comment on function app.sync_order_paid_total() is
  'orders.paid_total is trigger-maintained from payments; balance_due is a '
  'generated column over it (D07).';

create trigger payments_sync_order_paid_total
  after insert on public.payments
  for each row execute function app.sync_order_paid_total();

-- ── product_stock ────────────────────────────────────────────────────────────
-- A materialisation, not an entity: PRIMARY KEY (arena_id, product_id), no id
-- (DATABASE.md §1.3).

create table public.product_stock (
  arena_id   uuid           not null,
  product_id uuid           not null,
  quantity   numeric(12, 3) not null default 0,
  updated_at timestamptz    not null default now(),
  primary key (arena_id, product_id),
  foreign key (product_id, arena_id)
    references public.products (id, arena_id) on delete restrict
);

comment on table public.product_stock is
  'Trigger-maintained materialisation of SUM(inventory_movements.quantity). '
  'Never client-writable. Negative stock is permitted and flagged (D20).';

create index product_stock_product_id_idx on public.product_stock (product_id);
create index product_stock_arena_updated_at_idx on public.product_stock (arena_id, updated_at);

-- ── inventory_movements ──────────────────────────────────────────────────────
-- Append-only and signed. Sign is constrained per movement type (D20).

create table public.inventory_movements (
  id            uuid           primary key,
  arena_id      uuid           not null references public.arenas (id) on delete restrict,
  product_id    uuid           not null,
  type          text           not null
    check (type in ('opening', 'restock', 'sale', 'wastage', 'staff_use', 'breakage', 'correction')),
  quantity      numeric(12, 3) not null check (quantity <> 0),
  unit_cost     numeric(12, 2) null,
  order_id      uuid           null,
  order_item_id uuid           null,
  actor_user_id uuid           not null references public.profiles (id) on delete restrict,
  note          text           null,
  business_date date           not null,
  created_at    timestamptz    not null default now(),
  unique (id, arena_id),
  constraint inventory_movements_sign check (
    (type in ('opening', 'restock') and quantity > 0)
    or (type in ('sale', 'wastage', 'staff_use', 'breakage') and quantity < 0)
    or (type = 'correction')
  ),
  constraint inventory_movements_sale_shape
    check (type <> 'sale' or (order_id is not null and order_item_id is not null)),
  foreign key (product_id, arena_id)
    references public.products (id, arena_id) on delete restrict,
  foreign key (order_id, arena_id)
    references public.orders (id, arena_id) on delete restrict,
  foreign key (order_item_id, arena_id)
    references public.order_items (id, arena_id) on delete restrict
);

comment on table public.inventory_movements is
  'Signed, immutable movements are the source of truth for stock (D20). A '
  'correction is a new row of type = correction, never an edit.';

create index inventory_movements_arena_product_created_idx
  on public.inventory_movements (arena_id, product_id, created_at desc);
create index inventory_movements_order_id_idx on public.inventory_movements (order_id);
create index inventory_movements_order_item_id_idx on public.inventory_movements (order_item_id);
create index inventory_movements_actor_user_id_idx on public.inventory_movements (actor_user_id);
create index inventory_movements_arena_business_date_idx
  on public.inventory_movements (arena_id, business_date);

create trigger inventory_movements_append_only
  before update or delete on public.inventory_movements
  for each row execute function app.forbid_mutation();

create function app.sync_product_stock()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  insert into public.product_stock as ps (arena_id, product_id, quantity, updated_at)
  values (new.arena_id, new.product_id, new.quantity, now())
  on conflict (arena_id, product_id) do update
    set quantity = ps.quantity + excluded.quantity,
        updated_at = now();
  return null;
end;
$$;

comment on function app.sync_product_stock() is
  'AFTER INSERT only — inventory_movements is append-only, so the '
  'materialisation always equals the sum of movements (D20).';

create trigger inventory_movements_sync_product_stock
  after insert on public.inventory_movements
  for each row execute function app.sync_product_stock();

-- ── receipt_counters ─────────────────────────────────────────────────────────
-- A counter, not an entity: PRIMARY KEY (arena_id, series), no id.
-- Rows are not pre-created; the first settlement in a series inserts one, so a
-- financial-year rollover needs no migration (D13, D31).

create table public.receipt_counters (
  arena_id    uuid        not null references public.arenas (id) on delete restrict,
  series      text        not null,
  next_number bigint      not null default 1 check (next_number >= 1),
  updated_at  timestamptz not null default now(),
  primary key (arena_id, series)
);

comment on table public.receipt_counters is
  'Per-arena, per-series sequential receipt numbering (D13). The series key '
  'comes from arena_settings.receipt_series_mode, never from code.';

-- ── idempotency_keys ─────────────────────────────────────────────────────────
-- The SERVER-side store. This is not the client outbox, which lives only in
-- Drift and is never synchronised (D16).

create table public.idempotency_keys (
  arena_id            uuid        not null references public.arenas (id) on delete restrict,
  key                 text        not null check (length(btrim(key)) > 0),
  operation           text        not null check (length(btrim(operation)) > 0),
  request_fingerprint text        not null,
  response            jsonb       null,
  status              text        not null
    check (status in ('in_progress', 'succeeded', 'failed')),
  actor_user_id       uuid        not null references public.profiles (id) on delete restrict,
  created_at          timestamptz not null default now(),
  expires_at          timestamptz not null default now() + interval '30 days',
  primary key (arena_id, key)
);

comment on table public.idempotency_keys is
  'Keys are namespaced per arena, so a key from one tenant can never match '
  'another''s (D16). No client read path.';

create index idempotency_keys_actor_user_id_idx on public.idempotency_keys (actor_user_id);
create index idempotency_keys_expires_at_idx on public.idempotency_keys (expires_at);

-- ── audit_logs ───────────────────────────────────────────────────────────────
-- The only event store. session_events is removed (D22). Append-only.

create table public.audit_logs (
  id            uuid        primary key default gen_random_uuid(),
  arena_id      uuid        not null references public.arenas (id) on delete restrict,
  actor_user_id uuid        null references public.profiles (id) on delete restrict,
  action        text        not null check (length(btrim(action)) > 0),
  entity_type   text        not null check (length(btrim(entity_type)) > 0),
  entity_id     uuid        not null,
  metadata      jsonb       not null default '{}'::jsonb,
  device_id     uuid        null,
  business_date date        not null,
  created_at    timestamptz not null default now(),
  unique (id, arena_id)
);

comment on table public.audit_logs is
  'Written by app.audit() inside the acting RPC''s transaction, so a client '
  'cannot perform an audited action and skip the record (D22).';
comment on column public.audit_logs.metadata is
  'Never contains member PII. Log the member id, never the name or phone (D19).';
comment on column public.audit_logs.device_id is
  'Reported by the client, not trusted and not a foreign key (SECURITY.md §6).';

create index audit_logs_arena_entity_created_idx
  on public.audit_logs (arena_id, entity_type, entity_id, created_at desc);
create index audit_logs_arena_business_date_idx on public.audit_logs (arena_id, business_date);
create index audit_logs_actor_user_id_idx on public.audit_logs (actor_user_id);

create trigger audit_logs_append_only
  before update or delete on public.audit_logs
  for each row execute function app.forbid_mutation();
