# API Contract

Arena OS has no separate REST backend. The contract is:

- **Reads** — PostgREST `SELECT` through `supabase_flutter`, scoped by RLS
- **Writes** — PostgreSQL `SECURITY DEFINER` functions called as Supabase RPC

Every mutation in this document is an RPC. Direct client writes to protected
tables are not possible (`SECURITY.md` §5).

Naming: RPC functions are `snake_case`, parameters are prefixed `p_`.

---

## 1. Universal rules

**Arena.** Every arena-scoped RPC takes `p_arena_id` and validates it against
the caller's membership first. A supplied `arena_id` is never trusted
(`SECURITY.md` §3).

**Permissions.** Every mutating RPC begins with
`app.require_permission(p_arena_id, '<code>')`.

**Actor.** Never a parameter. Derived from `app.current_actor_id()`. An RPC
signature that accepts an actor is a bug.

**Money.** Never an input except where a human genuinely enters an amount
(`p_opening_float`, `p_counted_cash`, `p_amount` on a payment,
`p_discount_value`). Prices, charges, taxes, and totals are always computed
server-side. Amounts cross the wire as **strings**; Dart parses them to
minor-unit `int` (D01).

**Identifiers.** RPCs that create `sessions`, `orders`, `order_items`,
`payments`, `members`, `inventory_movements`, or `devices` take a
**client-generated** `p_*_id uuid` (D17).

**Idempotency.** Mutating RPCs take `p_idempotency_key text`. A replay with the
same key and arguments returns the original response; the same key with
different arguments is a conflict (`DATABASE.md` §11).

**Business date.** Never a parameter. Derived server-side (D09).

**Timestamps.** `p_client_at timestamptz` appears only on offline-capable RPCs
and is clamped server-side (`OFFLINE.md` §6).

**Errors.** Every RPC raises a PostgreSQL exception with a stable code:

| Code | Meaning | Retryable |
|---|---|---|
| `insufficient_privilege` | Missing permission or arena membership | no |
| `not_found` | Entity absent or outside the caller's arena | no |
| `invalid_state` | Illegal state transition | no |
| `conflict` | Constraint violation, e.g. station already live | no |
| `idempotency_key_reuse` | Same key, different arguments | no |
| `operation_in_progress` | Concurrent call with the same key | yes |
| `clock_skew_exceeded` | Device clock outside tolerance | no |
| `stale_operation` | Queued more than 24 hours | no |
| `offline_not_permitted` | Client-side guard, never reaches the server | n/a |
| `validation_failed` | Bad arguments | no |

---

## 2. Session and context

### `me()`

No parameters. Returns:

```jsonc
{
  "user": { "id": "…", "display_name": "…", "phone": "…" },
  "arenas": [
    { "id": "…", "name": "…", "timezone": "…", "currency": "…",
      "role": { "code": "manager", "name": "Manager" },
      "permissions": ["session.start", "session.stop", "…"] }
  ]
}
```

Permissions are returned per arena. The client caches them with a 24-hour TTL
(D18).

### `register_device(p_arena_id, p_device_id, p_name, p_platform, p_app_version)`

Upserts the device row. `p_device_id` is client-generated and stable per
install. Telemetry only — nothing is authorised on it (`SECURITY.md` §6).

---

## 3. Floor

### `floor_snapshot(p_arena_id)` — read

Returns zones, station types, stations, and a summary of each live session:
session id, status, `started_at`, `planned_end_at`, `paused_at`,
`total_paused_seconds`, `player_count`, game title, and the member display name
where present.

Play state is **not** returned. The client derives it (`UI_SPEC.md` §3).

### `station_set_status(p_arena_id, p_station_id, p_status, p_reason)`

Permission: `station.maintenance`.
`p_status ∈ ('active','maintenance','inactive')`. `p_reason` is required when
the status is not `active`. Rejected when the station has a live session.

---

## 4. Sessions

### `session_start(...)` — offline-capable

```
p_arena_id, p_session_id, p_station_id, p_billing_plan_id,
p_member_id (nullable), p_game_id (nullable), p_player_count,
p_client_at, p_idempotency_key
```

Permission: `session.start`.

1. Validates the station is `active` and has no live session
2. Validates the billing plan matches the station type, or applies to all types
3. Clamps `started_at` from `p_client_at`
4. Captures `pricing_snapshot` (`DATABASE.md` §9)
5. Sets `planned_end_at` for `fixed_duration` plans, null for `open_time`
6. Sets `opened_in_shift_id` to the open shift, if any — informational only
   (D08)
7. Rejects a blocked member

Returns the created session. A race on the station returns `conflict`.

Starting a session does **not** require an open shift. That coupling is
deliberately absent (audit finding C10).

### `session_pause(p_arena_id, p_session_id, p_idempotency_key)`

Permission: `session.pause`. `active → paused`, records `paused_at`.
Online-only.

### `session_resume(p_arena_id, p_session_id, p_idempotency_key)`

Permission: `session.resume`. `paused → active`, adds the paused interval to
`total_paused_seconds`, clears `paused_at`. Online-only.

### `session_extend(p_arena_id, p_session_id, p_blocks, p_idempotency_key)`

Permission: `session.extend`. Adds `p_blocks × duration_minutes` to
`planned_end_at`. **Rejected with `invalid_state` for `open_time` plans** —
there is nothing to extend. Online-only.

### `session_stop(p_arena_id, p_session_id, p_client_at, p_idempotency_key)` — offline-capable

Permission: `session.stop`.

Ends play only. Sets `status = 'completed'`, `ended_at` (clamped),
`ended_by_user_id`, `end_reason = 'normal'`. Resumes a paused session first so
`total_paused_seconds` is final.

**Creates no order and takes no money.** Billing is a separate, online-only
step. A session stopped offline is completed and unbilled until checkout runs
(D15).

Idempotent by state: stopping an already-completed session returns the existing
session rather than erroring.

### `session_cancel(p_arena_id, p_session_id, p_reason, p_idempotency_key)`

Permission: `session.cancel`. Terminal, non-billable. Rejected once a non-void
order exists for the session. Online-only.

### `unbilled_sessions(p_arena_id)` — read

Sessions with `status = 'completed'` and **no `settled` order**. A session with
an abandoned `open` order or a `void` order therefore still appears — anything
unpaid needs attention. Drives the Unbilled sessions queue (`OFFLINE.md` §3,
`UI_SPEC.md` §7).

---

## 5. Checkout — all online-only

### `checkout_open(p_arena_id, p_order_id, p_session_id, p_idempotency_key)`

Permission: `session.stop`.

Creates the order for a completed session, or returns the existing open order
(one order per session, D07). Computes the play charge from
`sessions.pricing_snapshot` using the algorithm in `DATABASE.md` §9 and writes
it as the single `type = 'play'` line, with a human-readable `description`
covering the time range, elapsed time, and rounded billable time.

Rejected when the session is not `completed`.

### `checkout_open_counter_sale(p_arena_id, p_order_id, p_member_id, p_idempotency_key)`

Permission: `inventory.sell`. Creates an order with `session_id IS NULL`.

### `order_add_item(p_arena_id, p_order_item_id, p_order_id, p_product_id, p_quantity, p_idempotency_key)`

Permission: `inventory.sell`. Snapshots the product name, unit price, and tax
rate. Recomputes order totals. Rejected unless the order is `open`.

Stock is **not** decremented here — inventory moves at settlement, so an
abandoned order never affects stock.

### `order_remove_item(p_arena_id, p_order_item_id)`

Permission: `inventory.sell`. Cannot remove the `play` line. Recomputes totals.

### `order_set_discount(p_arena_id, p_order_id, p_kind, p_value, p_reason)`

Permission: `discount.apply` — holding it *is* the authorisation (D14).

`p_kind ∈ ('flat','percent')`. `p_reason` is required and non-empty.
Sets `discount_authorised_by_user_id` from the actor. Reallocates the discount
across taxable lines and recomputes totals (`DATABASE.md` §10).

Passing `p_kind = null` clears the discount.

### `order_preview(p_arena_id, p_order_id)` — read

Recomputes and returns the full breakdown — lines, subtotal, discount, tax,
total, amount due — **without writing**. This is the authoritative preview
required by the MVP. Flutter never computes it.

### `order_settle(p_arena_id, p_order_id, p_payments, p_idempotency_key)`

Permission: `payment.create`.

`p_payments` is a JSON array of `{ id, method, amount, reference }`, each `id`
client-generated. P0's UI sends exactly one element; the array shape means split
payment needs no contract change.

In one transaction:

1. Requires an open shift; otherwise `invalid_state`
2. **Recomputes all totals from scratch** — nothing the client sent is trusted
3. Verifies the payments sum equals the recomputed total
4. Inserts the payment rows with `shift_id` set to the open shift (D08)
5. Writes `type = 'sale'` inventory movements for every product line
6. Assigns `receipt_sequence` and `receipt_number` under a row lock (D13)
7. Sets the order to `settled`
8. Audits `order.settled` and `payment.recorded`

The station is free as soon as the session is `completed`; settlement does not
change station availability.

### `order_void(p_arena_id, p_order_id, p_reason)`

Permission: `order.void`. Allowed only while `status = 'open'`. Sets `void`
with a reason. The session returns to the unbilled queue and can be checked out
again.

Voiding a **settled** order is a refund — post-MVP (D28).

---

## 6. Members — all online-only

`members` has no direct client read path (`SECURITY.md` §8).

### `member_search(p_arena_id, p_query, p_limit)` — read

Permission: `member.view`. Requires `length(trim(p_query)) >= 3`. `p_limit`
capped at 20. A numeric query is normalised the same way as on create before
matching, so a staff member can search `9876543210` and find `+919876543210`.
Matches phone prefix and name trigram. Returns id, display name, masked phone,
and blocked flag.

### `member_get(p_arena_id, p_member_id)` — read

Permission: `member.view`. Returns the full member plus their last 10 sessions.

### `member_create(p_arena_id, p_member_id, p_full_name, p_phone, p_dob, p_idempotency_key)`

Permission: `member.create`. Normalises `p_phone` to canonical E.164 via
`app.normalise_phone` using the arena's `default_phone_dial_code` (D36) —
server-side, because two clients normalising differently would defeat the
uniqueness constraint. Unparseable input returns `validation_failed`.

A duplicate within the arena returns `conflict` with the existing member id so
the UI can offer it.

### `member_update(p_arena_id, p_member_id, p_full_name, p_phone, p_dob, p_notes)`

Permission: `member.update`.

### `member_set_blocked(p_arena_id, p_member_id, p_blocked, p_reason)`

Permission: `member.block`. `p_reason` required when blocking.

---

## 7. Products and inventory — all online-only

### Reads

Products, `product_stock`, and tax rates are read directly through PostgREST
under RLS, and cached locally.

### `inventory_adjust(p_arena_id, p_movement_id, p_product_id, p_type, p_quantity, p_unit_cost, p_note, p_idempotency_key)`

Permission: `inventory.adjust` for `wastage`, `staff_use`, `breakage`,
`correction`; `inventory.receive` for `restock` and `opening`.

`p_quantity` is signed and validated against the type (`DATABASE.md` §7).
`p_note` is required for `correction`. Movements of `type = 'sale'` cannot be
created here — only `order_settle` creates them.

---

## 8. Shift — all online-only

### `shift_current(p_arena_id)` — read

Permission: `shift.view`. The open shift, or null.

### `shift_open(p_arena_id, p_shift_id, p_opening_float, p_idempotency_key)`

Permission: `shift.open`. Rejected when a shift is already open (D30).

### `shift_summary(p_arena_id, p_shift_id)` — read

Permission: `shift.view`. Returns opening float, order and session counts, sales
by line type (`play` vs `product`), discount total, tax total, payment
breakdown by method, expected cash, and the count of unbilled sessions in the
arena.

Every figure derives from `payments.shift_id`, never from session ownership
(D08).

### `shift_close(p_arena_id, p_shift_id, p_counted_cash, p_notes, p_idempotency_key)`

Permission: `shift.close`.

1. Rejected while any order in the arena is `open` — settle or void first
2. Computes `expected_cash = opening_float + Σ cash payments for this shift`
3. Stores `counted_cash`; `variance` is generated
4. Requires `p_notes` when variance is non-zero (D29)
5. Sets `closed`

Unbilled sessions do **not** block closing — their revenue belongs to whichever
shift eventually receives the payment (D08). The count is surfaced in the
summary so staff close with their eyes open.

---

## 9. Sync

### `sync_pull(p_arena_id, p_since)` — read

Returns changed and soft-deleted rows for the cacheable tables plus
`server_time`. The authoritative include/exclude lists are in `DATABASE.md`
§11 — `members` is excluded, as is everything financial.

### `outbox_discard(p_arena_id, p_idempotency_key, p_operation, p_payload, p_reason)`

Permission: `session.cancel`. Online-only.

Records that a device is abandoning a queued mutation that never succeeded.
Writes an `outbox.discarded` audit row carrying the operation, its payload, and
the reason, then returns. The client removes the local outbox row **only after**
this call succeeds, so nothing leaves the queue without a server-side trace
(`OFFLINE.md` §5).

Writes no business data. If the idempotency key was in fact already applied,
the audit record makes that discoverable.

---

## 10. Audit

### `audit_search(p_arena_id, p_entity_type, p_entity_id, p_from, p_to, p_limit)` — read

Permission: `report.view`. Also serves the session timeline, since
`session_events` no longer exists (D22).

---

## 11. Administration

Catalogue management is RPC-only in P0. Signatures follow the same rules and
are gated as follows:

| Area | Permission |
|---|---|
| Stations — create, edit, delete | `station.update` |
| Station status (maintenance / inactive) | `station.maintenance` |
| Zones, station types, games | `arena.settings` |
| Billing plans, tax rates, **tax rate components**, arena settings | `pricing.manage` |
| Products | `product.manage` |
| Arena users — invite, deactivate, assign a role | `staff.manage` |
| Roles and role permissions | `permissions.manage` |

### `provision_arena(...)`

```
p_organization_id, p_name, p_timezone, p_currency,
p_default_phone_dial_code, p_owner_user_id
```

Creates a fully usable arena in one transaction (`DATABASE.md` §15). Seeds a
`No tax` rate with a single `0%` component and **no billing plans, products, or
station types** — pricing is tenant configuration (D33).

The acceptance criterion for M10 is that a second tenant needs this call and
nothing else.

Tax rate management RPCs operate on `tax_rate_components`; `tax_rates.percent`
is trigger-maintained and is never accepted as an input. A rate cannot be left
without a live component.

---

## 12. Not in the P0 contract

Reservations · memberships · wallet and coins · refunds and payment reversal ·
split payment UI · receipt delivery · maintenance tickets · assets · expenses ·
notifications · realtime subscriptions · reporting beyond the shift summary ·
multi-arena aggregation.
