# Arena OS — Claude Instructions

## Product

Arena OS is a multi-tenant gaming-centre management platform.

404 Arena is the first real-world tenant and pilot location. It is **not** the
product. Never hardcode anything specific to it.

This repository contains:

```
mobile/      Flutter staff/manager application (phone + tablet)
supabase/    migrations, RPCs, policies, seed data
docs/        the platform contract
```

Owner Admin Web is **outside this repository** and outside the first MVP.

---

## Read this first

`docs/DECISIONS.md` is authoritative. If any document — including this one —
contradicts it, `DECISIONS.md` wins and the other document is a bug worth
fixing.

| Question | Document |
|---|---|
| Why is it this way? | `docs/DECISIONS.md`, `docs/AUDIT.md` |
| Schema, constraints, algorithms | `docs/DATABASE.md` |
| RPC contract and error codes | `docs/API.md` |
| Authorisation model | `docs/SECURITY.md` |
| What works offline | `docs/OFFLINE.md` |
| Flutter structure | `docs/ARCHITECTURE.md` |
| What is in P0 | `docs/MVP.md` |
| Build order | `docs/ROADMAP.md` |
| Permission codes | `docs/PERMISSIONS.md` |
| Screens and states | `docs/UI_SPEC.md` |

---

## Primary workflow

Do not compromise this while implementing anything secondary:

```
staff authenticates
→ views floor
→ selects an available station
→ starts session
→ manages running session
→ optionally adds products
→ stops session
→ server calculates the bill
→ payment recorded
→ station available
→ shift totals update
```

---

## Stack

**Mobile:** Flutter · Dart · Riverpod 3 · go_router · Freezed ·
json_serializable · Drift · flutter_secure_storage · supabase_flutter

**Backend:** Supabase · PostgreSQL · Supabase Auth · `SECURITY DEFINER` RPCs

**Do not add Dio.** There is no separate REST backend (D24).
**Do not add FCM.** Notifications are post-MVP.
**Realtime is not enabled in P0** — but repository reads are `Stream`-shaped so
it can be added later without touching controllers or UI.

Do not add a dependency without being asked.

---

## Non-negotiables

These are the rules that cost the most to violate.

1. **Money is `numeric(12,2)` in Postgres and minor-unit `int` in Dart.**
   Never `double`, never `float`. `numeric` arrives as a **string** — parse
   string → `int`, never through `double`.
2. **The server owns money.** Bills, discounts, tax, totals, stock and
   permission decisions are computed server-side. Flutter may show a live
   timer; it never submits a computed amount that gets stored.
3. **Every tenant-owned relationship uses a composite tenant foreign key**
   — `(child_id, arena_id) REFERENCES parent (id, arena_id)`.
4. **All stateful and financial mutation goes through `SECURITY DEFINER`
   RPCs.** The client has no write privilege on protected tables.
5. **The server derives the actor** from `app.current_actor_id()` (today,
   `auth.uid()`). Never accept an actor as a parameter.
6. **Never trust a client-supplied `arena_id`.** Validate membership first,
   every time.
7. **Checkout is unavailable offline.** No provisional offline billing.
8. **Never claim an operation reached the server when it did not.**
9. **Never silently discard a failed mutation.**
10. **Financial and audit records are append-only.** Corrections are new rows.

---

## Sessions

Stored `sessions.status`, exhaustively:

```
active · paused · completed · cancelled
```

Derived station presentation state, computed on the client and stored nowhere:

```
idle · live · ending · overtime · paused · maintenance · inactive
```

`ending` and `overtime` need `planned_end_at`, so **open-time sessions never
show them** — they show `live` with elapsed time. That is intended.

Persist timestamps: `started_at`, `planned_end_at`, `paused_at`,
`total_paused_seconds`, `ended_at`. Flutter derives the visible timer.

**Never write to the database on a timer tick.** No cron, no scheduled job, no
per-second write. Only explicit user actions write to a session.

One live session per station is enforced by a partial unique index. That
constraint is what makes offline session starts safe — do not remove it.

---

## Pricing and tax

P0 supports **two** billing plan types: `open_time` (hourly) and
`fixed_duration` (package). Nothing else. Happy hour, weekend surcharge,
day-part and per-player rates are post-MVP.

`player_count` is recorded but does not affect price in P0.

Pricing is snapshotted onto the session at start; tax is snapshotted onto every
order line. **A change to configuration must never change a historical bill.**

The play-charge, order-total, and tax-component-allocation algorithms are
normative in `docs/DATABASE.md` §9 and §10, with worked test vectors in §16.
Implement those; do not invent variants.

**Pricing is data, never code** (D33). No rate, package price, grace period,
rounding increment, tax percentage, or component name may appear in Dart or in
a SQL function body. There is no `18`, no `9`, no `"CGST"` anywhere in source.
Development and staging use `[FIXTURE]`-prefixed pricing; production pricing is
configured by a tenant before M4 acceptance.

**Pilot is India / INR / tax-inclusive** — all three are arena configuration
(D31, D32). Tax rates are composed of configured `tax_rate_components`, so
CGST + SGST and IGST are both representable from the first schema. Component
amounts are allocated by largest remainder and must sum **exactly** to the
line's tax. Receipt series rollover is configuration
(`receipt_series_mode`), not a jurisdiction constant in code.

---

## Money model

- One checkout order belongs to at most one session (`orders.session_id`,
  unique when not null).
- Play charges are `order_items` with `type = 'play'`.
- Product sales are `type = 'product'`.
- **Payments own the shift.** `payments.shift_id` is the only shift linkage
  used for cash reconciliation. `sessions.opened_in_shift_id` is informational
  and must never appear in a money calculation.
- **Business date is independent of calendar date.** Computed server-side from
  the arena's timezone and `business_day_start_time`. Never
  `created_at::date`.
- Receipt numbers are sequential **per arena and per series**, assigned at
  settlement. The series comes from `arena_settings.receipt_series_mode`, so a
  financial-year rollover is configuration, never a code change.

---

## Multi-tenancy

The **arena** is the operational tenant boundary. Every business record carries
`arena_id`.

Never hardcode: arena name, address, station names, station types, rates,
games, products, tax rates or component names, currency, timezone, phone dial
code, receipt format, opening hours, staff, or any pricing value. All of it is
tenant configuration created by `provision_arena` and edited by tenant users.

404 Arena is seed data created through the same function as any other tenant.
That it happens to be in India is a row in a table, not an assumption in code.

---

## Environments and secrets

Three **separate Supabase projects** — `development`, `staging`, `production`
(D34). Not schemas inside one project.

- URL and anon key per Flutter flavour via `--dart-define`. Nothing committed.
- Migrations are forward-only: `development → staging → production`.
- **Production data is never copied into development or staging.**
- The **anon key only** ships in the app. `service_role` must never appear in
  Flutter, Drift, a device, `--dart-define`, the repository, logs, crash
  reports, or CI (D37).

---

## Testing

Two suites, two CI jobs, and they are not interchangeable.

- **pgTAP** in `supabase/tests/` proves the security model — isolation, RLS,
  write privileges, permission enforcement, actor derivation, composite FKs,
  concurrency, idempotency, immutability. The 20 required assertions are in
  `docs/SECURITY.md` §15 and all must pass to exit M1.
- **Flutter tests** cover the client. A Dart test can never substitute for a
  database security test: a permission check that exists only in Flutter is not
  a permission check.

---

## Permissions

Authorise by **permission code**, never by role name. The catalogue is
`docs/PERMISSIONS.md`.

The backend enforces every permission. **Hiding a Flutter button is not
authorisation.** Navigation and controls are derived from permissions, so a
user never sees a tab they cannot use.

---

## Offline

Offline **writes** in P0 are exactly two: `session_start` and `session_stop`.

Everything else — checkout, payments, shift open/close, product sales, member
creation, inventory adjustment, station status — is online-only and fails fast
with a clear reason.

Offline **reads** come from Drift. Do not write ad-hoc caching in widgets.

Queued mutations carry: client-generated UUID, `arena_id`, `idempotency_key`,
`client_created_at`, opaque versioned payload, status, attempt count.

The **client outbox** (Drift) and the **server idempotency store**
(`idempotency_keys` in Postgres) are separate things. Never merge them.

After 24 hours without a successful sync the app degrades to read-only.

The authoritative per-operation matrix is `docs/OFFLINE.md` §2. Do not
reclassify an operation without changing that table first.

---

## Members

Member PII never leaves the server in bulk.

- The client has **no `SELECT` privilege** on `members`. Reads go through RPCs.
- `members` is excluded from `sync_pull`.
- Cache only members on active or unbilled sessions plus the 20 most recently
  touched on that device, with a 24-hour TTL.
- Never log a member's name or phone. Log the id.
- Phone is stored **canonically in E.164**, normalised **server-side** using
  the arena's dial code (D36). The UI may accept and display a 10-digit
  national number, but the client never decides the canonical form — otherwise
  the uniqueness constraint is meaningless.

---

## Inventory

Stock is derived from **signed, immutable** movements. Never a mutable
`stock` column as the source of truth.

`product_stock` is a trigger-maintained materialisation and must always equal
the sum of movements.

Negative stock is permitted and flagged. A sale is never blocked by recorded
stock.

---

## Audit

Every action listed in `docs/DATABASE.md` §12 writes an audit record **inside
the same transaction as the action**, from within the RPC. A client cannot
perform an audited action and skip the record.

There is no `session_events` table. The session timeline derives from
`audit_logs`.

---

## Flutter architecture

Feature-first:

```
mobile/lib/
  app/       core/       features/       shared/
```

- `UI → Controller (Riverpod) → Repository → data source`. Widgets never touch
  Supabase or Drift directly.
- Domain models never import Flutter.
- Riverpod 3 only. No Bloc, GetX, or `package:provider`.
- **One domain model per concept.** Drift row → mapper → Freezed domain. Add a
  separate DTO only where the wire shape genuinely differs, and say why.
- Reads are `Stream`-shaped on repositories.
- One sync engine in `core/sync`; features register handlers. Never per-feature
  queueing.
- **The ticker is watched only by leaf timer widgets** and never invalidates
  the floor provider. Getting this wrong makes a 40-station floor unusable.
- One router redirect state machine, fixed evaluation order.
- One sealed `AppFailure`, mapped once at the Supabase boundary.

Do not introduce abstractions without a clear purpose. Do not create empty
folders for symmetry.

---

## UI

Dark, gaming-oriented.

```
background #07070A   surface #101018 / #171A20   text #E8EAF0
accent/live #7CFF4F   warning/ending #FFB020   danger/overtime #FF4444
```

Green for normal and live. Amber for ending and attention. Red for overtime,
errors and destructive actions. **Colour is never the only signal** — always
pair it with a label.

Staff UI prioritises speed, clarity, large touch targets, minimal typing, and
visible station state. No unnecessary animation. Phone and tablet layouts from
one responsive scaffold.

An action unavailable offline is **visibly disabled with a reason** — never
hidden, never allowed to fail after the tap.

Nothing in the UI hints at features that do not exist yet.

---

## Development rules

Before implementing a feature:

1. Read the relevant docs, starting with `DECISIONS.md`.
2. Inspect existing code and follow its patterns.
3. State a plan for anything large.
4. Implement only the requested scope.
5. Add or update tests.
6. `dart format .` · `flutter analyze` · `flutter test`
7. Report what changed.

- Do not suppress analyzer warnings to make checks pass.
- Do not modify the database schema without a migration.
- Do not put secrets in source control. The **anon key only** ships in the app;
  `service_role` never does.
- Do not commit unless asked.
- Do not implement unrelated features.
- Do not replace working architecture without explaining why.

If a specification is wrong, say so and propose the fix in `DECISIONS.md`
rather than quietly working around it.

---

## Definition of done

A feature is not complete because the UI renders. Where applicable it needs:

- domain model
- repository contract and implementation
- loading, empty, error, and permission-denied states
- server-side permission enforcement, not just a hidden button
- offline behaviour matching `docs/OFFLINE.md` §2
- audit records for anything touching money, access, or state
- tests
- analyzer passing

Prioritise correctness over volume of code.
