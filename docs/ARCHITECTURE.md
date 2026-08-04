# Architecture

Governing decisions: `DECISIONS.md`. Security: `SECURITY.md`.
Offline behaviour: `OFFLINE.md`.

---

## 1. System

```
        Flutter (staff / manager)
        phone + tablet · mobile/
                  │
                  │  supabase_flutter
                  │  · Auth
                  │  · PostgREST SELECT under RLS
                  │  · RPC for every mutation
                  ▼
        ┌───────────────────────────┐
        │  Supabase / PostgreSQL    │
        │  RLS · SECURITY DEFINER   │
        │  RPCs · triggers · audit  │
        └───────────────────────────┘
```

There is **no separate REST backend**. The database is the backend and the
security boundary.

**Not in this repository and not in the first MVP** (D26): Owner Admin Web,
customer app, lobby TV. Realtime is designed for but not enabled (D23).

Repository layout:

```
arena-os/
  mobile/      Flutter application
  supabase/    migrations, RPCs, policies, seed data
  docs/        the platform contract
```

---

## 2. Transport

`supabase_flutter` only. **Dio is not a dependency** (D24). It is added only if
a separate REST backend actually exists, which it does not.

| Traffic | Mechanism |
|---|---|
| Sign-in, token refresh | Supabase Auth |
| Catalogue and floor reads | PostgREST `SELECT`, scoped by RLS |
| Every mutation | RPC (`SECURITY DEFINER`) |
| Bulk delta sync | `sync_pull` RPC |
| Live updates | Post-MVP; the seam is `Stream<T>` on repositories |

---

## 3. Flutter layout

```
mobile/lib/

  app/
    app.dart
    bootstrap.dart
    router.dart              single redirect state machine (§8)
    theme/

  core/
    auth/                    session, active arena, permission set
    supabase/                client, RPC helpers, error mapping
    database/                Drift database, DAOs, outbox table
    sync/                    sync engine, outbox, handler registry
    connectivity/            connectivity + staleness state
    permissions/             can() provider, PermissionGate
    money/                   Money value object, parsing, formatting
    time/                    ticker, arena-timezone formatting, duration display
    errors/                  AppFailure and mappers
    logging/

  features/
    auth/
    floor/
    sessions/
    checkout/
    members/
    products/
    inventory/
    shift/
    sync_issues/

  shared/
    widgets/
    extensions/
```

Feature internals, only where the feature is large enough to need them:

```
features/sessions/
  domain/        entities, repository interfaces
  data/          repository implementations, remote + local sources
  presentation/  controllers, screens, widgets
```

Small features stay flat. Do not create empty folders for symmetry.

**Boundaries:**

- Domain models never import Flutter.
- Widgets never call Supabase, Drift, or an RPC directly.
- `UI → Controller (Riverpod) → Repository → data source`.
- `core/auth` owns the session and permission *state*; `features/auth` owns the
  sign-in *screens*. They do not overlap.

---

## 4. State management

**Riverpod 3** (D25). No Bloc, GetX, or `package:provider`.

| Use | Provider |
|---|---|
| Async load with mutations | `AsyncNotifier` |
| Sync state | `Notifier` |
| Dependency injection | `Provider` |
| Continuous streams | `StreamProvider` |

Watch narrowly. A widget that needs one field uses `select` so an unrelated
change does not rebuild it. This matters most on the floor (§7).

---

## 5. Models

Three model layers per entity is the default failure mode of this stack. Avoid
it (D25).

```
Drift row  ──mapper──▶  Freezed domain model  ──▶  UI
RPC JSON   ──mapper──▶  Freezed domain model
```

- **One domain model per concept**, Freezed, no Flutter imports.
- Drift rows are a storage detail and never leave the data layer.
- A **separate DTO type is added only where the wire shape genuinely differs**
  from the domain shape, and the reason is written down. Reuse of one Freezed
  model for JSON and domain is the norm.
- Money crosses every layer as a `Money` value object wrapping minor-unit
  `int` (D01). `numeric` arrives from Supabase as a **string**; parse
  string → `int` at the data-source boundary. Never through `double`.

---

## 6. Repositories

One repository per feature, exposing domain types only.

```dart
abstract class FloorRepository {
  Stream<Floor> watchFloor(ArenaId arenaId);   // seam for Realtime (D23)
  Future<void> refresh(ArenaId arenaId);
}
```

Reads are stream-shaped from day one. In P0 the stream is backed by Drift and
driven by the poll; enabling Realtime later swaps the source behind the
interface without touching controllers or UI.

**Read strategy:**

| Data | Source |
|---|---|
| Floor, stations, zones, station types, games, billing plans, tax rates, products, stock, arena settings, the open shift row | Drift cache, refreshed by `sync_pull` |
| Members | Server RPC only, never cached in bulk (D19) |
| Orders, order items, payments, shift **summary**, audit | Server only, not cached |

Cache what the floor needs to keep working. Nothing else.

**Write strategy:** every mutation calls an RPC. For the two offline-capable
operations the call goes through the outbox (§9); for everything else the
repository fails fast with `AppFailure.offline` when there is no connectivity.

---

## 7. Timers

The server stores timestamps. Flutter owns the visible ticking. No network
request per second, and no server write per tick (D06).

```dart
final tickerProvider = StreamProvider<DateTime>((ref) =>
    Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()));
```

Rules, because getting this wrong makes a 40-station floor unusable:

- Only a **leaf widget** watches the ticker. The station card does not.
- The ticker **never invalidates** the floor provider or triggers a fetch.
- The card frame rebuilds only when its session data actually changes.
- That leaf widget owns **both** the timer text **and** the derived
  presentation state (`live` / `ending` / `overtime`) with its colour and
  label, computed from cached timestamps per `UI_SPEC.md` §3. Putting the
  colour on the card frame instead would force the whole card to rebuild every
  second, which is the exact failure this rule exists to prevent.

Correctness after an app kill or device restart comes free: everything is
derived from `started_at`, `paused_at`, and `total_paused_seconds`.

---

## 8. Navigation

`go_router`, with **one** redirect state machine. Four independent redirect
conditions written ad hoc produce loops.

```
                  ┌──────────────┐
   no session ───▶│  /sign-in    │
                  └──────┬───────┘
                         ▼
        no arena  ┌──────────────┐
        selected ─▶│ /arenas      │
                  └──────┬───────┘
                         ▼
        stale     ┌──────────────┐
        > 24h ───▶│ /stale       │  read-only, no mutations (D18)
                  └──────┬───────┘
                         ▼
                  ┌──────────────┐
                  │  /floor      │  app shell
                  └──────────────┘
```

Evaluation order is fixed: session → arena → staleness → permission guard →
destination. Each state has exactly one entry route.

A future PIN lock inserts one state between arena and staleness and changes
nothing else (D04).

Routes carry required permission codes; the guard redirects to the first
permitted route rather than showing an empty screen. Screens contain no
navigation business logic.

---

## 9. Sync engine

One engine in `core/sync`. Features do **not** implement their own queueing —
that is how a codebase ends up with twelve divergent sync implementations.

```
Repository
   │  enqueue(operation)
   ▼
Outbox (Drift, opaque versioned JSON payload)
   │
   ▼
Sync engine ── ordered per entity ── RPC ── success ──▶ apply server result
   │                                   └── failure ──▶ backoff or dead-letter
   ▼
Sync Issues screen (pending · failed · conflict)
```

- Features register an **operation handler** with the engine: how to serialise,
  how to apply optimistically, how to reconcile the server result. The queue,
  ordering, backoff, and error classification live in one place.
- Payloads are opaque versioned JSON so a Drift migration during an app update
  cannot corrupt queued work.
- Push (drain the outbox) always runs before pull (`sync_pull`).
- Nothing is discarded silently. `failed` and `conflict` surface to a human.

Full semantics — ordering, backoff schedule, retryable errors, clock skew,
staleness — are in `OFFLINE.md`.

**Foreground only.** iOS background execution is unreliable; the engine drains
on app start, on resume, on connectivity regained, and on a foreground timer.

---

## 10. Errors

One sealed failure type, mapped once at the Supabase boundary.

```dart
sealed class AppFailure {
  // network, offline, stale, auth, permission,
  // validation, conflict, notFound, server, unknown
}
```

- `PostgrestException` and `AuthException` are mapped by the stable error codes
  in `API.md` §1. Raw exceptions never reach a controller.
- Every screen renders loading, empty, error, and permission-denied states.
- `conflict` is user-visible and actionable, never a silent retry.
- Failure messages say what happened and what to do — "Station already in use,
  refresh the floor", not "PostgrestException 23505".

---

## 11. Mutation flow

**Online (everything except session start/stop):**

```
UI → Controller → Repository → RPC → Postgres (transaction: validate,
     compute money, write, audit, store idempotency) → authoritative result
     → local cache updated from the result
```

**Offline-capable (session start and stop only):**

```
UI → Repository → Drift transaction (local write + outbox entry)
   → UI shows PENDING, never "confirmed"
   → later: sync engine → RPC → reconcile with the server result
```

The UI never shows an offline operation as confirmed, and never presents a
locally computed amount as a bill.

---

## 12. Money and time

- Money: `numeric(12,2)` in Postgres, minor-unit `int` in Dart, never `double`
  anywhere (D01). Formatting uses the arena's currency.
- Timestamps: `timestamptz` in UTC; rendered in `arenas.timezone`.
- Business date is computed **server-side only** (D09). Flutter may display a
  business date it received; it never computes one for storage.
- Device clocks are not trusted. The server clamps client timestamps
  (`OFFLINE.md` §6).

---

## 13. Testing

Two suites, two CI jobs, no overlap in responsibility.

**Database — pgTAP** (D35), in `supabase/tests/`, run against a disposable
database:

| Area | Coverage |
|---|---|
| Tenant isolation | Per-table cross-arena reads, composite FK rejection |
| Write path | No client write privilege, per-RPC permission enforcement, actor from `auth.uid()` |
| Concurrency | One live session per station, idempotent replay |
| Immutability | Append-only triggers on `payments`, `inventory_movements`, `audit_logs` |
| Computed values | The pricing, tax, component-allocation, receipt-series, and phone vectors in `DATABASE.md` §16 |

The full assertion list is `SECURITY.md` §15 — 20 items, all required for M1.

**Flutter**:

| Layer | Coverage |
|---|---|
| Sync engine | Ordering, backoff, replay, conflict, clock skew, staleness |
| Repositories | Against fakes, per feature |
| Controllers | Loading, empty, error, permission-denied |
| Widgets | Station card state derivation; golden tests for phone and tablet floor layouts |
| Money | `Money` parsing from `numeric` strings, formatting, arithmetic — never via `double` |

**Flutter tests never substitute for database security tests.** A Dart test
exercises the client's intent; the security properties live in privileges,
policies, constraints, and triggers that no Dart test touches. A permission
check that exists only in Flutter is not a permission check.

CI runs `dart format --set-exit-if-changed`, `flutter analyze`,
`flutter test`, and the pgTAP suite on every change. All four must pass.

---

## 14. Responsiveness

| Breakpoint | Layout |
|---|---|
| `< 600` | Phone: bottom navigation, single column |
| `600–1023` | Small tablet: navigation rail, two-column floor |
| `>= 1024` | Tablet: persistent rail, multi-column floor, side detail panel |

One shared responsive scaffold. Screens declare content, not layout, so phone
and tablet do not diverge screen by screen.

---

## 15. Environments

Three **separate Supabase projects** — `development`, `staging`, `production`
(D34). PostgreSQL schemas inside one project are **not** used as environment
isolation.

| Concern | Rule |
|---|---|
| Selection | Flutter flavour; URL and anon key via `--dart-define` at build time |
| Committed config | None. No `.env` with real credentials, ever |
| Migrations | Forward-only, promoted `development → staging → production`; production only after staging applies cleanly |
| Seed data | `provision_arena` + `[FIXTURE]`-prefixed pricing in dev and staging (D33); production pricing is configured by a tenant user |
| Production data | Never copied into dev or staging by default; any exception is anonymised, approved, and time-boxed |
| Keys | **Anon key only** in the app. `service_role` never reaches Flutter, Drift, a device, logs, or CI (D37) |

Full detail in `SECURITY.md` §11.

Money, timezone, tax, phone dial code, and receipt numbering are **arena
configuration**, not environment configuration. Nothing about the pilot's
country lives in a flavour.
