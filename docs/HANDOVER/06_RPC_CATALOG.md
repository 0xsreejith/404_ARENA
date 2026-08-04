# 06 — RPC Catalog

All **public** PostgREST-callable functions as of latest migrations.  
All are `SECURITY DEFINER` unless noted.  
Grant: `authenticated` except `provision_arena` → `service_role` only.

Status: **Production** = implemented + used by at least one client · **Backend only** = exists, thin/no UI · **Partial** = exists but diverges from `docs/API.md` or incomplete UI.

---

## Auth & device

| RPC | Inputs | Outputs | Permission | Called from | Status |
|---|---|---|---|---|---|
| `me` | — | jsonb: user, arenas[], role, permissions, branding | auth required | Flutter AuthRepository; Web AuthContext | **Production** |
| `register_device` | arena_id, device_id, name, platform, app_version | jsonb | `station.view` | Flutter DeviceRepository; Web device.ts | **Production** |
| `provision_arena` | org_id, name, timezone, currency, dial_code, owner_user_id | uuid | service_role | Seed / ops only | **Production** |

---

## Floor & stations

| RPC | Inputs | Outputs | Permission | Called from | Status |
|---|---|---|---|---|---|
| `floor_snapshot` | arena_id | jsonb zones/stations/sessions/unbilled/seat_capacity | `station.view` | Flutter FloorRepository; Web LiveFloorGrid, Dashboard | **Production** |
| `station_set_status` | arena_id, station_id, status, reason | jsonb | `station.maintenance` | (RPC exists; limited UI) | **Backend only** |
| `unbilled_sessions` | arena_id | jsonb | `session.view` | Via floor billing path / available | **Production** |

---

## Sessions

| RPC | Inputs | Outputs | Permission | Flutter | Web | Status |
|---|---|---|---|---|---|---|
| `session_start` | arena, session_id, station_id, billing_plan_id, member_id?, game_id?, player_count, client_at, idempotency_key | jsonb | `session.start` | FloorScreen (partial params) | LiveFloorGrid | **Partial** |
| `session_pause` | arena, session_id, idempotency_key | jsonb | `session.pause` | Floor | LiveFloor | **Production** |
| `session_resume` | arena, session_id, idempotency_key | jsonb | `session.resume` | Floor | LiveFloor | **Production** |
| `session_stop` | arena, session_id, idempotency_key | jsonb | `session.stop` | Floor | LiveFloor | **Production** |

**Not implemented:** `session_extend`, `session_cancel` (in API.md).

---

## Checkout & orders

| RPC | Inputs | Outputs | Permission | Flutter | Web | Status |
|---|---|---|---|---|---|---|
| `checkout_open` | arena, order_id, session_id?, member_id? | jsonb | `payment.create` | CheckoutRepository | CheckoutPanel | **Production** |
| `order_add_product` | arena, order_id, order_item_id, product_id, quantity | jsonb | `inventory.sell` | thin | thin | **Partial** |
| `order_apply_discount` | arena, order_id, kind, value, reason | jsonb | `discount.apply` | Checkout | — | **Partial** |
| `order_preview` | arena, order_id | jsonb (money as strings) | `payment.create` | Checkout | CheckoutPanel | **Production** |
| `order_settle` | arena, order_id, payment_id, method, amount, reference?, idempotency_key | jsonb | `payment.create` | Checkout | CheckoutPanel | **Partial** (single payment) |
| `order_void` | arena, order_id, reason | jsonb | `order.void` | thin | — | **Partial** |

**API.md name mismatches:** `order_add_item` → `order_add_product`; `order_set_discount` → `order_apply_discount`; settle uses scalars not `p_payments` array.

---

## Shifts

| RPC | Inputs | Outputs | Permission | Flutter | Web | Status |
|---|---|---|---|---|---|---|
| `shift_current` | arena_id | jsonb \| null | `shift.view` | ShiftScreen | ShiftPanel | **Production** |
| `shift_open` | arena, shift_id, opening_float, idempotency_key | jsonb | `shift.open` | Shift | ShiftPanel | **Production** |
| `shift_summary` | arena, shift_id | jsonb | `shift.view` | Shift | ShiftPanel | **Production** |
| `shift_close` | arena, shift_id, counted_cash, notes?, idempotency_key | jsonb | `shift.close` | Shift | ShiftPanel | **Production** |

---

## Missing vs API.md (not in database)

| RPC | Section |
|---|---|
| `session_extend`, `session_cancel` | Sessions |
| `member_search`, `member_get`, `member_create`, `member_update`, `member_set_blocked` | Members |
| `inventory_adjust` | Inventory |
| `sync_pull`, `outbox_discard` | Sync |
| `audit_search` | Audit |
| Admin CRUD for stations/zones/games/plans/tax/products/staff/roles | Admin |

---

## App helpers (not PostgREST)

33 functions in schema `app` — permissions, business_date, receipts, phone, audit, idempotency, algorithms (`play_charge`, `compute_order_totals`, etc.). Only membership helpers are granted to `authenticated`; clients must not call algorithms directly for money authority.

---

## Count

| Kind | Count |
|---|---|
| Public RPCs | **20** |
| App helpers | **33** |
