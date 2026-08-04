# 09 — Supabase

**Path:** `arena-os/supabase/`  
**Local project_id:** `arena-os` (`config.toml`)  
**Postgres:** 17

---

## Schema

See `05_DATABASE.md`. Summary:

- Schemas: `public` (tables + RPCs), `app` (helpers), `extensions` (pgtap, pg_trgm, btree_gin)
- 28 tables, composite tenant keys, append-only money/audit
- Algorithms in `app` (play_charge, compute_order_totals, largest remainder, receipts)

---

## Policies

- RLS on every table
- Client: SELECT-only where granted; members/receipt_counters/idempotency_keys deny-by-default
- No write policies for `authenticated`
- Mutations exclusively via SECURITY DEFINER RPCs

Details: migration `20260730010600_m1_rls.sql` and `docs/SECURITY.md`.

---

## Functions

| Layer | Count | Notes |
|---|---|---|
| Public RPCs | 20 | See `06_RPC_CATALOG.md` |
| App helpers | 33 | Permissions, dates, algorithms, triggers |

---

## Storage

- Storage service enabled locally
- **No buckets configured**
- No image upload product path yet (CRM photo is commercial future)

---

## Realtime

- `[realtime] enabled = true` in local config
- **No** table publications / replica identity setup in migrations
- Product P0 decision: **no Realtime** — floor uses polling (D23)
- Flutter bootstrap comments: Realtime designed for later, not enabled

---

## Authentication

- Supabase Auth email/password
- Local: signup on, email confirmations off, site_url `http://127.0.0.1:3000`
- Seed users: `owner@` / `manager@` / `staff@arena-os.local` (password empty unless `arena_os.seed_password` set)
- Actor attribution: `app.current_actor_id()` → `auth.uid()`

---

## Environments (D34)

Three separate Supabase projects:

| Env | Purpose |
|---|---|
| development | Local + remote dev; seed allowed |
| staging | Promotion gate before production |
| production | Real tenants; typed confirm; **no seed**; no pull-data |

Promotion: `scripts/db.sh push <env>` with guards. Migrations forward-only.

---

## Current deployment reality

| Item | In-repo status |
|---|---|
| Local `supabase start` + reset + seed | Supported |
| CI: start, reset, lint, pgTAP | Configured |
| Remote project refs | Via env vars — **not committed** |
| PITR / restore rehearsal | Required for M7 go-live — **not evidenced as done** |
| Edge Functions | Runtime enabled; **no `functions/` directory** |
| `supabase/README.md` | Stale (“Current state: M1”) |

---

## Seed

`supabase/seed.sql` — fixture tenant only. See `03_HARDCODED.md`.

---

## Tests

20 pgTAP files under `supabase/tests/` covering schema, privileges, RLS, isolation, constraints, immutability, algorithms, receipts, provisioning, inventory materialisation, and Epics 1–6.

**Known drift:** `00_harness_test.sql` still asserts public functions = only `provision_arena`.
