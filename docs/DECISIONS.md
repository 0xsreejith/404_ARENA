# Decisions

Authoritative decision log for Arena OS.

If any other document contradicts this file, **this file wins** and the other
document is a bug.

Status values: `Accepted`, `Deferred`, `Superseded`, `Amended`.

Date of this pass: 2026-07-30. D31–D37 added in the same pass; D12 and D13 were
amended by D31.

---

## Index

| # | Decision | Status |
|---|---|---|
| D01 | Money representation | Accepted |
| D02 | Tenant boundary is the arena | Accepted |
| D03 | Composite tenant foreign keys | Accepted |
| D04 | Identity, actor attribution, and deferred PIN | Accepted |
| D05 | Server-authoritative RPC write path | Accepted |
| D06 | Stored session status vs derived presentation state | Accepted |
| D07 | Order / session / payment relationships | Accepted |
| D08 | Shift ownership of money | Accepted |
| D09 | Business date | Accepted |
| D10 | P0 pricing model | Accepted |
| D11 | Pricing snapshots | Accepted |
| D12 | Tax configuration and line-level tax snapshots | Amended by D31 |
| D13 | Receipt numbering | Amended by D31 |
| D14 | Discounts in P0 | Accepted |
| D15 | Offline scope and the offline checkout rule | Accepted |
| D16 | Client outbox vs server idempotency | Accepted |
| D17 | Sync metadata and deletion strategy | Accepted |
| D18 | 24-hour stale-client degradation | Accepted |
| D19 | Member data privacy | Accepted |
| D20 | Inventory accounting | Accepted |
| D21 | Append-only financial and audit data | Accepted |
| D22 | Single audit store (`session_events` removed) | Accepted |
| D23 | Realtime deferred | Accepted |
| D24 | Flutter transport | Accepted |
| D25 | Flutter state management and model layers | Accepted |
| D26 | Repository scope and Owner Admin Web | Accepted |
| D27 | Station types normalised | Accepted |
| D28 | Post-MVP deferrals | Accepted |
| D29 | Cash paid out of drawer not modelled in P0 | Accepted |
| D30 | One open shift per arena | Accepted |
| D31 | Pilot jurisdiction, currency, and GST-ready tax architecture | Accepted |
| D32 | Tax-inclusive price display | Accepted |
| D33 | Pricing is configuration, not code | Accepted |
| D34 | Supabase topology — three projects | Accepted |
| D35 | Database testing with pgTAP | Accepted |
| D36 | Canonical phone storage | Accepted |
| D37 | `service_role` handling and backup ownership | Accepted |
| D26a | Owner Admin Web in-repo | Accepted |
| D28a | Commercial CRM / wallet / memberships after CORE | Accepted |
| D38 | Super Admin platform schema separation | Accepted |
| D39 | Staff UI converges on Lobby HTML shell | Accepted |
| D40 | Commercial product catalogue (full SaaS scope) | Accepted |
| D41 | Platform billing topology | Accepted |

---

## D01 — Money representation

**PostgreSQL:** all monetary columns are `numeric(12,2)`. Never `float`,
`real`, `double precision`, or `money`.

**Dart:** money is an `int` of **minor units** (e.g. paise, cents). Never
`double`. A `Money` value object in `core/money/` wraps the integer and the
currency code, alongside `core/time/` and `core/errors/` — see
`ARCHITECTURE.md` §3, which is authoritative for file layout.

**Boundary conversion:** the Supabase client receives `numeric` as a string.
Parse string → minor-unit `int` at the data-source boundary. Never parse money
through `double`.

**Currency:** `arenas.currency` is an ISO 4217 code. P0 assumes a 2-decimal
minor unit for all supported currencies.

**Percentages:** `numeric(5,2)` (e.g. `18.00`).
**Quantities:** `numeric(12,3)` to allow fractional stock units.

---

## D02 — Tenant boundary is the arena

The **arena** is the operational tenant boundary for MVP.

`organizations` exists and owns arenas, but in P0 it is a grouping label only.
No cross-arena read, aggregation, or configuration inheritance is implemented
in P0.

Every tenant-owned row carries `arena_id NOT NULL`. Every authorisation
decision is scoped to an arena.

A user may belong to more than one arena (`arena_users` allows it). The client
holds exactly one **active arena** at a time; the server validates the arena on
every call and never trusts a client-supplied `arena_id` without checking
membership.

---

## D03 — Composite tenant foreign keys

Every tenant-owned table declares `UNIQUE (id, arena_id)` in addition to its
primary key. This is intentionally redundant — it exists solely as a composite
foreign-key target.

Every foreign key between two tenant-owned tables is composite:

```sql
FOREIGN KEY (station_id, arena_id) REFERENCES stations (id, arena_id)
```

This makes cross-arena references structurally impossible rather than
policy-dependent. It cannot be retrofitted cheaply, so it lands in the first
migration.

References to non-tenant-owned tables (`auth.users`, `profiles`, `permissions`)
are simple foreign keys.

---

## D04 — Identity, actor attribution, and deferred PIN

Supabase Auth identifies the **real staff user**. One Supabase user per staff
member. `profiles.id = auth.users.id`.

Actor identity is **always derived server-side**. Clients never supply
`actor_user_id`, `created_by`, `started_by`, or equivalent; if they do, the
value is ignored.

Every actor column in the schema is named `*_user_id` and references
`profiles(id)`. Every RPC resolves the actor through a single function:

```sql
app.current_actor_id() -- P0: returns auth.uid()
```

**Deferred PIN switching.** Shared-device PIN switching is out of P0. When it
arrives, only the body of `app.current_actor_id()` changes: it will resolve the
actor from a server-verified PIN session bound to the device's Supabase
session, falling back to `auth.uid()`. No column, no audit record, and no RPC
signature changes. `arena_users.staff_pin_hash` is **not** created in P0 —
a PIN credential will live in its own table with no client-side read access.

---

## D05 — Server-authoritative RPC write path

All stateful and financial mutations happen inside `SECURITY DEFINER`
PostgreSQL functions (Supabase RPC).

The `authenticated` role has **no** `INSERT`, `UPDATE`, or `DELETE` privilege on
protected tables. Privilege revocation — not RLS alone — is the primary write
control. See `SECURITY.md`.

The client may read protected tables through RLS-scoped `SELECT`, except where
`SECURITY.md` restricts reads further (notably `members`).

Flutter may compute **display estimates** (a running timer, an approximate
running total) but never submits a computed money value that the server stores.
Every amount persisted is computed by the server.

---

## D06 — Stored session status vs derived presentation state

**Stored** `sessions.status`, exhaustively:

```
active | paused | completed | cancelled
```

**Derived** station presentation state, computed by the client from station
operational status + the active session's timestamps, never stored:

```
idle | live | ending | overtime | paused | maintenance | inactive
```

**Stored** `stations.status`, exhaustively:

```
active | maintenance | inactive
```

Derivation rules are normative and live in `UI_SPEC.md`.

`ending` and `overtime` require `sessions.planned_end_at`. Open-time sessions
have `planned_end_at IS NULL` and therefore **never** render `ending` or
`overtime`; they render `live` with elapsed time. This is intended.

`reserved` is not a P0 state (reservations are post-MVP).

No background job, cron, or scheduled write exists to advance session state on a
clock boundary. The only writes to a session are explicit user actions.

---

## D07 — Order / session / payment relationships

- A **checkout order** may belong to **at most one** gaming session.
  `orders.session_id` is nullable and unique when not null, **excluding voided
  orders** — so a session whose order was voided can be checked out again.
- A session therefore has at most one live order. Standalone counter sales have
  `session_id IS NULL`.
- Play charges are `order_items` with `type = 'play'`.
- Product sales are `order_items` with `type = 'product'`.
- `type = 'adjustment'` is reserved for server-generated corrections; not used
  in P0.
- `payments` reference `order_id`. An order may have many payments (split
  payment is representable in the schema from day one, even though the P0 UI
  offers a single payment).
- `orders.paid_total` is trigger-maintained from `payments`.
  `orders.balance_due` is a generated column.
- Orders are never deleted. Terminal states are `settled` and `void`.

---

## D08 — Shift ownership of money

Cash reconciliation follows the **payment**, never the session.

- `payments.shift_id` is `NOT NULL` and set server-side to the shift that is
  open in that arena at the moment the payment is recorded. It is the only
  shift linkage used for money.
- `orders` has **no** shift column. This is deliberate: a shift column on the
  order invites incorrect reconciliation.
- `sessions.opened_in_shift_id` is nullable and **informational only**. It
  records which shift started the play. It must never appear in a cash or
  revenue calculation.

A session that starts in shift A and is paid in shift B contributes its revenue
entirely to shift B.

---

## D09 — Business date

Gaming centres trade past midnight. Calendar date is not the operating day.

- `arena_settings.business_day_start_time` (default `06:00`) plus
  `arenas.timezone` define the operating day.
- `app.business_date(p_arena_id, p_at timestamptz) RETURNS date` is the single
  implementation. Nothing else computes a business date.
- `business_date` is stored, `NOT NULL`, and immutable on: `shifts`,
  `sessions`, `orders`, `payments`, `inventory_movements`, `audit_logs`.
- It is set server-side at insert. Clients never supply it.
- All operational reporting groups by `business_date`, never by
  `created_at::date`.

---

## D10 — P0 pricing model

P0 supports exactly two billing plan types:

1. **`open_time`** — billed per hour from an `hourly_rate`.
2. **`fixed_duration`** — a package of `duration_minutes` for `fixed_price`.

Each plan also carries `grace_minutes`, `rounding_increment_minutes`,
`rounding_mode`, and `minimum_billable_minutes`.

A plan may be restricted to one station type (`station_type_id`), or apply to
all types when null.

`player_count` is recorded on the session for operational reasons but **does not
affect price in P0**.

**Post-MVP:** happy hour, weekend surcharge, day-part rates, per-extra-player
rates, member rates, and any rule engine. The `pricing_rules` table from the
original specification is not created in P0.

---

## D11 — Pricing snapshots

`sessions.pricing_snapshot jsonb NOT NULL` is captured at
`session_start` and never modified.

Billing at checkout uses the snapshot, not the current configuration. Editing a
billing plan therefore cannot change any historical bill.

The snapshot is versioned. Contract v1 is normative in `DATABASE.md`.

`order_items` additionally snapshot their own name, unit price, and tax rate, so
an order remains fully reconstructable after any catalogue change.

---

## D12 — Tax configuration and line-level tax snapshots

> **Amended by D31.** The single-component simplification below is withdrawn:
> tax rates are composed of **configured components** from the first schema, and
> multi-component snapshots are `schema_version: 1`, not a future version.

Supported from the **first production order**, without building a tax engine.

- `tax_rates` is arena-scoped and composed of one or more
  `tax_rate_components` (D31). `tax_rates.percent` is the trigger-maintained
  sum of its components.
- `arena_settings.prices_include_tax boolean` decides inclusive vs exclusive
  pricing arena-wide in P0 (D32).
- `arena_settings.default_play_tax_rate_id` and
  `arena_settings.default_product_tax_rate_id` supply defaults.
- `products.tax_rate_id` overrides the product default.
- Every `order_items` row stores an immutable `tax_rate_snapshot jsonb`
  carrying every component with its configured percent **and** its computed
  amount, plus `taxable_amount` and `tax_amount`.

**Explicitly not in P0:** place-of-supply resolution, customer GSTIN capture,
HSN/SAC codes, reverse charge, tax return generation, exemption handling. The
schema represents the outcome of those rules; P0 does not compute them.

---

## D13 — Receipt numbering

> **Amended by D31.** Series rollover is arena **configuration** from the first
> schema, not a post-MVP settings change, and no jurisdiction-specific
> numbering rule lives in application code.

A settled order receives a gap-free, per-arena, per-series sequential receipt
number, assigned inside `order_settle` under a row lock. It cannot be
backfilled, so it exists from the first order.

- `receipt_counters (arena_id, series)` holds `next_number`.
- The **series key is derived from configuration**, not hardcoded:
  `app.receipt_series(p_arena_id, p_business_date)` reads
  `arena_settings.receipt_series_mode` — `fixed`, `monthly`, `yearly`, or
  `financial_yearly` — together with
  `arena_settings.receipt_financial_year_start_month`.
- The rendered number comes from a token template,
  `arena_settings.receipt_number_format`, so no jurisdiction's format is
  embedded in SQL or Dart.
- `orders.receipt_sequence bigint` and `orders.receipt_number text` are null
  until settlement, then immutable.
- `UNIQUE (arena_id, receipt_number)`.

A new series starts its counter at 1 automatically — an Indian arena on
`financial_yearly` therefore restarts numbering each April without any code
change or migration.

---

## D14 — Discounts in P0

One order-level discount, authorised by a permission holder, with a mandatory
reason.

Stored on `orders`:

- `discount_kind` — `flat` or `percent`, null when no discount
- `discount_value` — the flat amount or the percentage
- `discount_total` — the resolved money amount, server-computed
- `discount_reason` — `NOT NULL` when a discount exists
- `discount_authorised_by` — the acting user, server-derived

The discount is allocated proportionally across taxable line items so
line-level tax stays correct. The allocation rule is normative in
`DATABASE.md`.

Only `discount.apply` exists in P0. Holding it *is* the authorisation.
`discount.override` (exceeding a configured cap) is post-MVP.

**Post-MVP:** stacked discounts, line-level discounts, coupon codes, discount
caps, member discounts.

---

## D15 — Offline scope and the offline checkout rule

Offline **writes** in P0 are limited to:

- `session_start`
- `session_stop`

Everything else — checkout, payments, shift open/close, product sales, member
creation, inventory adjustment, station status change — is **online-only**.

**Checkout is unavailable while offline.** There is no provisional offline
billing in P0. No locally computed bill is ever stored or presented as final.

**Accepted consequence.** A session stopped while offline is `completed` and
**unbilled**. It appears in an **Unbilled sessions** queue and is billed when
connectivity returns. This queue is a required P0 surface, not an optional
extra. Staff handling of cash taken during an outage is an operational
procedure, not a software feature, in P0.

Offline **reads** are served from the Drift cache for the floor, stations,
zones, station types, games, billing plans, tax rates, products, current stock,
arena settings, and the open shift. See `OFFLINE.md` §2 for the authoritative
operation matrix and §8 for the exact cached set.

---

## D16 — Client outbox vs server idempotency

Two separate concepts. Never one table.

**Client outbox** — a Drift table on the device. Holds queued mutations with
`payload`, `idempotency_key`, `attempt_count`, `next_attempt_at`, `status`,
`last_error`, `client_created_at`. Never synchronised to the server.

**Server idempotency store** — `idempotency_keys` in PostgreSQL, primary key
`(arena_id, key)`. Stores a request fingerprint and the original response.

- A replay with the same key and the same fingerprint returns the **stored
  response**, not an error.
- A replay with the same key and a different fingerprint is a conflict error.
- Keys are namespaced per arena and expire after 30 days.

The `sync_operations` table from the original specification is removed; it
conflated the two.

---

## D17 — Sync metadata and deletion strategy

Every syncable table carries:

- `id uuid PRIMARY KEY` — **client-generated** for entities a client may create
  offline; server-generated otherwise. Client generation is required for
  `sessions`, `orders`, `order_items`, `payments`, `members`,
  `inventory_movements`, and `devices`.
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`, maintained by trigger

Deliberate exceptions — join tables, materialisations, counters, and the
append-only tables — are enumerated in `DATABASE.md` §1.3. Nothing outside that
list may deviate.

**Deletion strategy, by table class:**

| Class | Tables | Rule |
|---|---|---|
| Catalogue | zones, station_types, stations, games, products, billing_plans, tax_rates, members, roles | **Soft delete** via `deleted_at timestamptz`. Rows are never hard-deleted. |
| Transactional / financial | sessions, orders, order_items, payments, inventory_movements, shifts, audit_logs | **Never deleted.** Terminal statuses (`cancelled`, `void`) express removal. |
| Access control | arena_users | Deactivated via `active`, never deleted. |

Soft-deleted rows are returned by `sync_pull` so clients can remove them
locally. Every uniqueness constraint on a soft-deletable table is partial on
`deleted_at IS NULL`.

Sync uses an `updated_at` watermark with a 5-second overlap window and
idempotent client-side upserts. See `OFFLINE.md`.

---

## D18 — 24-hour stale-client degradation

The client records `last_successful_sync_at`.

After **24 hours** with no successful server synchronisation:

- Queued offline mutations remain queued and are never discarded.
- **No new offline mutations are accepted.** Session start and stop require
  connectivity.
- The app is read-only from cache with a persistent blocking banner.

Cached permissions and cached configuration carry the same 24-hour TTL. Stale
permissions are never trusted indefinitely.

---

## D19 — Member data privacy

The member table is **never** fully replicated to a device.

- `authenticated` has **no direct `SELECT`** on `members`. All member reads go
  through RPCs.
- `member_search` is server-side, requires a query of at least 3 characters,
  and returns at most 20 rows.
- The device caches only: members attached to currently active or unbilled
  sessions, plus the last 20 members touched on that device, with a 24-hour
  TTL. The cache is cleared on sign-out and on arena switch.
- Member PII is never written to logs or crash reports.
- The floor snapshot returns a member display name for active sessions and
  nothing else.

---

## D20 — Inventory accounting

- `inventory_movements` is append-only and **signed**. Negative reduces stock.
  Sign is constrained per movement type.
- `product_stock` is a materialised per-product quantity maintained by an
  `AFTER INSERT` trigger on `inventory_movements`. It is never client-writable
  and is always reconstructable by summing movements.
- **Negative stock is permitted and flagged.** A sale is never blocked by
  insufficient recorded stock; blocking a real sale because a restock was not
  entered is worse than a visible negative. Negative stock surfaces as a
  data-quality warning on the stock screen.
- Product sales are online-only in P0, so offline oversell cannot occur.

---

## D21 — Append-only financial and audit data

`payments`, `inventory_movements`, and `audit_logs` reject `UPDATE` and
`DELETE` from **every** role, including the RPC definer, enforced by a
`BEFORE UPDATE OR DELETE` trigger that raises an exception.

Corrections are new rows:

- A payment reversal is a `payments` row with a negative `amount` and
  `reverses_payment_id` set. P0 writes only positive rows; the shape exists so
  refunds need no schema change.
- An inventory correction is a movement of `type = 'correction'`.

`orders` and `sessions` are mutable only through RPCs and only along their
defined status transitions. Settled orders are immutable except for the
trigger-maintained `paid_total`.

---

## D22 — Single audit store

`session_events` is **removed**. `audit_logs` is the only event store.

The session timeline shown in the UI is derived from `audit_logs` filtered to
`entity_type = 'session'`.

Audit rows are written inside the RPC that performs the action, in the same
transaction. A client cannot perform an audited action and skip the audit row.

`audit_logs` is readable within an arena by holders of `report.view`. It is
never insertable, updatable, or deletable by a client.

---

## D23 — Realtime deferred

Supabase Realtime is **not** required for the pilot and is not enabled in P0.

Floor freshness in P0 comes from a 10-second poll plus pull-to-refresh plus
immediate local application of the user's own mutations.

Repository interfaces expose `Stream<T>` from day one so a Realtime source can
be substituted without touching controllers or UI. When Realtime is enabled,
RLS applies to the publication and the client-side `filter:` parameter is
treated as an optimisation, never as authorisation.

---

## D24 — Flutter transport

`supabase_flutter` is the transport: Auth, PostgREST reads, RPC calls, and
(later) Realtime.

**Dio is not added.** It enters the project only if a separate REST backend
actually exists, which it does not.

---

## D25 — Flutter state management and model layers

- **Riverpod 3** is the state-management standard. No Bloc, GetX, or
  `package:provider`.
- **Drift** is the local database.
- **Freezed** domain models are permitted.
- **One model per concept wherever the shapes match.** A separate DTO layer is
  added only where the wire shape genuinely differs from the domain shape.
  Drift row → mapper → Freezed domain is the default; a third DTO type requires
  a stated reason.
- Money crosses every layer as minor-unit `int` inside a `Money` value object.

---

## D26 — Repository scope and Owner Admin Web

This repository contains:

- `mobile/` — the Flutter staff/manager application
- `supabase/` — schema, RPCs, policies, seed data

**Owner Admin Web is outside this repository and outside the first Flutter
MVP.** During the pilot, owner-level tasks are performed in the tablet app by a
user holding owner permissions, or directly in Supabase Studio.

`docs/` describes the whole platform contract, including parts a future web
client will consume.

---

## D27 — Station types normalised

`stations.type` (free text) is replaced by `station_types`, an arena-scoped
table (`PC`, `PS5`, `VR`, …). `stations.station_type_id` references it.

Reason: station type drives pricing eligibility and floor grouping. Free text
cannot be referenced by a billing plan and violates the no-hardcoding rule.
This is a normalisation of an existing field, not a new feature.

---

## D28 — Post-MVP deferrals

Deferred out of P0, with no P0 tables created:

memberships and membership plans · wallet / coins · reservations ·
`session_games` and change-game tracking · `station_games` · FCM and
notifications · maintenance ticket workflow · asset registry and QR scanning ·
expenses · pricing rule engine · refunds and payment reversal UI · split
payment UI · receipts (printed/emailed) · tournaments · leaderboards · lobby TV
· customer app · online booking · multi-location dashboards · advanced
analytics · supplier workflows · accounting integrations.

Stations can still be marked `maintenance` in P0 — the station status remains;
only the ticket workflow is deferred.

---

## D29 — Cash paid out of the drawer is not modelled in P0

Expenses are post-MVP, so cash removed from the drawer during a shift has no
record in P0 and will appear as a negative variance at close.

Accepted for the pilot. Mitigation: `shifts.notes` is captured at close and the
close screen prompts for an explanation when variance is non-zero.

A `cash_movements` table lands with expenses, post-MVP.

---

## D30 — One open shift per arena

P0 enforces at most one open shift per arena via a partial unique index.

Multiple registers or tills in one arena are post-MVP and will require a
migration adding `register_id` and changing the partial unique index. No
placeholder column is added now.

---

## D31 — Pilot jurisdiction, currency, and GST-ready tax architecture

**Pilot country: India. Pilot currency: INR.**

This is a property of the *pilot tenant*, not of the product. Country and
currency are arena configuration; nothing about India is compiled into Flutter
or into SQL function bodies.

### Money

Unchanged from D01: `numeric(12,2)` in PostgreSQL, minor-unit `int` (paise) in
Dart. `arenas.currency = 'INR'` for the pilot. INR has a 2-decimal minor unit,
which matches the P0 assumption.

### Tax must be GST-ready from the first schema

An Indian invoice splits one tax rate into components: intra-state supply is
CGST + SGST at half each, inter-state supply is a single IGST. Both must be
representable without a schema redesign, so **tax rates are composed of
configured components from migration 1**:

- `tax_rate_components (id, arena_id, tax_rate_id, name, percent, sort_order)`
  — a new P0 table.
- `tax_rates.percent` becomes the **trigger-maintained sum** of its components
  and is never written directly by a client. Components are the source of
  truth.
- A tax rate must have at least one component. A jurisdiction with no split
  configures a single component.

An arena serving both intra- and inter-state customers configures two rates —
for example `GST 18% (Intra)` with CGST 9 + SGST 9, and `GST 18% (Inter)` with
IGST 18. **Both are tenant data.**

### No hardcoded rates

There is no `18`, no `9`, no `CGST`, and no `SGST` anywhere in Flutter or in a
SQL function body. Rates, component names, and splits are rows in
`tax_rate_components`, created by provisioning or by a tenant with
`pricing.manage`. `provision_arena` seeds only a `0%` rate named `No tax` with
a single `0%` component, so a new tenant is never blocked and never
pre-assigned someone else's tax law.

### Which rate applies

P0 applies the arena's configured default — `default_play_tax_rate_id` and
`default_product_tax_rate_id`, with `products.tax_rate_id` overriding per
product. **P0 does not resolve place of supply.** Choosing intra- vs
inter-state per order requires customer GSTIN capture and place-of-supply
rules; that is post-MVP and needs no schema change when it arrives, because it
only changes *which existing rate id* is selected.

### Immutable multi-component snapshots

`order_items.tax_rate_snapshot` is `schema_version: 1` and carries every
component with both its configured `percent` and its **computed `amount`**.
A settled order therefore contains everything a GST return needs, frozen at the
moment of sale, with no dependency on current configuration.

Component amounts are allocated by largest remainder so they sum **exactly** to
the line's `tax_amount`. CGST and SGST on an 18% line are each half of the tax,
to within a single paisa that is assigned deterministically to the lower
`sort_order` — never left to float between the two halves, and never allowed to
make the components disagree with the line total.

### Configurable receipt numbering

See D13 as amended. India requires a per-financial-year series starting in
April; that is expressed as `receipt_series_mode = 'financial_yearly'` and
`receipt_financial_year_start_month = 4` in **arena settings**, not as a
constant in code. A tenant in another jurisdiction sets a different mode.

---

## D32 — Tax-inclusive price display

`arena_settings.prices_include_tax` is seeded **`true`** for the pilot.

- Every configured price — `billing_plans.hourly_rate`,
  `billing_plans.fixed_price`, `products.selling_price` — is the **final
  price the customer pays**. Tax is extracted from it, not added to it.
- The checkout total equals `subtotal − discount_total`. Tax is a breakdown
  line, not an addition (`DATABASE.md` §10, step 8).
- Acceptance tests assert against tax-inclusive customer-facing totals. A test
  that adds tax on top of a displayed price is testing the wrong mode.

**Tax-exclusive remains fully supported** at the schema and domain level — the
algorithm has both branches and both are unit-tested. What P0 does **not**
build is UI for switching modes: it is an arena setting changed by
`pricing.manage`, and changing it mid-trading is out of scope. Historical
orders are unaffected either way because the mode is captured in each line's
tax snapshot.

---

## D33 — Pricing is configuration, not code

**404 Arena's commercial rates are not yet known. This does not block M0 or
M1.**

- Pricing lives entirely in `billing_plans`, `tax_rates`,
  `tax_rate_components`, and `arena_settings`. It is **data**.
- No production rate, package price, grace period, rounding increment, or
  minimum charge may appear in Dart source, in a SQL function body, or in a
  migration that runs against production.
- Development and staging seed **explicitly labelled fixture pricing**. Fixture
  plans are named with a `[FIXTURE]` prefix so they can never be mistaken for
  real rates, and the seed script that creates them refuses to run against the
  production project.
- Worked fixture examples — one open-time plan, one fixed-duration package,
  grace, rounding, and minimum billable — are in `DATABASE.md` §16 as test
  vectors with expected outputs.

**Gate:** real production pricing must be configured in the production project,
by a tenant user, before M4 acceptance. M4 cannot be signed off against fixture
pricing. This is a configuration task, not an engineering task.

---

## D34 — Supabase topology — three projects

Three **separate Supabase projects**: `development`, `staging`, `production`.

PostgreSQL schemas inside a single project are **not** used as environment
isolation. Separate projects give separate auth user pools, separate storage,
separate keys, separate RLS blast radius, and make it impossible for a
misconfigured client to reach production.

- Each project has its own URL and anon key, supplied per Flutter flavour via
  `--dart-define` at build time. No environment values are committed.
- Migrations are **forward-only** and promoted in one direction:
  `development → staging → production`. A migration reaches production only
  after applying cleanly to staging.
- The production `service_role` key never leaves server-side contexts (D37).
- **Production data is never copied into development or staging by default.**
  If a production-shaped dataset is ever needed for debugging, it is
  anonymised — member names and phone numbers replaced — and the copy is
  approved and time-boxed.
- Development and staging are seeded from `provision_arena` plus fixture data
  (D33), not from a production dump.

---

## D35 — Database testing with pgTAP

**pgTAP** is the test framework for PostgreSQL-level behaviour. Tests live in
`supabase/tests/` and run in CI against a disposable database.

Flutter tests and database tests are **separate suites with separate jobs**.
A Flutter test can never substitute for a database security test: Flutter tests
exercise the client's intent, while the security properties are enforced by
privileges, policies, constraints, and triggers that a Dart test never touches.

Milestone 1 does not exit until pgTAP covers, at minimum:

1. cross-arena isolation — no row of arena B is visible to a user of arena A
2. RLS read policies on every table, including the deny-by-default tables
3. forbidden direct writes — no `INSERT`/`UPDATE`/`DELETE` on any protected
   table as `authenticated`
4. RPC permission enforcement — each mutating RPC rejects a caller lacking its
   permission code
5. actor identity derived from `auth.uid()` — a client cannot set or influence
   an actor column
6. composite tenant foreign keys reject cross-arena references
7. one-live-session-per-station under concurrency
8. idempotent mutation replay — same key + same arguments returns the stored
   response; different arguments conflict
9. immutable financial and audit records — `UPDATE`/`DELETE` fail on
   `payments`, `inventory_movements`, `audit_logs` for every role
10. order / session tenant consistency
11. inventory movement tenant consistency

The full assertion list is `SECURITY.md` §15.

---

## D36 — Canonical phone storage

`members.phone` is stored **canonically in E.164** — `+919876543210`.

- Uniqueness (`UNIQUE (arena_id, phone) WHERE deleted_at IS NULL`) is on the
  canonical form, so `9876543210` and `+91 98765 43210` cannot both exist.
- Normalisation happens **server-side** inside the member RPCs. The client may
  pre-format for display, but the server is authoritative — otherwise two
  clients normalise differently and the uniqueness constraint is meaningless.
- The default dial code is arena configuration
  (`arena_settings.default_phone_dial_code`, `+91` for the pilot), not a
  constant in code. A bare national number is normalised using it; an input
  already starting `+` is taken as given.
- The Indian UI may accept and display a plain 10-digit mobile number. Display
  formatting is a presentation concern; storage is always E.164.
- Input that cannot be normalised to a valid E.164 number is rejected with
  `validation_failed`.

---

## D37 — `service_role` handling and backup ownership

### `service_role`

The Supabase `service_role` key bypasses RLS entirely. It is a
**backend/administrative credential only**.

It must never exist in:

- the Flutter application, in any flavour or build
- Drift, local storage, `flutter_secure_storage`, or any device
- `--dart-define` values, `.env` files, or any committed file
- application logs, crash reports, analytics, or error payloads
- CI logs, or any client-side configuration

Only the **anon key** ships in the app. It is public by definition and carries
no privilege beyond what RLS and RPC grants allow.

Holders of the production `service_role` key are named, few, and recorded. Any
manual data change made with it is unaudited by the application and is treated
as an incident to be written down (`SECURITY.md` §13).

### Secrets

No credential of any kind is committed. Environment values are supplied at
build time per flavour (D34). A committed secret is rotated, not deleted from
the tip of the branch.

### Backup and recovery

Before the pilot handles a single real transaction:

- Point-in-time recovery is **enabled on the production project**.
- A **named owner** for backup and recovery is recorded in this repository.
- A restore has been **rehearsed once** — restore to a scratch project, verify
  a known order and its payments survive, and record the wall-clock time it
  took.

Enabling PITR is not the same as knowing recovery works. The rehearsal is the
deliverable, and it gates M7 go-live, not M0.

---

## D26a — Owner Admin Web in-repo

**Amends D26.** Owner Admin Web ships in this repository as `arena-os/web/`.

Pilot may still use tablet + Studio, but commercial GA requires Owner Web.
Technical stack remains React + Vite + same Supabase RPCs. Visual SoT is the
OWNER WEB section of `404 Lobby OS.dc.html`.

D26’s ban on a separate REST backend and on putting Owner Web *outside* the
repo is lifted for the web surface only. All money/security decisions stand.

---

## D28a — Commercial CRM / wallet / memberships after CORE

**Amends D28 timing, not P0 thinness.** Memberships, wallets, coins/loyalty,
and rich CRM fields are **authorized for schema after CORE trading path**
(M7–M10 / Waves W3–W4 in `docs/commercial/ROADMAP_COMMERCIAL.md`).

They remain forbidden in the P0 trading-day cut. When built: append-only
ledgers, RPC-only member access (D19), no client-side balances.

---

## D38 — Super Admin platform schema separation

Super Admin SaaS control plane uses a dedicated `platform` schema (and/or
deployable `platform/` app). Arena staff JWTs never receive `platform.*`
grants. Impersonation is time-boxed and audited. `service_role` remains
server-only (D37).

---

## D39 — Staff UI converges on Lobby HTML shell

The production Flutter staff app adopts the Lobby OS chrome from
`404 Lobby OS.dc.html` over live Supabase data. The demo-only `main_lobby`
path is transitional and must not ship as a second product. Behaviour and
P0 feature cuts still follow `UI_SPEC.md` and DECISIONS (no shipping fake
coins before D28a modules).

---

## D40 — Commercial product catalogue (full SaaS scope)

Arena OS is specified as a **complete commercial gaming-centre OS** (staff app,
customer app, owner web, super admin, website, portal, backend) covering the
module catalogue in `docs/commercial/PRD.md`.

This does **not** authorize redesign of money, tenancy, RPC, or offline rules
(D01–D25, D29–D37). It authorizes **additive** product scope and documentation.
Implementation is wave-ordered (`docs/commercial/ROADMAP_COMMERCIAL.md`);
documenting a module does not skip CORE sequencing.

404 Arena remains pilot data only (D33).

---

## D41 — Platform billing topology

SaaS subscriptions, plans, invoices, usage metering, and feature flags live in
`platform.*` (D38). Default: same Supabase project as the environment with
schema isolation. Enterprise may split a dedicated platform project later
without changing arena operational schemas.

