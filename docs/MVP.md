# MVP

## Goal

Run one real gaming centre's normal day on Arena OS.

The MVP succeeds when staff at 404 Arena operate the counter for a full trading
day without a separate session notebook, and the cash drawer balances at close.

Tenant #2 is validated **after** that, not alongside it.

---

## Scope rules

Scope is governed by `DECISIONS.md`. Two rules decide most arguments:

1. If it is not needed to run a normal day, it is post-MVP.
2. If it cannot be added later without a rewrite, it is in P0 even when it is
   invisible — composite tenant keys, RLS, idempotency, business date, pricing
   and tax snapshots, receipt numbering, client-generated UUIDs, audit.

---

# P0 — Required

## Authentication and context

- Supabase Auth sign-in with a **real user account per staff member**
- Arena selection when a user belongs to more than one arena
- Permission set fetched per arena, cached with a 24-hour TTL
- Permission-derived navigation and controls
- Device registration (telemetry only)

**Not in P0:** shared-device PIN switching, device lock, switch-staff (D04).
The architecture keeps the seam open — only `app.current_actor_id()` changes
when PIN arrives.

## Floor

- Zones, station types, stations
- Live session summary on each station card
- Locally derived timers
- Mark a station `maintenance` or `inactive`, with a reason
- Responsive phone and tablet layouts
- 10-second poll and pull-to-refresh; readable from cache when offline

Station presentation states — **derived, never stored** (D06):

```
idle · live · ending · overtime · paused · maintenance · inactive
```

`ending` and `overtime` require `planned_end_at`, so open-time sessions never
show them. `reserved` is not a P0 state.

## Sessions

- Start a walk-in session
- Start a member session
- Open-time hourly billing
- Fixed-duration package billing
- Player count (recorded; does not affect price in P0)
- Select one game
- Live timer
- Pause and resume
- Extend a fixed-duration session
- Stop a session
- Cancel a session without billing
- Unbilled sessions queue

Stored statuses: `active`, `paused`, `completed`, `cancelled`.
One live session per station, enforced by a database constraint.
Starting a session does not require an open shift.

## Checkout — online only

- **Server-authoritative** checkout preview
- Play charge computed from the session's pricing snapshot
- Products added to the order
- One manager-authorised discount — flat or percent, reason required
- **Tax-inclusive prices** (D32): the displayed price is what the customer
  pays, and tax is extracted from it
- Line-level tax with an immutable **multi-component** snapshot, so CGST + SGST
  or IGST is representable from the first order (D31)
- Sequential receipt number with a **configurable series** — the pilot uses
  Indian financial-year rollover, expressed as arena settings, not code (D31)
- Cash, UPI, card
- Settlement closes the order, assigns the receipt number, and writes the
  product stock movements. The station became available the moment the session
  was stopped, not at settlement
- Void an unsettled order, with a reason; the session returns to the unbilled
  queue

Checkout is unavailable while offline (D15). No provisional offline billing.

## Members — online only

- Search by phone or name (server-side, minimum 3 characters)
- Create a member
- Member profile with the last 10 sessions
- Blocked state with a reason

The member table is never replicated to a device (D19).

**Not in P0:** memberships, membership plans, wallet, coins.

## Products and inventory — online only

- Product list with prices
- Current stock, derived from signed immutable movements
- Low-stock indication
- Add a product to an active session's order
- Standalone counter sale
- Stock adjustments: restock, wastage, staff use, breakage, correction

Negative stock is permitted and flagged; a sale is never blocked by recorded
stock (D20).

## Shift and cash — online only

- Open a shift with an opening float
- One open shift per arena
- Shift summary: sales split by play and product, discounts, tax, payment
  breakdown by method
- Expected cash, counted cash, variance
- Close a shift, with mandatory notes when variance is non-zero

Cash reconciliation follows the **payment**, never the session (D08).

## Offline

- Floor, stations, catalogue, and stock readable from cache
- Session **start** and **stop** queue offline
- Everything else is blocked offline with a clear reason
- Sync Issues screen: pending, failed, and conflicting operations
- Read-only degradation after 24 hours without a successful sync

The authoritative operation matrix is `OFFLINE.md` §2.

## Audit

- Every action listed in `DATABASE.md` §12 writes an audit record inside the
  same transaction as the action
- Session timeline is derived from the audit log
- Audit records are append-only and unreachable by client writes

## Tenancy and security

- Arena is the tenant boundary
- Composite tenant foreign keys on every tenant-owned relationship
- RLS on every table; no client write privilege on protected tables
- All stateful and financial mutation through `SECURITY DEFINER` RPCs
- Actor derived from `auth.uid()`
- Three separate Supabase projects; production data never copied into
  development (D34)
- **pgTAP** proves the security model; Flutter tests never substitute for it
  (D35)
- `provision_arena` creates a fully usable tenant with no code change and no
  manual SQL

## Pilot configuration — data, not code

The pilot runs India / INR / tax-inclusive. Every one of those is a row in
`arenas` or `arena_settings`, never a constant in Flutter or SQL:

| Setting | Pilot value |
|---|---|
| Currency | `INR`, `numeric(12,2)` in Postgres, paise as `int` in Dart |
| Timezone | `Asia/Kolkata` |
| `prices_include_tax` | `true` (D32) |
| Tax rates | GST configured as `tax_rate_components` — no rate hardcoded (D31) |
| Receipt series | `financial_yearly`, FY start month `4` (D31) |
| Phone dial code | `+91`; storage is canonical E.164 (D36) |

**Commercial rates are not yet known and do not block M0–M3.** Development and
staging run `[FIXTURE]`-prefixed pricing with worked test vectors in
`DATABASE.md` §16. Production pricing is configured by a tenant user before M4
acceptance (D33).

---

# Accepted P0 limitations

Recorded so they are choices rather than surprises.

| Limitation | Reference |
|---|---|
| A session stopped offline is completed but **unbilled** until connectivity returns | D15 |
| Cash paid out of the drawer is not modelled and appears as negative variance; the close screen requires an explanation | D29 |
| A member session cannot be started offline unless that member is already cached; start a walk-in and correct it online | `OFFLINE.md` §2 |
| One open shift per arena — multiple registers need a migration | D30 |
| `player_count` does not affect price | D10 |
| No printed or emailed receipt; the receipt number exists and is displayed | D13 |
| Owner tasks are done in the tablet app or Supabase Studio; there is no web console | D26 |
| No Realtime — the floor refreshes on a 10-second poll | D23 |

---

# Post-MVP

## Next — directly after the pilot stabilises

- Expenses and cash drawer movements
- Receipts: print and share
- Maintenance tickets and asset registry
- Stock counts and receiving workflow
- Memberships and membership plans
- Wallet / coins
- Reservations and the `reserved` station state
- Realtime floor updates
- Notifications (FCM)
- Refunds and payment reversal
- Split payment UI

## Later

- Pricing rule engine: happy hour, weekend surcharge, day-part rates,
  per-player rates, member rates
- Provisional offline billing with variance reconciliation
- Offline product sales and member creation
- Session transfer between stations; one bill across several stations
- `session_games` and change-game tracking
- Multi-register shifts
- Owner Admin Web
- Multi-location dashboards and cross-arena reporting
- Tournaments, leaderboards, lobby TV
- Customer app and online booking
- Advanced analytics, supplier workflows, accounting integrations
