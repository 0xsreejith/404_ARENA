# 14 — How to Work

---

## Coding standards

- Prefer small, focused diffs; no drive-by refactors
- Match existing patterns in the touched feature
- Do not add dependencies unless asked
- Do not invent business rules — implement `docs/DATABASE.md` / `API.md` / `DECISIONS.md`
- `docs/DECISIONS.md` wins all conflicts

---

## Folder rules

| Area | Put code here |
|---|---|
| Flutter feature | `mobile/lib/features/<name>/` — screen, controller, repository |
| Shared Flutter | `mobile/lib/core/` or `app/` |
| Lobby demo only | `mobile/lib/features/lobby_ui/` — never import into production features |
| Web live ops | `web/src/services/` + components |
| Web fixture UI | `web/src/data/ownerFixtures.ts` until RPC exists |
| Schema / RPCs | `supabase/migrations/` forward-only |
| Tests DB | `supabase/tests/` |
| Binding docs | `docs/` — update when contract changes |

---

## Architecture rules

1. UI → Riverpod controller → repository → `supabase.rpc`  
2. No Dio / custom REST backend  
3. No client writes to protected tables  
4. Repository returns typed failures via `AppFailure` / mapper  
5. React: same RPCs as Flutter for the same action  

---

## RPC rules

- `SECURITY DEFINER` + `app.require_permission`
- Actor from JWT — never a parameter
- Validate arena membership before trusting `p_arena_id`
- Client-generated UUIDs for entity ids
- Idempotency keys on mutations that need them
- Money returned as decimal **strings**; Dart parses to minor-unit `int`
- Audit important actions via `app.audit`

---

## Money rules

- Postgres: `numeric(12,2)` only  
- Dart: minor-unit `int` — **never `double`**  
- Server computes bills, tax, discounts, stock  
- Client may show live timers; never submits authoritative totals  
- No hardcoded tax rates / CGST / `1.18` / receipt prefixes in SQL or Dart (D33)

---

## Theme rules

- Flutter production: dark Arena theme; Lobby chrome for staff shell  
- Owner Web: light owner tokens; dark cyber only for Live Floor / Shift  
- Branding from `arena_settings` / `me` — 404 Arena is data, not code  
- Touch targets ≥ 56; no decorative Material splash  

---

## Naming

| Kind | Convention |
|---|---|
| Permission codes | `resource.action` e.g. `session.start` |
| RPCs | snake_case verbs e.g. `order_settle` |
| Migrations | `YYYYMMDDHHMMSS_description.sql` |
| Fixture seed names | `[FIXTURE] ...` prefix |
| Flutter files | snake_case.dart |

---

## State management

- Flutter: Riverpod 3 Notifiers only  
- Web: React context + local state (no global store library yet)  
- Do not add Bloc/GetX/Redux  

---

## Commit style

- Prefer clear why-focused messages  
- Do not commit secrets, `env/*.json`, service_role keys  
- Do not commit unless asked  
- CI must stay green: format, analyze, flutter test, pgTAP  

---

## Testing expectations

| Change | Required proof |
|---|---|
| Migration / RPC | pgTAP assertions; extend existing epic tests |
| Money / tax | DATABASE.md §16 vectors |
| Flutter core | unit tests for Money / failures / guards |
| Security | tenant isolation still passes |
| New production UI | must not import `demo_data` |

---

## Dual-app warning

Never “finish” a feature only in `lobby_ui`. Production path is flavoured `main_*.dart`. Demo can prototype UX; ship requires RPC + production screens.
