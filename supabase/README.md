# Database workspace

PostgreSQL schema, RPCs, policies, and tests for Arena OS.

Authoritative specification: `../docs/DATABASE.md`, `../docs/SECURITY.md`.
Governing decisions: D34 (three projects), D35 (pgTAP), D37 (`service_role`).

**Current state: M1.** Schema v1 exists: the 28 tables in `DATABASE.md` §14,
RLS on every one of them, no client write privilege on any of them, the `app`
helper functions, the append-only and materialisation triggers, the permission
catalogue, and `provision_arena`.

`tests/00_harness_test.sql` pins that scope from both sides: it fails if a table
`DATABASE.md` §14 defers appears, and if any public RPC beyond
`provision_arena` does. `me()`, the session, checkout, member, shift and sync
RPCs are M2 and later.

---

## Layout

```
migrations/    forward-only schema, applied in filename order
seed.sql       [FIXTURE] data for development and staging only — never production
tests/         pgTAP suite, run in filename order
tests/fixtures/*.psql   shared setup, included with \ir; the extension keeps
                        pg_prove from collecting them as tests
```

---

## Environments

Three **separate Supabase projects**, never schemas inside one (D34):

| Environment | Purpose |
|---|---|
| `development` | Day-to-day work. Seeded from `provision_arena` + `[FIXTURE]` pricing |
| `staging` | Pre-production verification. Same seeding as development |
| `production` | Real tenants, real money. Pricing configured by a tenant user (D33) |

Project refs are read from the environment, never committed:

```bash
export SUPABASE_PROJECT_REF_DEVELOPMENT=...
export SUPABASE_PROJECT_REF_STAGING=...
export SUPABASE_PROJECT_REF_PRODUCTION=...
```

---

## Local development

Requires Docker.

```bash
../scripts/db.sh start        # start the local stack
../scripts/db.sh reset        # rebuild from migrations, then apply seed.sql
../scripts/db.sh new <name>   # create a migration
../scripts/db.sh test         # run the pgTAP suite
../scripts/db.sh lint         # static-check migrations
../scripts/db.sh stop
```

`reset` also loads `seed.sql`, which provisions a pilot-shaped tenant through
`provision_arena` and adds `[FIXTURE]`-prefixed pricing, tax and catalogue rows
— the test vectors in `DATABASE.md` §16, not commercial rates (D33).

Seeded accounts have **no usable password** unless one is supplied, because no
credential is committed (D37):

```bash
ARENA_OS_SEED_PASSWORD=... ../scripts/db.sh seed development
```

The tenant itself is a seed parameter, not a constant. Override
`ARENA_OS_SEED_ARENA_NAME`, `_TIMEZONE`, `_CURRENCY` or `_DIAL_CODE` to seed a
differently shaped tenant without editing a file.

---

## Migration workflow

Migrations are **forward-only**. There are no down-migrations: a mistake is
corrected by a new migration, because rolling back a schema change against live
financial data is not a real option.

```
write locally  →  db.sh reset  →  db.sh test  →  commit  →  CI
       ↓
   db.sh push development
       ↓
   db.sh push staging          ← must apply cleanly here first
       ↓
   db.sh push production       ← typed confirmation required
```

`db.sh push production` refuses to run while staging has unapplied migrations,
and requires you to type `production` before it proceeds.

`db.sh verify-parity staging production` confirms two environments are on the
same migration set.

### Rules

- **Never** edit a migration that has been pushed anywhere. Write a new one.
- **Never** apply schema changes through Studio or psql. They will not exist in
  the next environment and the drift is silent.
- **Never** copy production data into development or staging (D34). There is
  deliberately no command for it. If a production-shaped dataset is genuinely
  needed, anonymise member names and phone numbers first, get it approved, and
  time-box it.
- **Never** put a tenant's name, currency, timezone, dial code, tax component or
  rate in a migration. `scripts/ci.sh guard` fails the build if one appears
  (D31, D33). That is what `seed.sql` is for, and `db.sh seed` refuses
  production.

---

## Credentials

No credential lives in this directory or anywhere in the repository (D37).

- The **anon key** is what the Flutter app ships. It is public by definition.
- The **`service_role` key** bypasses RLS entirely. It is backend and
  administrative only, and must never appear in Flutter, on a device, in a log,
  in CI, or in a file here.
- `supabase link` stores the project ref locally; the database password is
  prompted for, or read from `SUPABASE_DB_PASSWORD` in your shell.

---

## Tests

pgTAP (D35), in `tests/`, run by `db.sh test` and by the `database` CI job.

Database tests and Flutter tests are separate suites and neither substitutes
for the other: a permission check that exists only in Flutter is not a
permission check.

M1 does not exit until the **20 assertions in `../docs/SECURITY.md` §15** pass —
tenant isolation per table, forbidden direct writes, RPC permission
enforcement, actor derivation, composite tenant foreign keys, one live session
per station, idempotent replay, append-only financial records, and the computed
vectors in `DATABASE.md` §16.

Several of those assertions have a part that only exists once a later milestone
adds the RPC it names. The suite asserts every part the M1 surface can express
and grows with each milestone.

| §15 | Where | Outstanding until |
|---|---|---|
| 1 cross-arena reads, per table | `04` | — |
| 2 RLS on every table, deny-by-default | `03` | — |
| 3 composite FKs reject cross-arena | `05` | — |
| 4 `orders.session_id` cross-arena | `05` | — |
| 5 `inventory_movements` cross-arena | `05` | — |
| 6 no client write privilege, per table | `02`, `04` | — |
| 7 per-RPC permission enforcement | `08` (`require_permission`) | each RPC, M2–M8 |
| 8 actor from `auth.uid()` | `08` | — |
| 9 money inputs | `08` (no money input exists in M1) | `order_settle`, M6 |
| 10 one live session per station | `06` (constraint) | the two-device race, M4 |
| 11 idempotent replay | `09` | end-to-end drain, M9 |
| 12 append-only for every role | `07` | — |
| 13 `receipt_number` and settled orders immutable | `07` | — |
| 14 no `SELECT` on `members` | `02`, `04` | `member_search` limits, M5 |
| 15 one audit row per audited action | `08`, `12` | each audited action, M4–M8 |
| 16 play-charge vectors §16.4 | `10` | — |
| 17 tax and total vectors §16.5 | `10` | — |
| 18 `tax_rates.percent` maintained | `10` | — |
| 19 receipt series §16.6 | `11` | — |
| 20 phone normalisation §16.7 | `11` | — |

Every test runs as a real `authenticated` JWT for a seeded user, not as the
migration role — otherwise it proves nothing about RLS. `fixtures/two_tenants.psql`
builds two complete tenants and the helpers `pg_temp.become(user)` and
`set local role authenticated` switch identity.

Naming: `NN_subject_test.sql`, run in filename order.
