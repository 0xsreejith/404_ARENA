# Specification Audit — 2026-07-30

Record of the audit that produced the current specification, kept so the
reasoning behind `DECISIONS.md` survives.

Audited: `CLAUDE.md` and `docs/` at the point where the repository contained
specifications only — `mobile/` and `supabase/migrations/` were empty.

The original specifications were unusually disciplined for that stage:
server-authoritative money, timestamps rather than tickers, inventory as
movements, permissions rather than role names, pricing snapshots. The problems
were not sloppiness. They were **unmade decisions presented as settled**, plus
a schema that did not yet implement the principles the prose demanded.

Status key: **Resolved** · **Accepted limitation** · **Deferred**.

---

## 1. Contradictions

| # | Finding | Resolution | Status |
|---|---|---|---|
| C1 | Offline capability and server-authoritative money were in direct conflict. `ARCHITECTURE.md` resolved it with "financial operations *may* require connectivity depending on consistency requirements" — a non-decision on the highest-stakes question in the product. | Checkout is unavailable offline. No provisional billing in P0. Offline writes limited to session start/stop. Unbilled sessions queue added as the necessary consequence. | **Resolved** — D15 |
| C2 | `ending` and `overtime` were listed both as stored session lifecycle states and as derived presentation states. Storing them requires a scheduled writer, which the same document banned. | Stored statuses reduced to `active`, `paused`, `completed`, `cancelled`. All play states derived client-side with a normative rule table. | **Resolved** — D06, `UI_SPEC.md` §3 |
| C3 | Two competing sources of price truth: `stations.hourly_rate` versus `billing_plans` + `pricing_rules`. `billing_plans` had no hourly rate field, so open-time billing had nowhere to live except the station. | `stations.hourly_rate` removed. `billing_plans.hourly_rate` added. `pricing_rules` not created in P0. | **Resolved** — D10 |
| C4 | The session→bill relationship did not exist. `sessions` had no order, `order_items` had no line type, and nothing connected a completed session to money owed. | `orders.session_id` unique-when-not-null; `order_items.type ∈ (play, product, adjustment)`. | **Resolved** — D07 |
| C5 | `reserved` was a required P0 station state while reservations were P1. | `reserved` removed from P0. Reservations post-MVP. | **Resolved** — D28 |
| C6 | `ending`/`overtime` were underivable for open-time sessions, which have no `planned_end_at` — yet all seven states were mandatory in P0. | Open-time sessions render `live` with elapsed time and never render `ending`/`overtime`. Stated as intended behaviour. | **Resolved** — `UI_SPEC.md` §3 |
| C7 | Shared-device PIN implied a device-level account, while every table's actor column and all RLS implied a real user. Unresolved, every audit record was forgeable. | PIN deferred. One Supabase user per staff member. Actor from `app.current_actor_id()`, a single seam that PIN can later occupy without schema or audit change. | **Resolved** — D04 |
| C8 | Transport specified three inconsistent ways: Dio, Supabase, and a REST API surface, with an architecture diagram showing no API tier. | `supabase_flutter` only. Dio not added. `API.md` rewritten as an RPC contract. | **Resolved** — D24 |
| C9 | Roadmap built features on fake repositories and placed sync, idempotency, and realtime last — while the Definition of Done required offline consideration per feature. M8 would have been a rewrite. | Sync primitives land in M3, before the first mutation. M9 *enables* offline rather than retrofitting it. | **Resolved** — `ROADMAP.md` |
| C10 | `sessions.shift_id` coupled play to cash. No business date, no rule for a session spanning a shift boundary, no statement on whether a shift must be open to start play. | Payments own the shift. `sessions.opened_in_shift_id` is informational only. Business date added. Starting a session does not require an open shift. | **Resolved** — D08, D09 |
| C11 | `roles.arena_id` was nullable and `role_permissions` had no arena scope — one tenant could alter another tenant's permissions. | `roles.arena_id NOT NULL`; `role_permissions` carries `arena_id` with a composite FK. System roles seeded per arena. | **Resolved** — `DATABASE.md` §3 |
| C12 | P0 displayed membership status and coin balance with no P0 way to create either. | Memberships and wallet removed from P0 entirely, including from the UI. | **Resolved** — D28 |
| C13 | Tax and discounts were P0 with no tax table, no discount model, no approver, and no line-level rate. | `tax_rates`, arena tax defaults, immutable per-line tax snapshots, and an order-level discount with mandatory reason and authoriser. | **Resolved** — D12, D14 |
| C14 | `audit_logs` and `session_events` were overlapping event stores with no authority rule. | `session_events` removed. `audit_logs` is the only store; the session timeline derives from it. | **Resolved** — D22 |
| C15 | `change-game` appeared in the API and the active-session UI but not in P0 scope. | `session_games`, `station_games`, and change-game all post-MVP. One `game_id` per session. | **Resolved** — D28 |
| C16 | Fixed navigation tabs versus configurable permissions produced dead tabs. | Navigation derived from permissions. | **Resolved** — `UI_SPEC.md` §5 |
| C17 | Repository scope was ambiguous: Flutter-and-contracts in one document, Owner Admin Web in another. | Owner Admin Web explicitly outside this repository and the first MVP. | **Resolved** — D26 |

---

## 2. Missing domain concepts

| Finding | Resolution | Status |
|---|---|---|
| **Business day.** Venues trade past midnight; every "today" report would have been wrong. | `arena_settings.business_day_start_time`, `app.business_date()`, stored `business_date` on financial rows. | **Resolved** — D09 |
| **Tax configuration**, including the unanswered question of whether prices are tax-inclusive. | `arena_settings.prices_include_tax`, `tax_rates`, per-line snapshots, normative total algorithm. | **Resolved** — D12 |
| **Receipt numbering.** Sequential per-arena numbers cannot be backfilled. | `receipt_counters` + `orders.receipt_number`, assigned under a row lock at settlement; series rollover is arena configuration. | **Resolved** — D13, D31 |
| **Pricing snapshot contract** — declared but undefined, and the most important structure in the system. | Versioned JSON contract, normative in `DATABASE.md` §9. | **Resolved** — D11 |
| **Server idempotency store**, conflated with the client outbox in `sync_operations`. | Split: Drift outbox on the device, `idempotency_keys` in Postgres. `sync_operations` removed. | **Resolved** — D16 |
| **Money type** unspecified in both Postgres and Dart. | `numeric(12,2)` and minor-unit `int`. Never `double`. | **Resolved** — D01 |
| **Order lifecycle**: no status, no `paid_total`, no `balance_due`; `payment.refund` existed with no refund model. | Order statuses, trigger-maintained `paid_total`, generated `balance_due`, signed payments with `reverses_payment_id` so refunds need no schema change. | **Resolved** — D07, D21 |
| **Rate applicability** — only a flat station rate existed. | Plans scope to a station type; `station_types` normalised. | **Resolved** — D10, D27 |
| **Rounding, grace, minimum billable duration** had no home. | Columns on `billing_plans`, captured in the snapshot, with a normative algorithm. | **Resolved** — `DATABASE.md` §9 |
| **Clock skew** — an offline device supplying `started_at` from a wrong clock produces a wrong bill. | Server clamps to `LEAST(client, now())`, rejects skew beyond a configurable tolerance, stores both timestamps. | **Resolved** — `OFFLINE.md` §6 |
| **`updated_at` / deletion strategy** — no delta sync and no delete propagation were possible. | `updated_at` everywhere, soft delete for catalogue tables, terminal statuses for transactional tables. | **Resolved** — D17 |
| **Conflict resolution had no owner, rules, or surface.** | Bounded retries, dead-lettering, and a required Sync Issues screen. | **Resolved** — `OFFLINE.md` §9 |
| **Arena settings surface** — the product promised per-tenant configuration with nowhere to store it. | `arena_settings`. | **Resolved** |
| **Tenant provisioning** — no milestone created a tenant, so the SaaS claim was untestable. | `provision_arena` in M1; tenant #2 is M10's exit criterion. | **Resolved** — D02 |
| **Membership benefits** — plans granted nothing, making memberships decorative. | Memberships deferred rather than shipped hollow. | **Deferred** — D28 |
| **Session transfer between stations; one bill across several stations.** Both routine in this business. | Not built. Recorded in the post-MVP backlog. | **Deferred** |
| **Cash drawer movements** — expected cash cannot account for money paid out. | Not modelled in P0; appears as variance, with mandatory notes at close. | **Accepted limitation** — D29 |
| **FCM had no token table**; notifications were P1 but FCM was in the stack. | Removed from the P0 stack. | **Resolved** — D28 |

---

## 3. Security

| Finding | Resolution | Status |
|---|---|---|
| **No RLS was specified anywhere**, while a Supabase client with an anon key talks to PostgREST directly. RLS *is* the authorisation system; there was none. | `SECURITY.md` defines a five-layer model with RLS on every table. | **Resolved** |
| **Client-writable money columns.** `orders.total` and `payments.amount` were ordinary columns a client could set. | `authenticated` has no write privilege on protected tables. All amounts computed inside `SECURITY DEFINER` RPCs, recomputed at settlement. | **Resolved** — D05 |
| **Actor spoofing.** Every `created_by` / `actor_id` was client-supplied. | Derived from `app.current_actor_id()`. RPC signatures do not accept actor parameters. | **Resolved** — D04 |
| **Privilege escalation.** Nothing protected `arena_users`, `roles`, `role_permissions`. | Protected tables, `permissions.manage`-gated RPCs, last-holder protection, audited. | **Resolved** — `SECURITY.md` §7 |
| **RLS recursion** — a policy on `arena_users` that reads `arena_users` recurses infinitely. | `app.current_arena_ids()` is `SECURITY DEFINER`, which breaks the cycle. Documented as a deliberate choice. | **Resolved** |
| **PIN brute force** — a 4-digit PIN with a client-readable hash. | PIN removed from P0. Documented requirements for when it returns: no client read access, rate limiting, lockout, never sole authorisation. | **Resolved** — D04 |
| **Financial and audit tables were mutable.** | `BEFORE UPDATE OR DELETE` triggers reject every role, including the definer. | **Resolved** — D21 |
| **Realtime treated as filtered rather than authorised.** | Realtime deferred; when enabled, RLS applies and `filter:` is documented as an optimisation only. | **Resolved** — D23 |
| **Local-first reads would put the full customer database on every counter tablet** — the largest PII exposure in the design. | No client `SELECT` on `members`; RPC-only access; excluded from `sync_pull`; a bounded device cache with a TTL. | **Resolved** — D19 |
| Idempotency keys not namespaced per tenant. | Primary key `(arena_id, key)`. | **Resolved** |
| `devices` had no secret, yet `device_id` was to be trusted. | Documented as telemetry that authorises nothing. | **Resolved** |
| No permission-cache TTL — a fired employee kept access indefinitely offline. | 24-hour TTL and read-only degradation. | **Resolved** — D18 |
| `profiles` globally readable — cross-tenant staff enumeration. | Readable only to users sharing an arena. | **Resolved** |
| No statement on `service_role` key handling or backups. | Both stated. PITR required before the pilot handles cash. | **Resolved** — `SECURITY.md` §11, §13 |

---

## 4. Multi-tenancy

| Finding | Resolution | Status |
|---|---|---|
| **No composite tenant foreign keys.** Nothing prevented a session in arena A referencing a station in arena B. The highest-value fix in the audit, and the one that cannot be retrofitted cheaply. | `UNIQUE (id, arena_id)` on every tenant-owned table; composite FKs on every tenant-owned relationship; in migration 1. | **Resolved** — D03 |
| **Tenant boundary undeclared** — organization or arena. | Arena is the operational boundary; organization is a grouping label in P0. | **Resolved** — D02 |
| **No active-arena mechanism.** The documents said not to trust a client `arena_id` without saying how the server resolves it. | Validated against `arena_users` in every RPC; RLS independently scopes reads. | **Resolved** |
| Cross-tenant role leakage. | See C11. | **Resolved** |
| No tenant provisioning, so tenant #2 needed manual SQL. | `provision_arena`; M10 exit criterion. | **Resolved** |
| Nothing kept 404 Arena's data out of production. | 404 Arena is created through the same provisioning function as any tenant, as seed data, never as compiled-in fixtures. | **Resolved** |

---

## 5. Offline sync

| Finding | Resolution | Status |
|---|---|---|
| **No per-operation offline contract.** "Designed for intermittent connectivity" is not implementable. | `OFFLINE.md` §2: every P0 operation classified offline / queued / cache / blocked. | **Resolved** — D15 |
| **Station double-booking** — two offline devices starting the same station. | Partial unique index on live sessions per station; the loser gets a conflict surfaced to a human. | **Resolved** |
| `sync_operations` conflated client queue and server idempotency. | Split. | **Resolved** — D16 |
| **No ordering model.** A naive independent-retry queue fails permanently when operation B depends on operation A. | Strict per-entity ordering, halt-on-failure, client-generated UUIDs. | **Resolved** |
| **Idempotent replay unspecified** — a retry could not distinguish "already done" from "failed". | Stored response returned on replay; fingerprint mismatch is a conflict. | **Resolved** |
| No delta-sync mechanism; reconnect gaps unaddressed. | `sync_pull` with an `updated_at` watermark, a 5-second overlap, and idempotent upserts. | **Resolved** |
| **"Never silently discard" with no dead-letter** guaranteed an infinite retry storm. | Bounded retries, error classification, dead-lettering, Sync Issues screen. | **Resolved** |
| Drift migration during an app update could corrupt queued work. | Outbox payloads are opaque versioned JSON. | **Resolved** |
| Offline oversell of stock. | Product sales are online-only in P0, so it cannot occur. | **Resolved** |
| Shift close offline would produce a false variance. | Blocked offline. | **Resolved** |

---

## 6. Flutter architecture

| Finding | Resolution | Status |
|---|---|---|
| Dio and `supabase_flutter` overlapped. | Dio not added. | **Resolved** — D24 |
| **Sync cross-cuts every repository**, inviting twelve divergent implementations. | One engine, one outbox, per-feature handlers registered with it. | **Resolved** — `ARCHITECTURE.md` §9 |
| **Timer rebuild storms** — a ticker invalidating the floor provider rebuilds every card every second. | Ticker consumed only in leaf timer widgets; it never invalidates the floor. | **Resolved** — `ARCHITECTURE.md` §7 |
| **Three model layers** with no mapping rule. | Drift row → mapper → Freezed domain. A separate DTO requires a stated reason. | **Resolved** — D25 |
| Router had four independent redirect conditions and would loop. | One state machine with a fixed evaluation order. | **Resolved** — `ARCHITECTURE.md` §8 |
| Riverpod version and codegen unspecified. | Riverpod 3. | **Resolved** — D25 |
| No error model despite the roadmap listing one. | Sealed `AppFailure` mapped from stable RPC error codes. | **Resolved** |
| **Money as `double`.** | Minor-unit `int` in a `Money` value object, parsed from the `numeric` string. | **Resolved** — D01 |
| No permission mechanism, no breakpoints, no test strategy, no CI, no flavours. | All specified in `ARCHITECTURE.md` §4, §13, §14, §15. | **Resolved** |
| `lib/` at repository root versus a `mobile/` directory. | `mobile/lib/`. | **Resolved** |

---

## 7. Database relationships

| Finding | Resolution | Status |
|---|---|---|
| No composite tenant FKs | See D03 | **Resolved** |
| Session↔order unmodelled | See D07 | **Resolved** |
| `sessions.shift_id` coupling | See D08 | **Resolved** |
| **No unique constraints stated anywhere** — members by phone, products by SKU, stations by name, arena users, idempotency keys, one open shift, one live session per station. Every one a live duplicate-data bug. | All specified, partial on `deleted_at IS NULL` where soft delete applies. | **Resolved** |
| `stations.status` coexisting with derived play state — the ghost-station bug. | Station status reduced to operational values; play state derived only. | **Resolved** — D06 |
| **`wallets.balance` was a mutable column with no ledger** — violating the project's own inventory principle. | Wallet deferred entirely rather than shipped with the flaw. | **Deferred** — D28 |
| Inventory sign convention undefined. | Signed quantities, constrained per movement type. | **Resolved** — D20 |
| No stock derivation strategy. | Trigger-maintained `product_stock` plus a reconciliation query. | **Resolved** |
| `order_items` had no type and no name snapshot — play and product revenue could not be split. | Both added. | **Resolved** |
| Money column types undefined; `json` rather than `jsonb`; no CHECK constraints on status columns. | All specified. | **Resolved** |
| **No index plan.** Postgres does not auto-index foreign keys. | Index plan in `DATABASE.md` §13. | **Resolved** |
| No cascade policy. | `ON DELETE RESTRICT` everywhere; no `CASCADE` in the schema. | **Resolved** |
| `member_memberships` snapshotted price but not benefits. | Deferred with memberships. | **Deferred** |
| `maintenance_tickets` allowed orphan rows. | Deferred with the ticket workflow. | **Deferred** |

---

## 8. Scope reductions applied

Removed from P0. The table count settled at 27, then rose to **28** when D31
added `tax_rate_components` so GST splits could be tenant configuration rather
than hardcoded logic (§10).

memberships and plans · wallet and coins · shared-device PIN and device lock ·
the pricing rule engine · `reserved` state and reservations ·
`session_games` / `station_games` / change-game · Realtime · FCM ·
Owner Admin Web · maintenance tickets · assets and QR · expenses ·
refunds and split-payment UI · receipt printing.

Reduced rather than removed: discounts (one order-level, manager-authorised,
reason required) · offline writes (session start and stop only) · visit history
(last 10 sessions).

Kept despite being invisible, because they cannot be retrofitted: composite
tenant keys · RLS and the RPC write path · client-generated UUIDs · idempotency
· business date · pricing and tax snapshots · receipt numbering · `updated_at`
and soft delete · audit.

---

## 9. The judgement calls worth remembering

**Offline checkout was the decisive question.** Every other decision had a
defensible default. This one changed the schema, the RPC surface, the UI, and
the shift model. Choosing "blocked offline" bought a shippable MVP at the cost
of an unbilled-sessions queue and a documented staff procedure. Provisional
billing remains available later without a rewrite, because orders already carry
snapshots and server-side recomputation.

**M10 is not polish.** Until a second arena can be created and run without
touching code, "multi-tenant SaaS" is unverified, and 404 Arena's seed data is
one shortcut away from becoming load-bearing.

---

## 10. Amendments after the correction pass

Two findings from the original audit were resolved *twice*, because the first
resolution was not quite right. Recorded so the reasoning is not lost.

**Tax components — the "one component now, `schema_version: 2` later" plan was
withdrawn.** The correction pass shipped a single-percent `tax_rates` table on
the argument that a CGST/SGST split could be added later without a table
change, since the snapshot already had a `components` array. That was true of
the *snapshot* and false of the *configuration*: there was nowhere for a tenant
to define the split, so the components could only have come from hardcoded
logic — violating the project's own no-hardcoding rule the moment India was
confirmed. D31 adds `tax_rate_components` as configuration, makes
`tax_rates.percent` a maintained sum, and makes multi-component snapshots
version 1. **Lesson: "the schema can represent it" is not the same as "a tenant
can configure it."**

**Fixed-duration grace was wrong, and only worked examples exposed it.** The
correction pass applied `grace_minutes` to total elapsed time for both plan
types. For a package that meant a customer two minutes past a one-hour slot was
billed for two hours — the exact outcome grace exists to prevent. Writing the
fixture vectors in `DATABASE.md` §16 surfaced it immediately (vector B3). Grace
now applies to the **overrun** for `fixed_duration`, and rounding and minimum
billable are documented as `open_time`-only. **Lesson: an algorithm is not
specified until someone writes down its expected outputs.**
