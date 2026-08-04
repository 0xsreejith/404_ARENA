# 17 — Backlog

Grouped by urgency against the **existing** roadmap and code gaps.

---

## Critical (blocks real trading-day pilot / M7)

- Finish Epic 7 — single production Flutter path; live overtime alert; demote lobby demo  
- Member RPCs + UI (search/create/select on session start) — M5 / Epic 10  
- Inventory receive/adjust + usable snack sell UX — M8 / Epic 11  
- Offline session start/stop + Sync Issues — M9 / Epic 12  
- PITR enabled + restore rehearsal on production project — M7 go-live gate  
- Android/iOS release signing (not debug keystore)  
- Session start: pass memberId/gameId from production UI  

---

## High

- `session_extend` / `session_cancel` RPCs + UI — Epic 9  
- Drift cache + `sync_pull` foundation — Epic 8  
- Persist D18 last-server-contact (survives process death)  
- Counter sale complete path (null session checkout UX)  
- `order_add_product` / discount UX completeness on Flutter + Web  
- Replace Owner Web dashboard/report fixtures with real aggregates (or remove fake numbers)  
- Fix stale `00_harness_test.sql` function list  
- Align docs: CLAUDE.md / ARCHITECTURE Owner Web layout vs D26a  
- Receipt printing / share  

---

## Medium

- Station maintenance UI (`station_set_status`)  
- Admin catalogue CRUD RPCs + Web stations/games/plans/tax/products — OW2/OW3 / M10  
- Staff & roles management UI (real mutations)  
- Arena settings UI bound to `arena_settings`  
- Audit log viewer (`audit_search` or equivalent)  
- Multi-payment settle (API.md shape) if required for pilot  
- Flutter feature/widget tests for floor/checkout/shift  
- Web test harness  
- Remove orphan `NavigationShell.tsx`  
- Freezed models if team adopts codegen  
- Source-guard vs remaining hardcoded INR/brand strings cleanup  

---

## Low

- Expenses / cash_movements (post-MVP)  
- Integrations page (real)  
- Search ⌘K / export  
- Deep-link routing for Owner Web (react-router)  
- Realtime floor (post-MVP)  
- FCM notifications (post-MVP)  
- Customer app / portal / website  
- Super Admin platform schema  
- CRM wallet / loyalty / coins (D28a)  
- Bookings / tournaments / AI insights  
- Happy hour / day-part pricing  
- Session transfer between stations  

---

## Explicitly out of P0 (do not sneak in)

Memberships selling · wallets · coins · tips as first-class · soft deletes of financial rows · client-side billing authority · production seed of `[FIXTURE]` rates as real prices
