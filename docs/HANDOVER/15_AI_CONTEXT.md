# 15 — AI Context (for Claude / Cursor / Gemini / ChatGPT)

Read this file before changing Arena OS. Prefer facts here + code over older summaries.

---

## What this product is

Multi-tenant **gaming centre operations** platform: floor stations, play sessions, checkout, shifts.  
**404 Arena** is tenant #1 / pilot — **not** the product name to hardcode.

Formal MVP = one centre runs a trading day without a notebook and balances the drawer (`docs/MVP.md`, ROADMAP M7). That exit is **not** met yet.

---

## Stack (actual)

| Layer | Actual deps |
|---|---|
| Mobile | Flutter, Riverpod 3, go_router, supabase_flutter, google_fonts, shared_preferences |
| Web | Vite, React 18, supabase-js, lucide-react |
| Backend | Supabase Postgres, Auth, SECURITY DEFINER RPCs |
| Not present yet | Drift, Freezed, Dio, FCM, react-router, chart libs, Edge Functions |

`CLAUDE.md` still lists Freezed/Drift/secure_storage as stack — **aspirational**. Trust `pubspec.yaml` / `package.json`.

---

## Architecture in one paragraph

Clients authenticate with Supabase, call `me`, select an arena, then mutate only via RPCs. Tables are SELECT-only under RLS. Money and permissions are server-owned. Flutter production app and Owner Web Live Floor/Shift share the same RPCs. Flutter also has a **demo** app (`main_lobby.dart` + `DemoData`) that must not be treated as production.

---

## Folder map

```
arena-os/
  mobile/lib/features/{auth,floor,checkout,shift,tenant,shell,devices,permissions,lobby_ui}
  web/src/{pages,components,services,data,context,styles,theme}
  supabase/migrations|tests|seed.sql
  docs/          binding contract
  docs/HANDOVER/ this package
  docs/commercial/ aspirational SaaS bible — mostly NOT built
  scripts/ci.sh|db.sh
```

---

## Important files

| File | Why |
|---|---|
| `docs/DECISIONS.md` | Absolute authority |
| `docs/DATABASE.md` | Schema + pricing/tax algorithms |
| `docs/API.md` | Target RPC contract (ahead of implementation) |
| `docs/SECURITY.md` | RLS / RPC / privacy |
| `docs/OFFLINE.md` | Offline matrix (mostly unimplemented) |
| `mobile/lib/app/router.dart` | Auth/arena/permission redirect machine |
| `mobile/lib/core/money/money.dart` | Money parsing rules |
| `web/src/data/ownerFixtures.ts` | Mock Owner Web — do not wire new “real” KPIs from this |
| `supabase/seed.sql` | Fixture tenant |

---

## Business rules agents must not break

1. Money: `numeric` ↔ minor-unit `int` — never `double`  
2. Server owns bills/tax/stock/permissions  
3. Composite tenant FKs `(id, arena_id)`  
4. Mutations only via SECURITY DEFINER RPCs  
5. Actor from JWT — never a param  
6. Never trust client `arena_id` without membership check  
7. Checkout unavailable offline  
8. Never claim success if mutation did not reach server  
9. Never silently discard failed mutations  
10. Payments / inventory_movements / audit_logs append-only  
11. No timer-tick DB writes  
12. One live session per station  
13. Pricing is data — no hardcoded GST/`1.18`/CGST in code  
14. Members: no client SELECT  
15. Anon key only in clients  

---

## How to implement a new feature

1. Confirm it is in P0 / current epic (`12_NEXT_TASK.md`) — do not jump to commercial CRM/AI  
2. Add/adjust migration if schema needed (forward-only)  
3. Add SECURITY DEFINER RPC + `require_permission` + tests  
4. Flutter: repository → controller → screen; use `Money` / `AppFailure`  
5. Web: same RPC in `services/`; replace fixtures if page already mocked  
6. Update API/docs if contract changes  
7. Run `./scripts/ci.sh all` mentally: format, analyze, flutter test, pgTAP  

---

## Common mistakes

| Mistake | Correct |
|---|---|
| Editing only `lobby_ui` / DemoData | Wire production flavours |
| Computing tax in the client | Use `order_preview` |
| Using `.from('members').select` | Member RPCs (not built yet) |
| Adding Dio | Forbidden |
| Hardcoding `404 Arena` / INR rates | Tenant settings / seed fixtures only |
| Marking Owner Web reports “done” | Still fixtures |
| Implementing wallet/coins in P0 | Deferred (D28 / D28a) |
| Enabling Realtime casually | Not P0; no publications |
| Believing API.md == shipped | Many RPCs missing — check migrations |

---

## Do not break

- Partial unique indexes (live session, open shift, live order)  
- Append-only triggers  
- RLS deny-by-default on members/receipt/idempotency  
- Epic 3C algorithm path (`app.compute_order_totals`, receipt helpers)  
- Promotion guards in `scripts/db.sh`  
- Demo isolation test (`no_demo_data_in_production_test.dart`)  

---

## Golden rules for agents

1. Read code — do not assume commercial docs are built  
2. Prefer RPC + pgTAP over UI-only demos  
3. Distinguish Production / Partial / Mock / Hardcoded / Not Started  
4. Keep Flutter and Web business logic identical for money ops  
5. When unsure, open `docs/DECISIONS.md` and the latest migration for that domain  

---

## Current honest status for agents

**Working:** auth, floor, session lifecycle (start/pause/resume/stop), checkout settle, shifts.  
**Not working as product:** members, inventory admin, offline, reports, memberships, most Owner Web modules.  
**Next:** finish Epic 7 → 8 sync → 9 sessions → 10 members → 11 inventory → 12 offline → 13 tenant #2.
