# 05 — Database

**Migrations:** 18 files under `supabase/migrations/` (forward-only)  
**Tables:** 28 (P0 complete per `docs/DATABASE.md`)  
**Authority:** `docs/DATABASE.md` for algorithms; this file reflects what migrations actually create.

---

## Migration order

| File | Purpose |
|---|---|
| `20260730000000_enable_pgtap.sql` | pgTAP extension |
| `20260730010000_m1_foundation.sql` | `app` schema, helpers |
| `20260730010100_m1_tenancy.sql` | orgs, arenas, profiles, roles, devices |
| `20260730010200_m1_catalogue.sql` | zones, stations, games, tax, plans, products, settings |
| `20260730010300_m1_operations.sql` | members, shifts, sessions, orders, payments, stock, audit |
| `20260730010400_m1_app_functions.sql` | auth/permission/receipt/audit/idempotency helpers |
| `20260730010500_m1_algorithms.sql` | money, tax, play_charge, order totals |
| `20260730010600_m1_rls.sql` | privileges + RLS policies |
| `20260730010700_m1_permission_catalogue.sql` | 33 permission codes |
| `20260730010800_m1_provision_arena.sql` | `provision_arena` |
| `20260804030000_m2_epic1_auth_me.sql` | branding + `me` + `register_device` |
| `20260804040000_epic2_floor_operations.sql` | floor + session RPCs |
| `20260804050000_epic3_checkout_billing.sql` | checkout RPCs |
| `20260804120000_epic3c_checkout_integrity.sql` | algorithm-aligned checkout |
| `20260804140000_epic4_auth_context.sql` | devices.platform web/desktop |
| `20260804160000_epic5_floor_billing.sql` | unbilled + preview strings |
| `20260804180000_epic6_shift_cash.sql` | shift RPCs |
| `20260804190000_epic7_floor_seat_capacity.sql` | seat_capacity on snapshot |

---

## Tables (28)

### Tenancy / identity
`organizations` · `arenas` · `arena_settings` · `profiles` · `permissions` · `roles` · `role_permissions` · `arena_users` · `devices`

### Floor / catalogue
`zones` · `station_types` · `stations` · `games` · `billing_plans` · `tax_rates` · `tax_rate_components` · `products`

### Ops / money
`members` · `shifts` · `sessions` · `orders` · `order_items` · `payments` · `product_stock` · `inventory_movements` · `receipt_counters` · `idempotency_keys` · `audit_logs`

---

## Relationships & composite keys

- Tenant boundary = **arena**
- Pattern: child `UNIQUE (id, arena_id)` + composite FK `(child_fk, arena_id) REFERENCES parent (id, arena_id)`
- `ON DELETE RESTRICT` everywhere
- Soft-delete catalogues via `deleted_at` + partial unique indexes for live rows

### Critical partial unique indexes
| Index purpose | Constraint |
|---|---|
| One open shift per arena | `shifts` status open |
| One live session per station | `sessions` active/paused |
| One live order per session | `orders` open |
| One play line per order | `order_items` type play |
| Unique receipt per arena | `orders.receipt_number` |

---

## RLS & permissions

| Layer | Behaviour |
|---|---|
| Privileges | `authenticated` has **SELECT only** on 25 tables; **no** INSERT/UPDATE/DELETE |
| No SELECT | `members`, `receipt_counters`, `idempotency_keys` |
| RLS | Enabled on all 28 tables |
| Policies | Read own arena via `app.current_arena_ids()`; audit also needs `report.view` |
| Writes | Only via SECURITY DEFINER RPCs |

Permission codes: 33 seeded (session.*, station.*, member.*, inventory.*, payment.*, discount, order.void, shift.*, report.view, arena.settings, pricing.manage, staff.*, permissions.manage).

System roles per arena: **staff**, **manager**, **owner**.

---

## Triggers (summary)

| Concern | Mechanism |
|---|---|
| `updated_at` | `app.touch_updated_at` on mutable tables |
| Tax percent | Synced from components |
| Shift/session/order transitions | Guard triggers |
| Append-only | payments, inventory_movements, audit_logs |
| `orders.paid_total` | Sum of payments |
| `product_stock` | Materialised from movements |
| Business date immutable | Forbid change after set |

---

## Audit logs

`audit_logs` — append-only; written by `app.audit` inside RPCs; client read requires `report.view`.

---

## Seed data

See `03_HARDCODED.md` §D. Creates fixture 404 Arena via `provision_arena`, staff users, GST fixtures, stations, plans, products, open shift. **Never production.**

---

## Schema extras vs DATABASE.md

| Extra | Source |
|---|---|
| `arena_settings.brand_name`, `logo_url`, `primary_color`, `accent_color` | Epic 1 |
| `devices.platform` includes `web`, `desktop` | Epic 4 |

---

## Missing / future schema (documented, not created)

From DATABASE.md §14 / commercial docs — **not in migrations**:

`pricing_rules` · memberships/wallets · `session_games` · `station_games` · expenses · cash_movements · assets · maintenance_tickets · reservations · `sync_operations` · `session_events` · platform SaaS tables

---

## Storage / Realtime

| Service | Status |
|---|---|
| Storage buckets | **None** defined |
| Realtime publications | **None** (service enabled locally; product P0 = no Realtime) |
