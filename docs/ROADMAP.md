# Implementation Roadmap

Ordered on one principle: **what cannot be retrofitted goes first.**

The original roadmap placed reliability, sync, idempotency and realtime at the
end, after building on fake repositories. That ordering makes the last
milestone a rewrite rather than an addition. Composite tenant keys, RLS,
client-generated UUIDs, idempotency, business date, and snapshots are therefore
in M1–M3, before the first mutation is written.

**The MVP is one gaming centre operating a full trading day (M7). Tenant #2 is
validated afterwards (M10).**

Each milestone has an exit criterion. A milestone is not done when the screens
render — it is done when the criterion passes.

---

## M0 — Decisions and foundations

- `DECISIONS.md` resolved; no open blocking decisions
- **Three Supabase projects** created — `development`, `staging`, `production`
  (D34)
- Flutter project created in `mobile/`
- Flavours mapping one-to-one onto the three projects; URL and anon key via
  `--dart-define`, nothing committed
- `Money` value object — minor-unit `int`, never `double`; parses from the
  `numeric` string the Supabase client returns
- Sealed `AppFailure` and the Supabase error mapper
- Theme, logging
- Supabase CLI migration workflow with `development → staging → production`
  promotion
- **pgTAP installed** in development and wired into CI (D35)
- CI: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`,
  and the pgTAP suite — as two separate jobs

**Exit:** CI green on an empty app, with the pgTAP job running (even with a
trivial assertion) so the harness is proven before M1 depends on it. Three
projects reachable. Zero open blocking decisions.

---

## M1 — Data and security core

Backend only. No UI.

- Schema v1 per `DATABASE.md` — all 28 tables: composite tenant foreign keys,
  partial unique indexes, CHECK constraints, `updated_at`, `deleted_at`,
  business date, indexes
- RLS on every table; no client write privilege on protected tables
- `app` helper functions, including `current_actor_id()`,
  `current_arena_ids()`, `business_date()`, `receipt_series()`, and
  `normalise_phone()`
- Append-only triggers on `payments`, `inventory_movements`, `audit_logs`;
  `tax_rates.percent` maintained from `tax_rate_components`
- Permission catalogue and seeded system roles
- `provision_arena`
- 404 Arena created as seed data through `provision_arena`, configured for
  India / INR / tax-inclusive (D31, D32)
- Fixture pricing seeded in development and staging only, `[FIXTURE]`-prefixed,
  with the seed script refusing to run against production (D33)
- **The 20 pgTAP assertions in `SECURITY.md` §15**

**Exit:** every pgTAP assertion passes. A user in arena A can neither read nor
write any row of arena B, on every one of the 28 tables; cross-arena references
are rejected by the database; and the pricing, tax, receipt-series, and phone
vectors in `DATABASE.md` §16 produce exactly the documented values.

---

## M2 — Authentication and arena context

- Supabase Auth sign-in
- `me()` — user, arenas, permissions
- Arena selection and switching
- Permission provider, `can()`, `PermissionGate`
- The router state machine in `ARCHITECTURE.md` §8
- Permission-derived navigation
- Device registration

**Progress (2026-08-04 — Epic 4):** Flutter `go_router` state machine, `canProvider` /
`PermissionGate`, permission-derived staff shell (only production `/floor`),
`register_device` on arena select, `AppFailure`/`FailureMapper` at auth and floor
RPC boundaries, D18 stale gate. `devices.platform` CHECK includes `web`/`desktop`.
Owner Web: permission-gated Live Floor only (no stub modules), `register_device`
telemetry, mapped auth/floor errors. pgTAP `17_epic4_auth_context_test.sql`.

**Exit:** a user with a reduced permission set sees a correctly reduced app,
**and** the server independently rejects the actions the UI hid.

---

## M3 — Floor and sync foundation

- Zones, station types, stations; `floor_snapshot`
- Drift cache and DAOs
- `sync_pull` with the `updated_at` watermark and soft-delete handling
- Connectivity and staleness state
- Outbox table, sync engine, and handler registry — wired but not yet used
- Station cards, state derivation, responsive floor
- Leaf-widget ticker
- 10-second poll and pull-to-refresh

**Exit:** the floor renders correctly from cache with the network off, showing
the age of the last successful sync. A 40-station floor stays smooth with all
timers running.

---

## M4 — Sessions

- `session_start`, `pause`, `resume`, `extend`, `stop`, `cancel`
- Pricing snapshot captured at start
- One-live-session-per-station constraint proven under concurrency
- Start session flow; active session screen
- Audit records for every session action
- Session start and stop routed through the outbox

**Exit:** two devices racing to start the same station produce exactly one
session, and the loser gets an actionable error. The full lifecycle is audited.

> **Configuration gate.** Real 404 Arena billing plans, GST rates, and receipt
> settings must be configured in the **production** project, by a tenant user,
> before M4 acceptance. M4 cannot be signed off against `[FIXTURE]` pricing
> (D33). This is a business task, not an engineering task, and it does not
> block M0–M3.

---

## M5 — Members

- `member_search`, `member_get`, `member_create`, `member_update`,
  `member_set_blocked`
- Member sessions; blocked-member refusal
- Restricted device-side member cache

**Progress (2026-08-05 — Epic 10 Waves A–C):** Migrations
`epic10_members_p0`, `epic10b_crm_depth`, `epic10c_wallet_loyalty` ship
RPC-only members (D19), CRM spine (`member_profiles` / tags / notes / stats /
codes), wallet + loyalty ledgers (D21), membership plans, and
`order_settle` wallet method + loyalty earn. Flutter `/members` + session
start search; Owner Web Members / Memberships live RPCs. pgTAP
`20_epic10_members_test.sql`, `21_epic10_crm_wallet_test.sql`.

**Exit:** `authenticated` has no `SELECT` privilege on `members`, member search
never bulk-downloads, and no member PII appears in any log.

---

## M6 — Checkout, orders and payments

First end-to-end value.

- `checkout_open`, counter sale, `order_add_item`, `order_remove_item`
- `order_set_discount` with a mandatory reason
- `order_preview` — server-authoritative
- Tax rates, line-level tax snapshots, inclusive and exclusive modes
- `order_settle`: payments, receipt number, stock movements
- `order_void`
- Unbilled sessions queue
- Checkout UI

**Progress (2026-08-04 — Epic 3C):** Checkout RPCs now call `app.play_charge` /
`app.compute_order_totals` and `app.next_receipt_number` (no hardcoded `1.18` /
`FIX/` prefix). `session_start` persists the normative nested
`pricing_snapshot`. pgTAP `16_epic3_checkout_billing_test.sql` asserts money
vectors through RPCs.

**Progress (2026-08-04 — Epic 5):** Floor `END & BILL` opens checkout after
`session_stop`. Unbilled queue (Flutter sheet + React panel) bills completed
sessions. `order_preview` returns money as decimal strings (D01).
`public.unbilled_sessions` added; `floor_snapshot.unbilled_sessions` includes
sessions with open/void orders until settled. Seed opens a shift so settle
works until Epic 6. pgTAP `18_epic5_floor_billing_test.sql`.

**Exit:** shadow-run a real evening at 404 Arena alongside the existing
notebook. Every total matches. Pricing, tax, and discount algorithms have unit
tests covering grace, rounding, and inclusive/exclusive tax.

---

## M7 — Shift and cash — **pilot go-live**

- `shift_open`, `shift_current`, `shift_summary`, `shift_close`
- Expected cash from `payments.shift_id` only
- Variance with mandatory notes
- Shift UI

**Progress (2026-08-04 — Epic 6):** Shift RPCs landed:
`shift_current`, `shift_open`, `shift_summary`, `shift_close`. Flutter `/shift`
and React `ShiftPanel` provide thin production UI for open/summary/close. pgTAP
`19_epic6_shift_cash_test.sql` covers one-open rejection, expected cash from
`payments.shift_id`, variance notes, and open-order close rejection.

**Exit:** 404 Arena runs a **full trading day with no notebook** and the drawer
balances at close. This is the MVP.

> **Go-live gate.** Before the first real transaction: PITR enabled on
> production, a named backup owner recorded in this repository, and one
> rehearsed restore with its wall-clock time written down (D37,
> `SECURITY.md` §13).

---

## M8 — Products and inventory

- Products and tax rate assignment
- Signed movements; trigger-maintained `product_stock`
- Low stock and negative-stock warnings
- Add to session, counter sale, adjustments
- Stock reconciliation query

**Exit:** stock derived from movements matches a physical count, and
`product_stock` matches the sum of movements exactly.

> M8 may run in parallel with M7 once M6 lands. Product lines on an order need
> M8; a play-only checkout does not.

---

## M9 — Offline enablement and reliability

The primitives exist from M3, so this milestone **enables** rather than
retrofits.

- Offline session start and stop turned on per `OFFLINE.md` §2
- Idempotency replay verified end to end
- Clock-skew clamping and rejection
- Ordered outbox drain, backoff, dead-lettering
- Sync Issues screen
- 24-hour staleness degradation
- Audit verification pass across every P0 action

**Exit:** pull the router mid-shift. Sessions start and stop; the floor stays
correct; everything reconciles on reconnect with zero duplicates and zero
silent losses. Stopped-offline sessions appear in the unbilled queue and bill
correctly.

---

## M10 — Tenant #2 validation

Proves the SaaS claim.

- Self-serve `provision_arena` path
- Arena settings, pricing, and tax configuration UI
- Staff and role management UI
- Hardcoding audit against `CLAUDE.md` — no arena name, station type, rate,
  game, product, tax value, or opening hour in source

**Exit:** a second arena is created and operated **with no code change and no
manual SQL**, by someone who did not build it.

---

## After M10

Not milestones — a prioritised backlog, in `MVP.md` under Post-MVP.

Nearest first: expenses and cash movements · receipts · maintenance tickets ·
memberships · wallet and coins · reservations · Realtime · notifications ·
refunds · split payment.

Then: the pricing rule engine · provisional offline billing · offline product
sales · session transfer and multi-station bills · multi-register shifts ·
Owner Admin Web · multi-location reporting.
