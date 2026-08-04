# Database

PostgreSQL via Supabase.

This document is the schema contract for P0. It is detailed enough that
migration work should not require guessing. Where it is silent, ask before
inventing.

Governing decisions: `DECISIONS.md`. Security model: `SECURITY.md`.

---

## 1. Conventions

### 1.1 Types

| Concept | Type |
|---|---|
| Money | `numeric(12,2)` — never float/real/double/money |
| Percentage | `numeric(5,2)` |
| Quantity | `numeric(12,3)` |
| Identifier | `uuid` |
| Timestamp | `timestamptz` — always UTC in storage |
| Business date | `date` |
| Structured data | `jsonb` — never `json` |
| Enumerations | `text` + `CHECK` constraint — not PostgreSQL enum types |

`text` + `CHECK` is chosen over PostgreSQL `enum` because adding or removing a
value is an ordinary migration rather than a type rewrite.

### 1.2 Schemas

| Schema | Contents | Exposed to PostgREST |
|---|---|---|
| `public` | tables and RPCs the client calls | yes |
| `app` | internal helper functions, triggers | **no** |

### 1.3 Standard columns

Every tenant-owned table:

```
id           uuid PRIMARY KEY
arena_id     uuid NOT NULL
created_at   timestamptz NOT NULL DEFAULT now()
updated_at   timestamptz NOT NULL DEFAULT now()   -- trigger-maintained
UNIQUE (id, arena_id)                             -- composite FK target
```

Catalogue tables additionally carry `deleted_at timestamptz NULL`.

Financial and operational tables additionally carry
`business_date date NOT NULL`.

**Documented exceptions to the standard shape** — these are deliberate, not
oversights:

| Table | Deviation | Why |
|---|---|---|
| `arena_settings` | `PRIMARY KEY (arena_id)`, no `id` | 1:1 with the arena; nothing references it |
| `product_stock` | `PRIMARY KEY (arena_id, product_id)`, no `id` | a materialisation, not an entity |
| `receipt_counters` | `PRIMARY KEY (arena_id, series)`, no `id` | a counter, not an entity |
| `role_permissions` | `PRIMARY KEY (role_id, permission_code)`, no `id` | a join table |
| `idempotency_keys` | `PRIMARY KEY (arena_id, key)`, no `id` | keyed by the client's key |
| `payments`, `inventory_movements`, `audit_logs` | no `updated_at` | append-only; a row never changes (§1.7) |
| `organizations`, `profiles`, `permissions` | no `arena_id`, no composite unique | not tenant-owned |

Actor columns are always named `<verb>_user_id` or `actor_user_id`, reference
`profiles(id)`, and are **set server-side** from `app.current_actor_id()`.

### 1.4 Identifier generation

Client-generated UUIDs are **required** for: `sessions`, `orders`,
`order_items`, `payments`, `members`, `inventory_movements`, `devices`.

The client supplies the `id` as an RPC parameter. This makes retries safe and
lets offline records reference each other before reaching the server.

All other tables use server-generated `gen_random_uuid()`.

### 1.5 Tenant integrity

Every tenant-owned table declares `UNIQUE (id, arena_id)` — redundant against
the primary key, present only as a composite foreign-key target.

Every foreign key **between two tenant-owned tables** is composite:

```sql
FOREIGN KEY (station_id, arena_id)
  REFERENCES stations (id, arena_id) ON DELETE RESTRICT
```

Foreign keys to `auth.users`, `profiles`, and `permissions` are simple.

A cross-arena reference is therefore rejected by the database, independently of
RLS or application code.

### 1.6 Deletion behaviour

| Class | Rule |
|---|---|
| Catalogue (`zones`, `station_types`, `stations`, `games`, `products`, `billing_plans`, `tax_rates`, `members`, `roles`) | Soft delete via `deleted_at`. Never hard-deleted. |
| Transactional / financial (`sessions`, `orders`, `order_items`, `payments`, `inventory_movements`, `shifts`, `audit_logs`) | Never deleted. Terminal status expresses removal. |
| Access control (`arena_users`) | Deactivated via `active`. Never deleted. |

Every foreign key uses `ON DELETE RESTRICT`. No `CASCADE` exists anywhere in
the P0 schema. Deleting an arena is not a supported operation in P0.

### 1.7 Append-only tables

`payments`, `inventory_movements`, `audit_logs`.

Enforced by a `BEFORE UPDATE OR DELETE` trigger that raises an exception for
**every** role, including the RPC definer. Corrections are new rows
(`reverses_payment_id`, `type = 'correction'`).

---

## 2. Helper functions (`app` schema)

All are `SECURITY DEFINER`, owned by `postgres`, and not exposed to PostgREST.

| Function | Returns | Purpose |
|---|---|---|
| `app.current_actor_id()` | `uuid` | Acting user. P0: `auth.uid()`. The single seam for future PIN switching (D04). |
| `app.current_arena_ids()` | `setof uuid` | Arenas the caller belongs to with `arena_users.active = true`. `STABLE`. Bypasses RLS, so it cannot recurse. |
| `app.is_arena_member(p_arena_id)` | `boolean` | Membership check. |
| `app.has_permission(p_arena_id, p_code)` | `boolean` | Resolves role → permissions for the caller in that arena. `STABLE`. |
| `app.require_permission(p_arena_id, p_code)` | `void` | Raises `insufficient_privilege` when false. First statement of every mutating RPC. |
| `app.business_date(p_arena_id, p_at)` | `date` | `(p_at AT TIME ZONE arenas.timezone - arena_settings.business_day_start_time)::date`. The only implementation. |
| `app.current_shift_id(p_arena_id)` | `uuid` | The single open shift, or null. |
| `app.receipt_series(p_arena_id, p_business_date)` | `text` | Series key from `arena_settings.receipt_series_mode`. The only place numbering policy lives (D31). |
| `app.normalise_phone(p_arena_id, p_raw)` | `text` | Canonical E.164 using `arena_settings.default_phone_dial_code`. Raises `validation_failed` on unparseable input (D36). |
| `app.audit(p_arena_id, p_action, p_entity_type, p_entity_id, p_metadata)` | `void` | Inserts an audit row in the caller's transaction. |
| `app.claim_idempotency(p_arena_id, p_key, p_fingerprint)` | `jsonb` | Returns the stored response on replay, or null to proceed. |
| `app.touch_updated_at()` | trigger | Maintains `updated_at`. |
| `app.forbid_mutation()` | trigger | Append-only enforcement. |

---

## 3. Tenancy and identity

### organizations

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `name` | `text NOT NULL` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

Not tenant-owned. In P0 a grouping label only (D02).

### arenas

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `organization_id` | `uuid NOT NULL` → `organizations(id)` | RESTRICT |
| `name` | `text NOT NULL` | |
| `timezone` | `text NOT NULL` | IANA name, e.g. `Asia/Kolkata` |
| `currency` | `text NOT NULL` | ISO 4217 |
| `phone` | `text NULL` | |
| `address` | `text NULL` | |
| `active` | `boolean NOT NULL DEFAULT true` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (id)` is the composite-FK target for children (`arena_id` references
`arenas(id)` directly).

### arena_settings

One row per arena. `PRIMARY KEY (arena_id)`.

| Column | Type | Notes |
|---|---|---|
| `arena_id` | `uuid PK` → `arenas(id)` | RESTRICT |
| `business_day_start_time` | `time NOT NULL DEFAULT '06:00'` | D09 |
| `prices_include_tax` | `boolean NOT NULL DEFAULT true` | D12 |
| `default_play_tax_rate_id` | `uuid NULL` | composite FK → `tax_rates` |
| `default_product_tax_rate_id` | `uuid NULL` | composite FK → `tax_rates` |
| `receipt_prefix` | `text NOT NULL DEFAULT ''` | D13 |
| `receipt_series_mode` | `text NOT NULL DEFAULT 'fixed'` | `CHECK (receipt_series_mode IN ('fixed','monthly','yearly','financial_yearly'))` |
| `receipt_fixed_series` | `text NOT NULL DEFAULT ''` | used only when mode is `fixed` |
| `receipt_financial_year_start_month` | `int NOT NULL DEFAULT 1` | `CHECK (receipt_financial_year_start_month BETWEEN 1 AND 12)`; pilot sets `4`; never hardcoded (D31) |
| `receipt_number_format` | `text NOT NULL DEFAULT '{prefix}{series}{sequence}'` | token template, see §10 |
| `receipt_number_padding` | `int NOT NULL DEFAULT 6` | |
| `default_phone_dial_code` | `text NOT NULL` | e.g. `+91`; set at provisioning (D36) |
| `low_stock_enabled` | `boolean NOT NULL DEFAULT true` | |
| `ending_threshold_minutes` | `int NOT NULL DEFAULT 10` | when a fixed-duration session starts rendering `ending` (`UI_SPEC.md` §3) |
| `max_clock_skew_minutes` | `int NOT NULL DEFAULT 15` | see §11 |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

Every value a tenant can differ on lives here. Nothing here is hardcoded in
Flutter.

### profiles

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` → `auth.users(id)` | RESTRICT |
| `display_name` | `text NOT NULL` | |
| `phone` | `text NULL` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

Not tenant-owned. A user may belong to several arenas. Read access is
restricted to users sharing an arena (see `SECURITY.md`).

### permissions

| Column | Type | Notes |
|---|---|---|
| `code` | `text PK` | e.g. `session.start` |
| `description` | `text NOT NULL` | |
| `category` | `text NOT NULL` | grouping for admin UI |

Global catalogue, not tenant-owned. Readable by all authenticated users.
Adding a code is a migration; it grants nothing until added to a role.

### roles

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | **NOT NULL** — no global roles (audit C11) |
| `code` | `text NOT NULL` | `owner`, `manager`, `staff` seeded per arena |
| `name` | `text NOT NULL` | |
| `is_system` | `boolean NOT NULL DEFAULT false` | system roles cannot be deleted |
| `deleted_at` | `timestamptz NULL` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, code) WHERE deleted_at IS NULL`.

### role_permissions

| Column | Type | Notes |
|---|---|---|
| `arena_id` | `uuid NOT NULL` | |
| `role_id` | `uuid NOT NULL` | composite FK → `roles(id, arena_id)` |
| `permission_code` | `text NOT NULL` → `permissions(code)` | RESTRICT |

`PRIMARY KEY (role_id, permission_code)`.

Arena-scoped, so one tenant can never alter another tenant's permission set.

### arena_users

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `user_id` | `uuid NOT NULL` → `profiles(id)` | RESTRICT |
| `role_id` | `uuid NOT NULL` | composite FK → `roles(id, arena_id)` |
| `active` | `boolean NOT NULL DEFAULT true` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (arena_id, user_id)`, `UNIQUE (id, arena_id)`.

One role per user per arena in P0. No per-user permission overrides.

**No `staff_pin_hash` column.** PIN switching is deferred (D04); a PIN
credential will arrive in its own table with no client read access.

### devices

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated**, stable per install |
| `arena_id` | `uuid NOT NULL` | |
| `name` | `text NOT NULL` | |
| `platform` | `text NOT NULL CHECK (platform IN ('android','ios'))` | |
| `app_version` | `text NULL` | |
| `registered_by_user_id` | `uuid NOT NULL` → `profiles(id)` | |
| `last_seen_at` | `timestamptz NULL` | throttled to one write per 15 min |
| `active` | `boolean NOT NULL DEFAULT true` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (id, arena_id)`.

**Operational telemetry, not an authorisation boundary in P0.** `device_id` is
client-asserted. Nothing is authorised on the basis of it. See `SECURITY.md`.

---

## 4. Floor configuration

### zones

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `name` | `text NOT NULL` | |
| `sort_order` | `int NOT NULL DEFAULT 0` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, name) WHERE deleted_at IS NULL`.

Provisioning seeds one default zone so a tenant never faces an empty floor.

### station_types

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `code` | `text NOT NULL` | e.g. `pc`, `ps5`, `vr` |
| `name` | `text NOT NULL` | |
| `sort_order` | `int NOT NULL DEFAULT 0` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, code) WHERE deleted_at IS NULL`.

Replaces the free-text `stations.type` (D27). Billing plans reference it.

### stations

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `zone_id` | `uuid NOT NULL` | composite FK → `zones(id, arena_id)` |
| `station_type_id` | `uuid NOT NULL` | composite FK → `station_types(id, arena_id)` |
| `name` | `text NOT NULL` | |
| `seat_capacity` | `int NOT NULL DEFAULT 1 CHECK (seat_capacity >= 1)` | |
| `status` | `text NOT NULL DEFAULT 'active'` | `CHECK (status IN ('active','maintenance','inactive'))` |
| `status_reason` | `text NULL` | required when status <> 'active' |
| `sort_order` | `int NOT NULL DEFAULT 0` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, name) WHERE deleted_at IS NULL`.

**No `hourly_rate` column.** Price lives on `billing_plans` (D10, audit C3).

`stations.status` is the **operational** status only. Play state
(`idle`/`live`/`ending`/`overtime`/`paused`) is derived by the client and never
stored (D06).

### games

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `title` | `text NOT NULL` | |
| `rating` | `text NULL` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, title) WHERE deleted_at IS NULL`.

`station_games` is **not** created in P0 — the picker lists all active games for
the arena (D28).

---

## 5. Pricing and tax configuration

### billing_plans

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `station_type_id` | `uuid NULL` | composite FK → `station_types`; null = all types |
| `name` | `text NOT NULL` | |
| `type` | `text NOT NULL` | `CHECK (type IN ('open_time','fixed_duration'))` |
| `hourly_rate` | `numeric(12,2) NULL` | |
| `duration_minutes` | `int NULL` | |
| `fixed_price` | `numeric(12,2) NULL` | |
| `grace_minutes` | `int NOT NULL DEFAULT 0 CHECK (grace_minutes >= 0)` | applies to both types, at different boundaries — see §9 |
| `rounding_increment_minutes` | `int NOT NULL DEFAULT 1 CHECK (rounding_increment_minutes >= 1)` | **`open_time` only** |
| `rounding_mode` | `text NOT NULL DEFAULT 'up'` | `CHECK (rounding_mode IN ('up','nearest','down'))`; **`open_time` only** |
| `minimum_billable_minutes` | `int NOT NULL DEFAULT 0 CHECK (minimum_billable_minutes >= 0)` | **`open_time` only** |
| `sort_order` | `int NOT NULL DEFAULT 0` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, name) WHERE deleted_at IS NULL`.

Shape constraint:

```sql
CHECK (
  (type = 'open_time'
     AND hourly_rate IS NOT NULL AND hourly_rate >= 0
     AND duration_minutes IS NULL AND fixed_price IS NULL)
  OR
  (type = 'fixed_duration'
     AND duration_minutes IS NOT NULL AND duration_minutes > 0
     AND fixed_price IS NOT NULL AND fixed_price >= 0
     AND hourly_rate IS NULL)
)
```

`pricing_rules` is **not** created in P0 (D10).

### tax_rates

A rate is a **named container for one or more components** (D31). Nothing about
any jurisdiction's tax law is hardcoded — rates and their splits are tenant
data.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `name` | `text NOT NULL` | e.g. `GST 18% (Intra-state)` |
| `percent` | `numeric(5,2) NOT NULL DEFAULT 0 CHECK (percent >= 0 AND percent <= 100)` | **trigger-maintained** sum of components; never written by a client |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, name) WHERE deleted_at IS NULL`.

A rate is never edited in place once used — editing changes future orders only,
because every order line snapshots the rate and its components (D12, D31).

Provisioning seeds a `No tax` rate with a single `0%` component, so a tenant is
never blocked and is never pre-assigned another jurisdiction's tax law.

### tax_rate_components

The source of truth for a rate's value.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `tax_rate_id` | `uuid NOT NULL` | composite FK → `tax_rates(id, arena_id)` |
| `name` | `text NOT NULL` | e.g. `CGST`, `SGST`, `IGST`, `VAT` — tenant data |
| `percent` | `numeric(5,2) NOT NULL CHECK (percent >= 0 AND percent <= 100)` | |
| `sort_order` | `int NOT NULL DEFAULT 0` | display and allocation order |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`,
`UNIQUE (arena_id, tax_rate_id, name) WHERE deleted_at IS NULL`.

Constraints and triggers:

- An `AFTER INSERT OR UPDATE OR DELETE` trigger recomputes
  `tax_rates.percent = SUM(components.percent)` for live components.
- The same trigger raises an explicit error if the sum would exceed 100, so a
  bad configuration fails with a readable message rather than tripping the
  `percent <= 100` CHECK on `tax_rates`.
- A tax rate must have **at least one live component**; the last one cannot be
  soft-deleted. A jurisdiction with no split configures a single component.
- Components are mutated only through `pricing.manage` RPCs.
- Editing a component changes **future** orders only; settled orders carry
  their own snapshot (§10).

**Example configurations — all tenant data, none of it in code:**

| Rate | Components |
|---|---|
| `No tax` | `Tax 0.00` |
| `GST 18% (Intra-state)` | `CGST 9.00` + `SGST 9.00` |
| `GST 18% (Inter-state)` | `IGST 18.00` |
| `GST 5% (Food, intra)` | `CGST 2.50` + `SGST 2.50` |

P0 applies the arena's configured **default** rate; it does **not** resolve
place of supply. Selecting intra- vs inter-state per order requires customer
GSTIN capture and is post-MVP — and needs no schema change, because it only
changes which existing `tax_rate_id` is chosen (D31).

---

## 6. Members

### members

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated** |
| `arena_id` | `uuid NOT NULL` | |
| `full_name` | `text NOT NULL` | |
| `phone` | `text NOT NULL` | **canonical E.164**, e.g. `+919876543210`; server-normalised by `app.normalise_phone` (D36) |
| `dob` | `date NULL` | |
| `blocked` | `boolean NOT NULL DEFAULT false` | |
| `blocked_reason` | `text NULL` | required when `blocked` |
| `notes` | `text NULL` | |
| `created_by_user_id` | `uuid NOT NULL` → `profiles(id)` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`, `UNIQUE (arena_id, phone) WHERE deleted_at IS NULL`.

`CHECK (blocked = false OR blocked_reason IS NOT NULL)`
`CHECK (phone ~ '^\+[1-9][0-9]{6,14}$')` — canonical E.164 only

Uniqueness is on the canonical form, so `9876543210` and `+91 98765 43210`
cannot both exist. Normalisation is **server-side** inside the member RPCs; the
client may format for display but is never authoritative (D36).

**No direct client `SELECT`.** All reads go through RPCs (D19,
`SECURITY.md`). Not included in `sync_pull`.

`membership_plans`, `member_memberships`, `wallets`, and `wallet_transactions`
are **not** created in P0 (D28).

---

## 7. Products and inventory

### products

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `name` | `text NOT NULL` | |
| `sku` | `text NULL` | |
| `selling_price` | `numeric(12,2) NOT NULL CHECK (selling_price >= 0)` | tax treatment per `arena_settings.prices_include_tax` |
| `cost_price` | `numeric(12,2) NULL CHECK (cost_price >= 0)` | |
| `tax_rate_id` | `uuid NULL` | composite FK → `tax_rates`; null falls back to arena default |
| `low_stock_threshold` | `numeric(12,3) NOT NULL DEFAULT 0` | |
| `deleted_at` | `timestamptz NULL` | |

`UNIQUE (id, arena_id)`,
`UNIQUE (arena_id, sku) WHERE sku IS NOT NULL AND deleted_at IS NULL`,
`UNIQUE (arena_id, name) WHERE deleted_at IS NULL`.

No stock column. Stock lives in `product_stock` (D20).

### inventory_movements

Append-only, signed.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated** |
| `arena_id` | `uuid NOT NULL` | |
| `product_id` | `uuid NOT NULL` | composite FK → `products(id, arena_id)` |
| `type` | `text NOT NULL` | see constraint below |
| `quantity` | `numeric(12,3) NOT NULL CHECK (quantity <> 0)` | **signed**; negative reduces stock |
| `unit_cost` | `numeric(12,2) NULL` | for `restock` / `opening` |
| `order_id` | `uuid NULL` | composite FK → `orders(id, arena_id)` |
| `order_item_id` | `uuid NULL` | composite FK → `order_items(id, arena_id)` |
| `actor_user_id` | `uuid NOT NULL` → `profiles(id)` | server-derived |
| `note` | `text NULL` | |
| `business_date` | `date NOT NULL` | |
| `created_at` | `timestamptz NOT NULL` | no `updated_at` — immutable |

`UNIQUE (id, arena_id)`.

Sign convention, enforced:

```sql
CHECK (type IN ('opening','restock','sale','wastage','staff_use','breakage','correction'))
CHECK (
  (type IN ('opening','restock')                            AND quantity > 0) OR
  (type IN ('sale','wastage','staff_use','breakage')         AND quantity < 0) OR
  (type = 'correction')
)
CHECK (type <> 'sale' OR (order_id IS NOT NULL AND order_item_id IS NOT NULL))
```

### product_stock

Materialised current stock. `PRIMARY KEY (arena_id, product_id)`.

| Column | Type | Notes |
|---|---|---|
| `arena_id` | `uuid NOT NULL` | |
| `product_id` | `uuid NOT NULL` | composite FK → `products(id, arena_id)` |
| `quantity` | `numeric(12,3) NOT NULL DEFAULT 0` | may be negative (D20) |
| `updated_at` | `timestamptz NOT NULL` | |

Maintained by an `AFTER INSERT` trigger on `inventory_movements`. Never
client-writable. Always reconstructable as
`SUM(inventory_movements.quantity)` per product — a reconciliation query must
exist and be run in acceptance testing.

---

## 8. Shifts

### shifts

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | |
| `arena_id` | `uuid NOT NULL` | |
| `business_date` | `date NOT NULL` | |
| `status` | `text NOT NULL` | `CHECK (status IN ('open','closed'))` |
| `opened_by_user_id` | `uuid NOT NULL` → `profiles(id)` | |
| `opened_at` | `timestamptz NOT NULL` | |
| `opening_float` | `numeric(12,2) NOT NULL CHECK (opening_float >= 0)` | |
| `closed_by_user_id` | `uuid NULL` → `profiles(id)` | |
| `closed_at` | `timestamptz NULL` | |
| `expected_cash` | `numeric(12,2) NULL` | computed at close |
| `counted_cash` | `numeric(12,2) NULL` | |
| `variance` | `numeric(12,2) GENERATED ALWAYS AS (counted_cash - expected_cash) STORED` | |
| `notes` | `text NULL` | |

`UNIQUE (id, arena_id)`.

**One open shift per arena** (D30):

```sql
CREATE UNIQUE INDEX shifts_one_open_per_arena
  ON shifts (arena_id) WHERE status = 'open';
```

`CHECK (status = 'open' OR (closed_at IS NOT NULL AND closed_by_user_id IS NOT NULL
        AND expected_cash IS NOT NULL AND counted_cash IS NOT NULL))`

**Expected cash formula** (computed server-side inside `shift_close`):

```
expected_cash = opening_float
              + SUM(payments.amount) WHERE payments.shift_id = this AND method = 'cash'
```

Cash paid out of the drawer is not modelled in P0 and will show as negative
variance (D29). The close screen requires `notes` when `variance <> 0`.

---

## 9. Sessions

### sessions

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated** |
| `arena_id` | `uuid NOT NULL` | |
| `station_id` | `uuid NOT NULL` | composite FK → `stations(id, arena_id)` |
| `member_id` | `uuid NULL` | composite FK → `members(id, arena_id)`; null = walk-in |
| `game_id` | `uuid NULL` | composite FK → `games(id, arena_id)` |
| `billing_plan_id` | `uuid NOT NULL` | composite FK → `billing_plans(id, arena_id)` |
| `opened_in_shift_id` | `uuid NULL` | composite FK → `shifts(id, arena_id)`. **Informational only — never used for money** (D08) |
| `status` | `text NOT NULL` | `CHECK (status IN ('active','paused','completed','cancelled'))` |
| `player_count` | `int NOT NULL DEFAULT 1 CHECK (player_count >= 1)` | does not affect price in P0 (D10) |
| `started_by_user_id` | `uuid NOT NULL` → `profiles(id)` | |
| `started_at` | `timestamptz NOT NULL` | server-clamped, see §11 |
| `planned_end_at` | `timestamptz NULL` | set for `fixed_duration`; null for `open_time` |
| `paused_at` | `timestamptz NULL` | non-null only while `status = 'paused'` |
| `total_paused_seconds` | `int NOT NULL DEFAULT 0 CHECK (total_paused_seconds >= 0)` | |
| `ended_by_user_id` | `uuid NULL` → `profiles(id)` | |
| `ended_at` | `timestamptz NULL` | |
| `end_reason` | `text NULL` | `CHECK (end_reason IS NULL OR end_reason IN ('normal','cancelled','no_show'))` |
| `pricing_snapshot` | `jsonb NOT NULL` | captured at start, immutable (D11) |
| `client_created_at` | `timestamptz NULL` | device clock at creation, for skew audit |
| `business_date` | `date NOT NULL` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (id, arena_id)`.

**One live session per station:**

```sql
CREATE UNIQUE INDEX sessions_one_live_per_station
  ON sessions (station_id) WHERE status IN ('active','paused');
```

This constraint is what makes concurrent or offline session starts safe. The
loser of the race receives a conflict error; the client surfaces it and does
not retry.

State constraints:

```sql
CHECK ((status = 'paused') = (paused_at IS NOT NULL))
CHECK (status NOT IN ('completed','cancelled')
       OR (ended_at IS NOT NULL AND ended_by_user_id IS NOT NULL AND end_reason IS NOT NULL))
CHECK (ended_at IS NULL OR ended_at >= started_at)
```

Permitted status transitions (enforced in RPCs):

```
active    → paused | completed | cancelled
paused    → active | completed | cancelled
completed → (terminal)
cancelled → (terminal)
```

`session_games` is **not** created in P0 (D28).

### Pricing snapshot contract — `schema_version: 1`

```jsonc
{
  "schema_version": 1,
  "captured_at": "2026-07-30T12:00:00Z",
  "currency": "INR",
  "billing_plan": {
    "id": "…uuid…",
    "name": "Open Play — PC",
    "type": "open_time",          // or "fixed_duration"
    "hourly_rate": "120.00",      // string decimal; null for fixed_duration
    "duration_minutes": null,     // int; null for open_time
    "fixed_price": null           // string decimal; null for open_time
  },
  "billing_policy": {
    "grace_minutes": 5,
    "rounding_increment_minutes": 15,
    "rounding_mode": "up",
    "minimum_billable_minutes": 30
  },
  "station": { "id": "…uuid…", "name": "PC-04", "station_type_code": "pc" },
  "player_count": 2,              // recorded, not priced in P0
  "tax": {
    "prices_include_tax": true,
    "play_tax_rate": {
      "id": "…uuid…",
      "name": "GST 18% (Intra-state)",
      "percent": "18.00",
      "components": [             // mirrors tax_rate_components (D31)
        { "name": "CGST", "percent": "9.00" },
        { "name": "SGST", "percent": "9.00" }
      ]
    }
  }
}
```

The session snapshot records the tax **configuration** in force when play
started. The authoritative per-line figures — `taxable_amount`, `tax_amount`,
and each component's computed `amount` — are written to
`order_items.tax_rate_snapshot` at checkout (§10), because that is when the
charge exists.

All money and percentage values are **strings** in JSON to avoid float
round-tripping. Consumers parse to `numeric` / minor-unit `int`.

### Play charge computation (normative)

Executed server-side in `checkout_open`, using the snapshot only.

```
1.  elapsed_seconds = (ended_at − started_at) − total_paused_seconds
2.  elapsed_minutes = ceil(elapsed_seconds / 60)
3.  if elapsed_minutes <= grace_minutes  →  amount = 0.00, stop

4.  open_time:
      a. billable = max(elapsed_minutes, minimum_billable_minutes)
      b. billable = round_to(billable, rounding_increment_minutes, rounding_mode)
      c. amount   = hourly_rate × billable / 60

5.  fixed_duration:
      a. overrun = max(0, elapsed_minutes − duration_minutes − grace_minutes)
      b. blocks  = 1 + ceil(overrun / duration_minutes)
      c. amount  = fixed_price × blocks

6.  amount = round(amount, 2)   -- half-up
```

**`minimum_billable_minutes` and the rounding settings apply to `open_time`
only.** For a package the block *is* the minimum and the block *is* the
increment; applying a 15-minute rounding inside a 60-minute package is
meaningless. Those columns exist on every plan for uniformity and are ignored
for `fixed_duration`.

**Grace is applied at the boundary that matters for each type.** For
`open_time` it forgives a session that barely started. For `fixed_duration` it
forgives the **overrun**, so a customer two minutes past a one-hour package
pays for one package, not two — which is the entire reason grace exists. Step 3
still covers the "started and immediately stopped" case for both types.

Worked vectors for every branch are in §16.

`session_extend` adds `p_blocks × duration_minutes` to `planned_end_at` for
`fixed_duration` plans; for `open_time` plans `session_extend` is rejected —
there is nothing to extend. Extending moves the expectation and the
`ending`/`overtime` display; the charge still follows step 6 from actual
elapsed time.

---

## 10. Orders, payments, receipts

### orders

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated** |
| `arena_id` | `uuid NOT NULL` | |
| `session_id` | `uuid NULL` | composite FK → `sessions(id, arena_id)`; null = counter sale |
| `member_id` | `uuid NULL` | composite FK → `members(id, arena_id)` |
| `status` | `text NOT NULL` | `CHECK (status IN ('open','settled','void'))` |
| `subtotal` | `numeric(12,2) NOT NULL DEFAULT 0` | sum of line subtotals before discount |
| `discount_kind` | `text NULL` | `CHECK (discount_kind IS NULL OR discount_kind IN ('flat','percent'))` |
| `discount_value` | `numeric(12,2) NULL CHECK (discount_value IS NULL OR discount_value >= 0)` | |
| `discount_total` | `numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount_total >= 0)` | server-resolved |
| `discount_reason` | `text NULL` | |
| `discount_authorised_by_user_id` | `uuid NULL` → `profiles(id)` | |
| `tax_total` | `numeric(12,2) NOT NULL DEFAULT 0` | sum of line `tax_amount` |
| `total` | `numeric(12,2) NOT NULL DEFAULT 0` | |
| `paid_total` | `numeric(12,2) NOT NULL DEFAULT 0` | trigger-maintained from `payments` |
| `balance_due` | `numeric(12,2) GENERATED ALWAYS AS (total - paid_total) STORED` | |
| `receipt_sequence` | `bigint NULL` | assigned at settlement |
| `receipt_number` | `text NULL` | assigned at settlement, immutable |
| `void_reason` | `text NULL` | |
| `opened_by_user_id` | `uuid NOT NULL` → `profiles(id)` | |
| `settled_by_user_id` | `uuid NULL` → `profiles(id)` | |
| `settled_at` | `timestamptz NULL` | |
| `business_date` | `date NOT NULL` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (id, arena_id)`
`UNIQUE (session_id) WHERE session_id IS NOT NULL AND status <> 'void'` —
**one live order per session** (D07). Voided orders are excluded so a session
whose order was voided can be checked out again (`API.md` §5).
`UNIQUE (arena_id, receipt_number) WHERE receipt_number IS NOT NULL`

```sql
CHECK (discount_kind IS NULL
       OR (discount_value IS NOT NULL
           AND discount_reason IS NOT NULL
           AND discount_authorised_by_user_id IS NOT NULL))
CHECK (discount_kind <> 'percent' OR discount_value <= 100)
CHECK (status <> 'settled'
       OR (receipt_number IS NOT NULL AND settled_at IS NOT NULL
           AND settled_by_user_id IS NOT NULL AND total = paid_total))
CHECK (status <> 'void' OR void_reason IS NOT NULL)
```

**No `shift_id` column** (D08).

Transitions: `open → settled`, `open → void`. Both terminal.

### order_items

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated** |
| `arena_id` | `uuid NOT NULL` | |
| `order_id` | `uuid NOT NULL` | composite FK → `orders(id, arena_id)` |
| `type` | `text NOT NULL` | `CHECK (type IN ('play','product','adjustment'))` |
| `session_id` | `uuid NULL` | composite FK → `sessions(id, arena_id)` |
| `product_id` | `uuid NULL` | composite FK → `products(id, arena_id)` |
| `name_snapshot` | `text NOT NULL` | catalogue name at time of sale |
| `description` | `text NULL` | e.g. `18:04–20:11 · 2h 07m · rounded to 2h 15m` |
| `quantity` | `numeric(12,3) NOT NULL CHECK (quantity > 0)` | |
| `unit_price` | `numeric(12,2) NOT NULL CHECK (unit_price >= 0)` | |
| `line_subtotal` | `numeric(12,2) NOT NULL` | `quantity * unit_price`, rounded |
| `discount_amount` | `numeric(12,2) NOT NULL DEFAULT 0` | allocated share of the order discount |
| `taxable_amount` | `numeric(12,2) NOT NULL` | |
| `tax_rate_id` | `uuid NULL` | composite FK → `tax_rates(id, arena_id)` |
| `tax_rate_snapshot` | `jsonb NOT NULL` | immutable, multi-component (D12, D31) |
| `tax_amount` | `numeric(12,2) NOT NULL DEFAULT 0` | |
| `line_total` | `numeric(12,2) NOT NULL` | |
| `sort_order` | `int NOT NULL DEFAULT 0` | |
| `created_at` / `updated_at` | `timestamptz NOT NULL` | |

`UNIQUE (id, arena_id)`
`UNIQUE (order_id) WHERE type = 'play'` — at most one play line per order

```sql
CHECK (type <> 'play'    OR session_id IS NOT NULL)
CHECK (type <> 'product' OR product_id IS NOT NULL)
```

### Tax snapshot contract — `schema_version: 1`

Immutable, written once per line, and complete enough to reconstruct a tax
return without reading current configuration (D31).

Example below: a `600.00` tax-inclusive line at 18% split CGST/SGST.

```jsonc
{
  "schema_version": 1,
  "rate_id": "…uuid…",
  "name": "GST 18% (Intra-state)",
  "percent": "18.00",
  "inclusive": true,
  "taxable_amount": "508.47",
  "tax_amount": "91.53",
  "components": [
    { "name": "CGST", "percent": "9.00", "amount": "45.77" },
    { "name": "SGST", "percent": "9.00", "amount": "45.76" }
  ]
}
```

`components` mirrors the live `tax_rate_components` rows at the moment of sale,
in `sort_order`, each carrying both its configured `percent` and its **computed
`amount`**. A single-component rate produces a one-element array; an
inter-state Indian sale produces one `IGST` element. Both are
`schema_version: 1` — no future version and no table change is required (D31).

`taxable_amount` and `tax_amount` are duplicated into the snapshot as well as
into their own columns so the JSON is self-contained.

### Component allocation (normative)

`tax_amount` is computed once for the line from the rate's **total** percent
(§10, step 5), then split across components:

1. For each component in `sort_order`:
   `raw_i = taxable_amount × component.percent / 100`
2. `amount_i = floor(raw_i, 2)`
3. Distribute `tax_amount − Σ amount_i` as single-paisa increments by
   **largest remainder** of `raw_i − amount_i`, ties broken by `sort_order`

This guarantees `Σ component.amount = tax_amount` **exactly**. CGST and SGST on
an 18% line are each half, with any odd paisa assigned deterministically to the
first component rather than drifting between the two.

### Total computation (normative)

Executed server-side in `order_preview` and again inside `order_settle`.
`order_preview` performs no writes; `order_settle` recomputes rather than
trusting anything the client sent.

Let `prices_include_tax = arena_settings.prices_include_tax`.

1. Per line: `line_subtotal = round(quantity * unit_price, 2)`
2. `subtotal = SUM(line_subtotal)`
3. Resolve the order discount:
   - `flat`  → `discount_total = min(discount_value, subtotal)`
   - `percent` → `discount_total = round(subtotal * discount_value / 100, 2)`
4. **Allocate** `discount_total` across lines proportionally to
   `line_subtotal`. Assign by largest-remainder so the allocated amounts sum
   exactly to `discount_total` with no rounding drift.
5. Per line, `net = line_subtotal - discount_amount`, then:
   - **exclusive**: `taxable_amount = net`,
     `tax_amount = round(net * percent / 100, 2)`,
     `line_total = net + tax_amount`
   - **inclusive**: `taxable_amount = round(net / (1 + percent/100), 2)`,
     `tax_amount = net - taxable_amount`,
     `line_total = net`
6. Split each line's `tax_amount` across the rate's components by the
   allocation rule above, and write the snapshot
7. `tax_total = SUM(tax_amount)`
8. **exclusive**: `total = subtotal - discount_total + tax_total`
   **inclusive**: `total = subtotal - discount_total`
9. All rounding is half-up to 2 decimal places.

**The pilot runs inclusive** (D32): the displayed price *is* the price the
customer pays, tax is extracted from it, and `total = subtotal − discount_total`.
Acceptance tests assert against tax-inclusive customer-facing totals. The
exclusive branch stays fully supported and unit-tested, because `percent` and
`inclusive` are captured per line — changing the arena setting never alters a
historical order.

### payments

Append-only.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | **client-generated** |
| `arena_id` | `uuid NOT NULL` | |
| `order_id` | `uuid NOT NULL` | composite FK → `orders(id, arena_id)` |
| `shift_id` | `uuid NOT NULL` | composite FK → `shifts(id, arena_id)`. **The only shift linkage used for cash** (D08) |
| `method` | `text NOT NULL` | `CHECK (method IN ('cash','upi','card'))` |
| `amount` | `numeric(12,2) NOT NULL CHECK (amount <> 0)` | signed |
| `reverses_payment_id` | `uuid NULL` | composite FK → `payments(id, arena_id)` |
| `reference` | `text NULL` | UPI ref / card auth code |
| `actor_user_id` | `uuid NOT NULL` → `profiles(id)` | server-derived |
| `business_date` | `date NOT NULL` | |
| `created_at` | `timestamptz NOT NULL` | no `updated_at` — immutable |

`UNIQUE (id, arena_id)`

```sql
CHECK ((reverses_payment_id IS NULL AND amount > 0)
    OR (reverses_payment_id IS NOT NULL AND amount < 0))
```

P0 inserts only positive rows. The reversal shape exists so refunds need no
schema change (D21).

`orders.paid_total` is maintained by an `AFTER INSERT` trigger summing
`payments.amount` for the order.

### receipt_counters

`PRIMARY KEY (arena_id, series)`.

| Column | Type | Notes |
|---|---|---|
| `arena_id` | `uuid NOT NULL` | |
| `series` | `text NOT NULL` | derived from configuration, see below |
| `next_number` | `bigint NOT NULL DEFAULT 1` | |
| `updated_at` | `timestamptz NOT NULL` | |

### Series derivation and number rendering (normative)

No jurisdiction's numbering rule appears in application code (D13 as amended by
D31). `app.receipt_series(p_arena_id, p_business_date) RETURNS text` reads
`arena_settings.receipt_series_mode`:

| Mode | Series value | Example |
|---|---|---|
| `fixed` | `receipt_fixed_series` verbatim | `''` or `'A'` |
| `monthly` | `YYYY-MM` of the business date | `2026-07` |
| `yearly` | `YYYY` of the business date | `2026` |
| `financial_yearly` | financial year containing the business date, using `receipt_financial_year_start_month` | `2026-27` |

`financial_yearly` with start month `4` puts 2026-07-30 in `2026-27` and
2027-03-31 in `2026-27`; 2027-04-01 begins `2027-28`. Setting start month `1`
makes it identical to `yearly`.

`order_settle`:

1. `series := app.receipt_series(arena_id, order.business_date)`
2. `SELECT … FOR UPDATE` on `receipt_counters (arena_id, series)`, inserting the
   row at `next_number = 1` if the series is new — so a new financial year
   restarts at 1 with no migration
3. `receipt_sequence := next_number`
4. Render `receipt_number` from `arena_settings.receipt_number_format` by
   substituting `{prefix}`, `{series}`, and `{sequence}`, where `{sequence}` is
   zero-padded to `receipt_number_padding`
5. Increment `next_number`

Templates are tenant data. `'{prefix}{series}/{sequence}'` with prefix `404/`
and financial-yearly mode renders `404/2026-27/000123`; `'{prefix}{sequence}'`
with fixed mode and an empty series renders `404/000123`.

Gap-free within a transaction: a rolled-back settlement releases the number.
`UNIQUE (arena_id, receipt_number)` still holds because the series is part of
the rendered string.

---

## 11. Idempotency, sync, and clock skew

### idempotency_keys

`PRIMARY KEY (arena_id, key)`.

| Column | Type | Notes |
|---|---|---|
| `arena_id` | `uuid NOT NULL` | |
| `key` | `text NOT NULL` | client-generated, unique per logical operation |
| `operation` | `text NOT NULL` | RPC name |
| `request_fingerprint` | `text NOT NULL` | hash of normalised arguments |
| `response` | `jsonb NULL` | the original successful response |
| `status` | `text NOT NULL` | `CHECK (status IN ('in_progress','succeeded','failed'))` |
| `actor_user_id` | `uuid NOT NULL` → `profiles(id)` | |
| `created_at` | `timestamptz NOT NULL` | |
| `expires_at` | `timestamptz NOT NULL DEFAULT now() + interval '30 days'` | |

Behaviour inside every mutating RPC:

1. `app.claim_idempotency(arena_id, key, fingerprint)`
2. Miss → insert `in_progress`, proceed
3. Hit, `succeeded`, matching fingerprint → **return the stored response**
4. Hit, matching fingerprint, `in_progress` → return a retryable
   `operation_in_progress` error
5. Hit, **different** fingerprint → `idempotency_key_reuse` conflict error

Keys are namespaced per arena, so a key from one tenant can never match
another's.

This is a **server-side** table. It is not the client outbox, which lives only
in Drift (D16). The `sync_operations` table from the original specification is
removed.

### Clock skew

Offline-capable RPCs (`session_start`, `session_stop`) accept
`p_client_at timestamptz` and store it as `client_created_at`.

- Authoritative timestamp `= LEAST(p_client_at, now())`
- If `p_client_at > now() + arena_settings.max_clock_skew_minutes` → reject with
  `clock_skew_exceeded`; the client moves the operation to `failed` for manual
  review and does **not** retry.
- If `now() - p_client_at > 24 hours` → reject with `stale_operation` (D18).

### sync_pull

`sync_pull(p_arena_id uuid, p_since timestamptz)` returns changed rows for the
syncable tables, including soft-deleted rows, plus `server_time`.

| Included | Excluded |
|---|---|
| `zones`, `station_types`, `stations`, `games`, `billing_plans`, `tax_rates`, `products`, `product_stock`, `arena_settings`, the open `shifts` row, and sessions that are `active`, `paused`, or completed-and-unbilled | `members` (D19), `orders`, `order_items`, `payments`, `audit_logs`, `idempotency_keys`, `devices`, `profiles`, `organizations`, `roles`, `role_permissions`, `arena_users`, `receipt_counters` |

The caller's own permission set is **not** part of `sync_pull` — it comes from
`me()` and is cached separately with the same 24-hour TTL (D18).

The client stores `server_time` and passes `server_time - 5 seconds` as the
next `p_since`, absorbing commit-ordering races. All client-side application is
an idempotent upsert keyed on `id`.

---

## 12. Audit

### audit_logs

Append-only. The only event store — `session_events` is removed (D22).

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid PK` | server-generated |
| `arena_id` | `uuid NOT NULL` | |
| `actor_user_id` | `uuid NULL` → `profiles(id)` | null only for system actions |
| `action` | `text NOT NULL` | e.g. `session.started`, `order.settled` |
| `entity_type` | `text NOT NULL` | e.g. `session`, `order`, `station` |
| `entity_id` | `uuid NOT NULL` | |
| `metadata` | `jsonb NOT NULL DEFAULT '{}'` | never contains member PII |
| `device_id` | `uuid NULL` | reported, not trusted |
| `business_date` | `date NOT NULL` | |
| `created_at` | `timestamptz NOT NULL` | no `updated_at` |

`UNIQUE (id, arena_id)`.

Written by `app.audit()` inside the acting RPC's transaction. A client cannot
perform an audited action and skip the audit row.

**Minimum audited actions in P0:**

```
session.started    session.paused     session.resumed    session.extended
session.stopped    session.cancelled
order.opened       order.item_added   order.item_removed order.discount_applied
order.settled      order.voided
payment.recorded
shift.opened       shift.closed
inventory.adjusted
station.status_changed
member.created     member.updated     member.blocked     member.unblocked
role.permissions_changed              arena_user.changed
outbox.discarded
```

Readable within an arena by holders of `report.view`. Never client-writable.

---

## 13. Indexes

Postgres does **not** create indexes for foreign keys automatically. Every
foreign key column gets one. Beyond that:

```sql
-- floor (hottest query in the product)
CREATE INDEX ON sessions (arena_id, station_id) WHERE status IN ('active','paused');
CREATE INDEX ON stations (arena_id, zone_id) WHERE deleted_at IS NULL;

-- unbilled queue
CREATE INDEX ON sessions (arena_id, business_date) WHERE status = 'completed';

-- member lookup (RPC-only, but still needs to be fast)
CREATE INDEX ON members (arena_id, phone) WHERE deleted_at IS NULL;
-- multicolumn GIN mixing a plain column with a trigram column needs btree_gin
CREATE INDEX ON members USING gin (arena_id, full_name gin_trgm_ops)
  WHERE deleted_at IS NULL;

-- money and reconciliation
CREATE INDEX ON orders (arena_id, business_date, status);
CREATE INDEX ON payments (arena_id, shift_id, method);
CREATE INDEX ON payments (order_id);

-- inventory
CREATE INDEX ON inventory_movements (arena_id, product_id, created_at DESC);

-- audit
CREATE INDEX ON audit_logs (arena_id, entity_type, entity_id, created_at DESC);
CREATE INDEX ON audit_logs (arena_id, business_date);

-- sync watermarks: one per syncable table
CREATE INDEX ON stations (arena_id, updated_at);
-- …repeat for every table in sync_pull
```

Required extensions: `pg_trgm` (member name search) and `btree_gin` (the
multicolumn GIN index above). `pgcrypto` or `pg_catalog.gen_random_uuid()` for
server-side UUIDs.

---

## 14. Table inventory

**P0 (28 tables):**

organizations · arenas · arena_settings · profiles · permissions · roles ·
role_permissions · arena_users · devices · zones · station_types · stations ·
games · billing_plans · tax_rates · tax_rate_components · members · products ·
inventory_movements · product_stock · shifts · sessions · orders · order_items ·
payments · receipt_counters · idempotency_keys · audit_logs

**Deliberately not created in P0** (D28):

`pricing_rules` · `membership_plans` · `member_memberships` · `wallets` ·
`wallet_transactions` · `session_games` · `station_games` · `expenses` ·
`cash_movements` · `assets` · `maintenance_tickets` · `reservations` ·
`sync_operations` (replaced by `idempotency_keys` + the Drift outbox) ·
`session_events` (replaced by `audit_logs`)

---

## 15. Provisioning a tenant

```
provision_arena(
  p_organization_id, p_name, p_timezone, p_currency,
  p_default_phone_dial_code, p_owner_user_id
)
```

Creates, in one transaction:

1. the `arenas` row
2. `arena_settings` with defaults, tax-rate defaults left null for now
3. system roles `owner`, `manager`, `staff` with seeded `role_permissions`
4. an `arena_users` row binding the owner to the `owner` role
5. a default zone
6. a `No tax` rate with a single `0%` component in `tax_rate_components`
7. an update to `arena_settings` pointing both tax-rate defaults at it — this
   step comes **after** step 6 because `arena_settings` has composite foreign
   keys into `tax_rates`

`receipt_counters` rows are **not** pre-created: `order_settle` inserts the row
for a series the first time that series is used, so any
`receipt_series_mode` works without provisioning knowing which one is chosen
(§10).

The function seeds **no billing plans, no products, and no station types**.
Pricing is configuration a tenant supplies (D33), and an empty catalogue is the
correct starting state.

No arena is usable without these steps. A tenant must be creatable with **no
code change and no manual SQL** — the acceptance criterion for M10.

### The pilot tenant

404 Arena is created by this same function, with `p_currency = 'INR'`,
`p_timezone = 'Asia/Kolkata'`, and `p_default_phone_dial_code = '+91'`, then
configured to:

- `prices_include_tax = true` (D32)
- `business_day_start_time` per the venue's trading hours
- `receipt_series_mode = 'financial_yearly'`,
  `receipt_financial_year_start_month = 4` (D31)
- GST rates and components entered as tenant data

Every one of those is **configuration**, not code, and none of it is compiled
into Flutter or into any SQL function body.

---

## 16. Test fixtures — not production pricing

> **These are test vectors, not 404 Arena's rates.** They exist so the pricing,
> tax, and rounding algorithms can be tested before commercial rates are known
> (D33). Real production pricing is configured by a tenant user before M4
> acceptance and is never committed to this repository.
>
> Fixture rows are named with a `[FIXTURE]` prefix so they can never be
> mistaken for real configuration, and the seed script that creates them
> **refuses to run against the production project**.

### 16.1 Fixture arena configuration

```
currency                            INR
timezone                            Asia/Kolkata
prices_include_tax                  true
business_day_start_time             06:00
default_phone_dial_code             +91
receipt_prefix                      FIX/
receipt_series_mode                 financial_yearly
receipt_financial_year_start_month  4
receipt_number_format               {prefix}{series}/{sequence}
receipt_number_padding              6
```

### 16.2 Fixture tax rate

`[FIXTURE] GST 18% (Intra-state)` — set as both the play and product default.

| Component | Percent | sort_order |
|---|---|---|
| CGST | 9.00 | 1 |
| SGST | 9.00 | 2 |

`tax_rates.percent` is therefore `18.00`, maintained by trigger.

A second fixture rate `[FIXTURE] GST 18% (Inter-state)` with a single
`IGST 18.00` component exists solely to prove the multi-component schema
handles both shapes. P0 never selects it automatically.

### 16.3 Fixture billing plans

**A — open-time**, `[FIXTURE] PC Open Play`

```
type                        open_time
hourly_rate                 120.00
grace_minutes               5
minimum_billable_minutes    30
rounding_increment_minutes  15
rounding_mode               up
```

**B — fixed-duration**, `[FIXTURE] PS5 1-Hour Pack`

```
type              fixed_duration
duration_minutes  60
fixed_price       150.00
grace_minutes     5
```

### 16.4 Play charge vectors

Plan A — exercises grace, minimum, rounding, and pause exclusion:

| # | Elapsed | Paused | Billable after §9 | Amount | Branch tested |
|---|---|---|---|---|---|
| A1 | 4m 00s | 0 | — | `0.00` | inside grace |
| A2 | 5m 00s | 0 | — | `0.00` | grace boundary is inclusive |
| A3 | 6m 00s | 0 | 30 | `60.00` | just past grace → minimum applies |
| A4 | 1h 07m | 0 | 75 | `150.00` | 67 rounds up to 75 |
| A5 | 2h 00m | 0 | 120 | `240.00` | exact increment, no movement |
| A6 | 2h 11m wall | 10m | 135 | `270.00` | 121 billable → rounds to 135 |

Plan B — exercises package blocks and overrun grace:

| # | Elapsed | Overrun | Blocks | Amount | Branch tested |
|---|---|---|---|---|---|
| B1 | 3m | — | — | `0.00` | inside grace |
| B2 | 45m | 0 | 1 | `150.00` | within the package |
| B3 | 62m | 0 | 1 | `150.00` | **overrun inside grace — not double-charged** |
| B4 | 66m | 1 | 2 | `300.00` | overrun past grace |
| B5 | 125m | 60 | 2 | `300.00` | grace shifts each block boundary |
| B6 | 126m | 61 | 3 | `450.00` | third block starts |

B3 is the vector that would have failed the previous specification.

### 16.5 Tax and total vectors

All inclusive (D32), using the fixture rate. Verifies §10 and the component
allocation rule.

**T1 — single line, no discount, clean split**

```
play line 150.00 (from A4)
  subtotal        150.00
  discount          0.00
  taxable         127.12   = round(150 / 1.18, 2)
  tax_amount       22.88
    CGST           11.44
    SGST           11.44
  total           150.00   -- inclusive: total = subtotal − discount
```

**T2 — odd paisa, largest-remainder allocation**

```
product line 100.00
  taxable          84.75   = round(100 / 1.18, 2)
  tax_amount       15.25
    raw per component 7.6275 → floor 7.62 each = 15.24, remainder 0.01
    tie on remainder → lowest sort_order takes it
    CGST            7.63
    SGST            7.62
  components sum   15.25   -- exactly equals tax_amount
```

**T3 — two lines with a 10% order discount**

```
  play      150.00     product   100.00
  subtotal  250.00
  discount   25.00     allocated 15.00 / 10.00 by line_subtotal

  play:     net 135.00  taxable 114.41  tax 20.59  CGST 10.30  SGST 10.29
  product:  net  90.00  taxable  76.27  tax 13.73  CGST  6.87  SGST  6.86

  tax_total  34.32
  total     225.00     = 250.00 − 25.00   (inclusive)
  Σ line_total = 135.00 + 90.00 = 225.00  -- must reconcile
```

**T4 — same play line, exclusive mode, to prove the other branch**

```
  prices_include_tax = false
  play line 150.00
  taxable   150.00
  tax        27.00      CGST 13.50   SGST 13.50
  total     177.00      = subtotal − discount + tax_total
```

### 16.6 Receipt numbering vectors

Using the §16.1 configuration:

| Business date | Series | First number of that series |
|---|---|---|
| 2026-07-30 | `2026-27` | `FIX/2026-27/000001` |
| 2027-03-31 | `2026-27` | continues the same counter |
| 2027-04-01 | `2027-28` | `FIX/2027-28/000001` — restarts at 1, no migration |

With `receipt_series_mode = 'fixed'`, empty `receipt_fixed_series`, and format
`{prefix}{sequence}`, the same order renders `FIX/000001`.

### 16.7 Phone normalisation vectors

With `default_phone_dial_code = '+91'` (D36):

| Input | Stored | Note |
|---|---|---|
| `9876543210` | `+919876543210` | bare national number |
| `098765 43210` | `+919876543210` | trunk prefix and spaces stripped |
| `+91 98765 43210` | `+919876543210` | already international |
| `+442071838750` | `+442071838750` | non-default country accepted as given |
| `12345` | rejected | `validation_failed` |

The second and third rows are the reason uniqueness is on the canonical form:
without normalisation, one member could be created three times.
