# Offline Behaviour

Gaming centres lose internet. This document defines exactly what the app does
when that happens.

Governing decisions: D15, D16, D17, D18 in `DECISIONS.md`.

**The single rule that shapes everything else: checkout is unavailable while
offline.** There is no provisional offline billing in P0.

---

## 1. Connectivity states

| State | Meaning |
|---|---|
| `online` | Last server call succeeded within the last 60 seconds |
| `degraded` | A server call has failed; retrying. Cache reads continue; queued writes accumulate |
| `offline` | No connectivity detected, or repeated failures |
| `stale` | ≥24 hours since the last successful sync (D18) |

The state is always visible in the app bar, with the age of the last successful
sync. The app never implies a write reached the server when it did not.

---

## 2. Operation matrix

Every P0 operation. Exactly one classification each.

**Legend**

- **Offline** — executes fully on-device against the cache
- **Queued** — accepted offline, written to the outbox, applied locally,
  synchronised later. The UI shows it as *pending*, never as confirmed
- **Cache** — read-only from the local cache, possibly stale, labelled as such
- **Blocked** — refused while offline, with a clear reason

### Authentication and context

| Operation | Offline | Notes |
|---|---|---|
| First sign-in | **Blocked** | Requires Supabase Auth |
| Resume an existing session | **Offline** | Valid cached token; hard-expires per §6 |
| Switch active arena | **Blocked** | Clears cached tenant data; needs a fresh fetch |
| Read own permissions | **Cache** | 24-hour TTL (D18) |
| Sign out | **Offline** | Blocked while the outbox is non-empty; see §7 |
| Register device | **Blocked** | One-time, at setup |

### Floor and stations

| Operation | Offline | Notes |
|---|---|---|
| View floor | **Cache** | Shows last-synced age |
| View station detail | **Cache** | |
| Derive station state | **Offline** | Computed from cached timestamps; no server involvement |
| Set station maintenance / unavailable | **Blocked** | Affects other devices; must not diverge |

### Sessions

| Operation | Offline | Notes |
|---|---|---|
| **Start session** | **Queued** | The only offline-capable create |
| **Stop session** | **Queued** | Ends play. Does **not** bill |
| Pause session | **Blocked** | Changes billable duration; requires the authoritative clock |
| Resume session | **Blocked** | Same |
| Extend session | **Blocked** | Same |
| Cancel session | **Blocked** | Voids a billable record |
| View live timer | **Offline** | Derived locally from `started_at` |
| View session detail | **Cache** | |

Pause, resume, and extend are blocked deliberately. Each one alters
`total_paused_seconds` or `planned_end_at`, which directly changes money, and
two offline devices could produce irreconcilable values for the same session.
Start and stop are safe because a database constraint makes the outcome
deterministic (§4).

### Checkout, orders, payments

| Operation | Offline | Notes |
|---|---|---|
| Open checkout | **Blocked** | Requires the server play-charge computation |
| Checkout preview | **Blocked** | Server-authoritative only |
| Add product to order | **Blocked** | |
| Apply discount | **Blocked** | |
| Record payment | **Blocked** | Never claim money reached the server |
| Settle order | **Blocked** | Assigns a receipt number; must be gap-free |
| Void order | **Blocked** | |
| View a past order | **Blocked** | Not cached; see §8 |

### Members

| Operation | Offline | Notes |
|---|---|---|
| Search members | **Blocked** | Server-side only (D19) |
| View a member on an active session | **Cache** | Only the cached subset |
| Create member | **Blocked** | |
| Update member | **Blocked** | |
| Block / unblock member | **Blocked** | |

Blocking member search offline is a privacy decision, not a technical one. The
member table is never on the device to search.

Consequence: **a member session cannot be started offline** unless that member
is already in the device cache. Staff start a walk-in session instead and the
attribution is corrected online. This is documented staff procedure.

### Products and inventory

| Operation | Offline | Notes |
|---|---|---|
| View product list and prices | **Cache** | |
| View current stock | **Cache** | Labelled as possibly stale |
| Sell product (counter or to a session) | **Blocked** | Financial; also prevents offline oversell |
| Adjust stock | **Blocked** | |

### Shift

| Operation | Offline | Notes |
|---|---|---|
| View current shift | **Cache** | |
| Open shift | **Blocked** | |
| View shift summary | **Blocked** | Must reflect all payments |
| Close shift | **Blocked** | Closing with unsynced operations produces a false variance |

### Sync management

| Operation | Offline | Notes |
|---|---|---|
| View pending queue | **Offline** | |
| View failed operations | **Offline** | |
| Retry a failed operation | **Blocked** | Retry needs a server |
| Discard a failed operation | **Blocked** | Requires `session.cancel`. Online-only so the discard is audited server-side at the moment it happens, rather than relying on a later sync that may never come |

---

## 3. What being offline actually costs

Stated plainly so nobody is surprised in production.

**Works offline:** the floor stays accurate, timers keep running, sessions start
and stop, staff can see what is playing and for how long.

**Does not work offline:** taking money.

A session stopped while offline becomes `completed` and **unbilled**. It appears
in the **Unbilled sessions** queue and is billed when connectivity returns.
Handling cash during an outage is an operational procedure in P0 — write it
down, reconcile it after.

This is the accepted MVP trade (D15). The alternative — provisional offline
billing — was rejected because it requires local pricing, a variance
reconciliation workflow, and a way to correct receipts that have already been
handed to a customer. That is a post-MVP project, not an MVP feature.

---

## 4. Why start and stop are safe to queue

Both are protected by a database constraint rather than by hope.

```sql
CREATE UNIQUE INDEX sessions_one_live_per_station
  ON sessions (station_id) WHERE status IN ('active','paused');
```

Two devices that both start Station 5 while offline will, on sync, produce
exactly one session. The loser receives a conflict error, the operation moves to
`failed`, and a human resolves it on the Sync Issues screen. It is never
silently dropped and never silently duplicated.

`session_stop` is idempotent by state: stopping an already-completed session
returns the existing result rather than erroring, and a replayed idempotency key
returns the original response.

---

## 5. The client outbox

A Drift table. It is **never** synchronised to the server as data — it is a
local queue (D16).

| Column | Purpose |
|---|---|
| `local_id` | autoincrement, ordering |
| `operation` | RPC name |
| `entity_id` | client-generated UUID of the affected entity |
| `arena_id` | scope |
| `payload` | **opaque versioned JSON**, never a typed Drift row |
| `payload_version` | so an app update can still send an old queued payload |
| `idempotency_key` | stable across every retry of this logical operation |
| `client_created_at` | device clock at creation |
| `status` | `pending` · `syncing` · `synced` · `failed` · `conflict` |
| `attempt_count` | |
| `next_attempt_at` | backoff schedule |
| `last_error` | |

`payload` is opaque JSON specifically so a Drift schema migration during an app
update cannot corrupt or drop a queued operation.

### Ordering

Operations sync **strictly in order per entity**. A `session_stop` never
overtakes its own `session_start`.

A failure **halts that entity's chain** — later operations for the same entity
stay queued. Unrelated entities continue. Because P0 queues only two operation
types for one entity type, this stays simple; the rule is stated now so it does
not have to be invented later.

Client-generated UUIDs make this work: `session_stop` references a session id
that exists locally before the server has ever seen it.

### Retry and dead-lettering

Exponential backoff: 2s, 4s, 8s, 30s, 2m, 10m, capped at 30 minutes.

After **8 failed attempts**, or immediately on any non-retryable error, the
operation moves to `failed`.

Non-retryable: `insufficient_privilege`, `clock_skew_exceeded`,
`stale_operation`, `idempotency_key_reuse`, constraint violations, `4xx`
validation errors.

Retryable: network errors, timeouts, `5xx`, `operation_in_progress`.

**Nothing is ever silently discarded.** A `failed` or `conflict` operation
raises a persistent badge and appears on the Sync Issues screen until a human
retries or explicitly discards it. Discarding requires connectivity and calls
`outbox_discard(p_arena_id, p_idempotency_key, p_operation, p_payload,
p_reason)`, which writes an audit record and returns before the local row is
removed. An operation is never removed from the outbox without a server-side
trace.

---

## 6. Clock skew

An offline device supplies its own clock. A wrong clock produces a wrong bill.

Every offline-capable RPC takes `p_client_at`, stores it as
`client_created_at`, and derives its authoritative timestamp as:

```
authoritative = LEAST(p_client_at, now())
```

- `p_client_at` more than `arena_settings.max_clock_skew_minutes` (default 15)
  in the future → `clock_skew_exceeded`, non-retryable, human review.
- `p_client_at` more than 24 hours in the past → `stale_operation`,
  non-retryable, human review (D18).

Both the client and server timestamps are stored, so a skew problem is
diagnosable after the fact.

---

## 7. Stale-client degradation

The client tracks `last_successful_sync_at`.

| Elapsed | Behaviour |
|---|---|
| < 24 h | Normal. Session start/stop queue; everything else needs connectivity |
| ≥ 24 h | **`stale`.** No new mutations of any kind. Read-only from cache with a persistent blocking banner. Queued operations remain queued |

Cached permissions and cached configuration expire on the same 24-hour clock. A
revoked staff member loses access within 24 hours at the very worst, and
immediately whenever the device is online.

Sign-out is blocked while the outbox contains `pending` or `failed` operations,
because signing out would strand another user's work on that device. The app
explains this and offers to sync first.

---

## 8. Pull sync

Reads are refreshed by `sync_pull(p_arena_id, p_since)` (`DATABASE.md` §11).

- Returns changed rows, **including soft-deleted rows**, plus `server_time`.
- The client stores `server_time` and passes `server_time - 5 seconds` as the
  next `p_since`. The overlap absorbs commit-ordering races; every client-side
  application is an idempotent upsert keyed on `id`, so replaying rows is
  harmless.
- Soft-deleted rows are removed locally. This is why catalogue tables use
  `deleted_at` rather than hard deletes (D17) — a hard delete is invisible to a
  watermark and would leave phantom rows on every device forever.
- Push sync (outbox drain) runs before pull sync so the device's own writes are
  reflected in what it pulls back.

**Cached locally:** zones, station types, stations, games, billing plans, tax
rates, products, current stock, arena settings, the open shift, own
permissions, active and unbilled sessions, and the restricted member subset
from D19.

**Never cached locally:** the member table, orders, order items, payments,
audit logs, other users' profiles.

Cache freshness targets while online: floor every 10 seconds (poll); catalogue
data on app start, on resume, and every 15 minutes.

---

## 9. Sync Issues screen

A required P0 surface, not a nice-to-have. Without it, "never silently discard
a failed mutation" is unenforceable.

Shows:

- pending operations with their next retry time
- failed and conflicting operations with a plain-language reason
- the age of the last successful sync
- per-operation **Retry** and **Discard**, both online-only. Discard requires
  `session.cancel` and is audited server-side before the local row is removed

Reachable from the connectivity indicator anywhere in the app, and surfaced
automatically when anything enters `failed` or `conflict`.

---

## 10. Post-MVP

Not built now; listed so the design leaves room:

- Provisional offline billing with server recalculation and a variance report
- Offline product sales with an oversell policy
- Offline member creation with deduplication on sync
- Automatic conflict resolution beyond "one wins, the other is reviewed"
- Background sync while the app is not foregrounded
- Multi-device presence so staff can see who else is on the floor
