# Security Model

Conceptual security model for Arena OS. Schema detail is in `DATABASE.md`;
governing choices are in `DECISIONS.md`.

The client is a Flutter app talking to Supabase with an **anon key**. There is
no private application server in front of the database. Therefore the database
*is* the security boundary. Nothing enforced only in Flutter is enforced at all.

---

## 1. Layers

Authorisation is defended in five independent layers. Any one of them failing
must not be sufficient to breach isolation.

| Layer | Mechanism | Protects against |
|---|---|---|
| 1 | **PostgreSQL privileges** — `authenticated` has no write privilege on protected tables | Direct PostgREST writes |
| 2 | **Row Level Security** — every readable table is scoped to the caller's arenas | Cross-tenant reads |
| 3 | **Permission checks inside RPCs** — `app.require_permission()` | Authenticated-but-unauthorised actions |
| 4 | **Schema constraints** — composite tenant FKs, partial uniques, CHECKs | Cross-tenant references and impossible states, even from a bug in layers 1–3 |
| 5 | **Append-only triggers** | Tampering with financial and audit history |

Layer 1 is the primary write control. RLS alone is not relied on for writes.

---

## 2. Authentication

- Supabase Auth is the identity provider. One Supabase user per **real staff
  member** (D04).
- `profiles.id = auth.users.id`. A profile row is created on first sign-in.
- The session's refresh token is held in `flutter_secure_storage`.
- Sign-out clears the Drift cache of member data and any cached permission set.

**Shared-device PIN switching is deferred.** When it arrives it changes only the
body of `app.current_actor_id()` — never a column, an audit record, or an RPC
signature. A PIN credential will live in its own table with **no client read
access**, be verified only by a rate-limited server RPC with lockout, and be
treated as a convenience credential layered on top of a real authenticated
session — never as the sole authorisation.

Any *offline* PIN check would be a screen lock, not authorisation. This must
stay true whenever PIN work begins.

---

## 3. Arena membership and context

- `arena_users(arena_id, user_id, role_id, active)` is the membership record.
- `app.current_arena_ids()` returns the arenas the caller belongs to with
  `active = true`. It is `SECURITY DEFINER` and `STABLE`.

`SECURITY DEFINER` here is not incidental. A policy on `arena_users` that
queries `arena_users` through the invoker's rights recurses infinitely — a
well-known Supabase failure. The definer function bypasses RLS on that read and
breaks the cycle.

- **A client-supplied `arena_id` is never trusted.** Every RPC validates it
  against membership as its first action. Every RLS policy independently scopes
  rows to `app.current_arena_ids()`.
- The client holds one **active arena** at a time; switching arenas clears all
  cached tenant data.
- Deactivating `arena_users.active` removes access on the next server call,
  bounded by the offline cache TTL in §9.

---

## 4. Row Level Security

RLS is enabled on **every** table in `public`, including tables with no client
read path — a table with RLS enabled and no policy denies everything, which is
the correct default.

Standard read policy shape for a tenant-owned table:

```sql
CREATE POLICY read_own_arena ON <table>
  FOR SELECT TO authenticated
  USING (arena_id IN (SELECT app.current_arena_ids()));
```

No table has an `INSERT`, `UPDATE`, or `DELETE` policy for `authenticated`.
Writes have no client path by construction.

Tables whose read rule differs from the standard shape:

| Table | Read rule |
|---|---|
| `permissions` | readable by all authenticated users — a code list, not tenant data |
| `profiles` | readable only for users sharing an arena with the caller |
| `organizations` | readable only for organizations owning an arena the caller belongs to |
| `members` | **no direct read at all** — see §8 |
| `idempotency_keys` | no client read |
| `receipt_counters` | no client read |
| `audit_logs` | arena-scoped **and** `app.has_permission(arena_id, 'report.view')` |

RLS applies to `SECURITY INVOKER` access. `SECURITY DEFINER` RPCs run as their
owner and bypass RLS deliberately — which is exactly why every one of them must
begin with an explicit arena and permission check.

---

## 5. Write path — SECURITY DEFINER RPC boundaries

All stateful and financial mutation happens inside `SECURITY DEFINER` functions
owned by `postgres`, with `EXECUTE` granted to `authenticated`.

Every mutating RPC follows the same skeleton, in this order:

1. `app.require_permission(p_arena_id, '<code>')` — implicitly asserts arena
   membership
2. Idempotency claim, when the operation is idempotent
3. Load and lock the entities being changed (`FOR UPDATE`)
4. Validate the state transition
5. **Compute every money value server-side.** No client-supplied amount is
   ever persisted.
6. Write
7. `app.audit(...)` in the same transaction
8. Store the idempotency response
9. Return the authoritative result

Every function declares `SET search_path = pg_catalog, public, app` to prevent
search-path hijacking.

**Protected tables — no client `INSERT`/`UPDATE`/`DELETE` under any
circumstance:**

```
sessions · orders · order_items · payments · shifts · inventory_movements
product_stock · audit_logs · receipt_counters · idempotency_keys
arena_users · roles · role_permissions · arena_settings · members
```

Catalogue tables (`zones`, `station_types`, `stations`, `games`, `products`,
`billing_plans`, `tax_rates`) are also RPC-only in P0. Management RPCs are
gated per area — see `API.md` §11 for the exact permission per table.

---

## 6. Actor attribution

The server derives the actor. Always.

- `app.current_actor_id()` — P0 returns `auth.uid()`.
- Any client-supplied `actor_user_id`, `created_by`, `started_by`,
  `authorised_by`, or equivalent is **ignored**, not validated. RPC signatures
  do not accept such parameters at all.
- `device_id` is accepted and recorded but **never authorises anything** in P0.
  It is client-asserted telemetry (`DATABASE.md` §3).

Because a client cannot insert into an audited table directly, it cannot
perform an audited action and omit the audit row: the write and the audit
happen in the same function, in the same transaction.

---

## 7. Privilege escalation

`arena_users`, `roles`, and `role_permissions` are protected tables with no
client write path. They are mutated only by RPCs requiring
`permissions.manage`, which additionally enforce:

- the target role belongs to the caller's arena — structurally guaranteed by
  `roles.arena_id NOT NULL` and the composite FK on `role_permissions`
- a user cannot remove `permissions.manage` from themselves if they are the
  last holder in the arena
- `is_system` roles cannot be deleted
- every change writes `role.permissions_changed` to the audit log

`roles.arena_id` is `NOT NULL` specifically so no role is ever shared across
tenants (audit finding C11).

---

## 8. Member data privacy

Members are the only personal data in the system: name, phone, optional date of
birth.

- **`authenticated` has no `SELECT` privilege on `members`.** Not a policy — a
  revoked privilege. There is no query a client can write that returns the
  member table.
- Reads go through RPCs only:
  - `member_search` — requires ≥3 characters, returns at most 20 rows, requires
    `member.view`, and writes an audit row when the query looks like an
    enumeration attempt
  - `member_get` — single member by id
  - `floor_snapshot` — returns only a display name for members on active
    sessions
- `members` is **excluded from `sync_pull`**. The full table is never
  replicated to a device.
- Device cache: only members on currently active or unbilled sessions, plus the
  20 most recently touched on that device, with a 24-hour TTL. Cleared on
  sign-out and on arena switch.
- Member PII never appears in `audit_logs.metadata`, application logs, or crash
  reports. Log the member id, never the phone or name.
- Blocking a member records a reason and is audited.

Retention and erasure requests are handled as an operational procedure against
the database in P0; an automated erasure path is post-MVP.

---

## 9. Offline and stale trust

Offline capability is a trust window, so it is bounded.

- Cached permissions carry a **24-hour TTL**.
- After 24 hours without a successful sync, the client accepts **no new
  mutations** — it degrades to read-only with a persistent banner (D18).
- Already-queued mutations are never discarded, and never silently. A queued
  mutation that the server rejects on permission grounds surfaces to a human.
- The server re-checks permissions when a queued mutation arrives. Offline
  permission caching decides what the UI offers; the server decides what
  happens.
- `session_start` and `session_stop` are the only offline-capable mutations
  (D15). Nothing financial is ever computed or committed offline.

---

## 10. Append-only financial and audit data

`payments`, `inventory_movements`, and `audit_logs` reject `UPDATE` and
`DELETE` via a `BEFORE UPDATE OR DELETE` trigger that raises an exception for
**every** role — including the RPC definer and `service_role`.

This is stronger than revoking privileges, because it also protects against a
mistake inside a `SECURITY DEFINER` function.

Corrections are new rows:

- payment reversal → negative `amount` with `reverses_payment_id`
- inventory correction → movement of `type = 'correction'`

`orders` becomes effectively immutable once `settled`: a CHECK constraint
requires `total = paid_total` at settlement, and no RPC transitions an order
out of `settled`. `receipt_number` is never reissued or reused.

---

## 11. Environments, keys, and secrets

### Three separate Supabase projects (D34)

`development`, `staging`, `production` are **separate projects**, not schemas
inside one. Separate projects mean separate auth user pools, separate storage,
separate keys, and no configuration mistake that can point a development client
at production data.

- Each project has its own URL and anon key, supplied per Flutter flavour via
  `--dart-define` at build time. No environment values are committed.
- Migrations are forward-only and promoted `development → staging →
  production`. A migration reaches production only after applying cleanly to
  staging.
- **Production data is never copied into development or staging by default.**
  Any exception is anonymised — member names and phone numbers replaced —
  approved, and time-boxed. Development and staging are seeded from
  `provision_arena` plus clearly labelled fixture data (D33), never from a
  production dump.

### Client keys

- The Flutter app ships the **anon key only**. It is public by definition;
  treat it as a routing identifier, not a secret. It carries no privilege
  beyond what RLS and RPC grants allow.
- The **`service_role` key bypasses RLS entirely** and is a
  backend/administrative credential only (D37). It must never appear in:
  the Flutter app in any flavour · Drift, `flutter_secure_storage`, or any
  device · `--dart-define` values or `.env` files · the repository ·
  application logs, crash reports, or analytics · CI logs · any client-side
  configuration.
- Holders of the production `service_role` key are named, few, and recorded.

### Secrets

No credential of any kind is committed. A secret that reaches the repository is
**rotated**, not deleted from the tip of the branch.

### Other

- Edge Functions, if introduced later, must verify the JWT and re-derive the
  arena from the database. A request body is never a source of authorisation.
- Rate limiting: Supabase Auth defaults cover sign-in. `member_search` is
  additionally limited server-side. Any future PIN verification must be
  rate-limited with lockout before it ships.

---

## 12. Realtime

Realtime is not enabled in P0 (D23). When it is:

- RLS must be enabled for the publication; a subscription is a read and is
  subject to the same policies.
- The client-side `filter:` parameter is a bandwidth optimisation, **not** an
  authorisation boundary. It is chosen by the client and must never be the only
  thing separating tenants.
- Only tables safe to stream are published. `members`, `payments`,
  `audit_logs`, and `idempotency_keys` are not published.

---

## 13. Operational

### Backup and recovery (D37)

Before the pilot handles a single real transaction, all three must be true:

1. **Point-in-time recovery is enabled** on the production project.
2. A **named owner** for backup and recovery is recorded in this repository.
3. A **restore has been rehearsed once** — restore to a scratch project, verify
   that a known order and its payments survive, and record the wall-clock time
   it took.

Enabling PITR is not the same as knowing recovery works. The rehearsal is the
deliverable. It gates **M7 go-live**, not M0.

### Change control

- Migrations are forward-only, reviewed, and promoted through the three
  environments (§11). Schema changes never bypass the migration workflow.
- Database access outside the app — Studio, or psql with `service_role` — is
  unaudited by design. Restrict who holds it, and treat any manual data change
  as an incident to be written down.

---

## 14. Non-goals for P0

Stated so their absence is a decision rather than an oversight:

- Device attestation or certificate pinning
- Hardware-backed device identity
- Automated PII erasure workflows
- Field-level encryption of member data
- Anomaly detection on staff behaviour
- Per-tenant encryption keys
- SSO / SAML

---

## 15. Acceptance tests — pgTAP

Written in **pgTAP** (D35), living in `supabase/tests/`, run in CI against a
disposable database on every change. **Milestone 1 does not exit until every
one passes.**

Flutter tests are a separate suite in a separate CI job and **can never
substitute** for these. A Dart test exercises the client's intent; these
properties are enforced by privileges, policies, constraints, and triggers that
no Dart test touches.

Every test runs as a real `authenticated` JWT for a seeded user, not as the
migration role — otherwise it proves nothing about RLS.

**Tenant isolation**

1. A user of arena A cannot `SELECT` any row of arena B, asserted **per table**
   across all 28 tables — not a spot check.
2. RLS is enabled on every table in `public`, and a table with no policy denies
   reads rather than allowing them.
3. Composite tenant foreign keys reject a cross-arena reference on **every**
   tenant-owned relationship.
4. `orders.session_id` cannot reference a session in another arena; the
   composite FK rejects it even when RLS is bypassed.
5. `inventory_movements.product_id` and `.order_item_id` cannot reference
   another arena's rows.

**Write path**

6. `authenticated` has no `INSERT`, `UPDATE`, or `DELETE` privilege on any
   protected table listed in §5 — asserted per table.
7. Each mutating RPC rejects a caller lacking its permission code with
   `insufficient_privilege`, asserted per RPC against `API.md`.
8. Actor columns are derived from `auth.uid()`: no RPC signature accepts an
   actor parameter, and the row written records the caller regardless of any
   attempt to influence it.
9. The only money inputs are the human-entered amounts enumerated in `API.md`
   §1. A settlement whose payment amounts do not equal the server-recomputed
   total is rejected.

**Concurrency and replay**

10. Two concurrent `session_start` calls on one station produce exactly one
    session; the loser receives `conflict`.
11. A replayed idempotency key with identical arguments returns the **stored
    response**; the same key with different arguments returns
    `idempotency_key_reuse`.

**Immutability**

12. `UPDATE` and `DELETE` on `payments`, `inventory_movements`, and
    `audit_logs` fail for **every** role, including the definer and
    `service_role`.
13. `orders.receipt_number` cannot be changed once assigned, and no RPC
    transitions an order out of `settled`.

**Privacy and audit**

14. `authenticated` has no `SELECT` privilege on `members`; `member_search`
    enforces the 3-character minimum and the 20-row cap.
15. Every audited action in `DATABASE.md` §12 produces exactly one audit row,
    in the same transaction as the action.

**Correctness of computed values**

16. The play-charge vectors in `DATABASE.md` §16.4 produce the stated amounts.
17. The tax and total vectors in §16.5 produce the stated amounts, and tax
    components sum **exactly** to each line's `tax_amount`.
18. `tax_rates.percent` always equals the sum of its live components, and the
    last live component of a rate cannot be removed.
19. Receipt series derivation matches §16.6, including the financial-year
    rollover restarting at 1.
20. `app.normalise_phone` matches §16.7, and two spellings of one number cannot
    both be inserted.
