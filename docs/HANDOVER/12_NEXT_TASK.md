# 12 — Next Tasks (Implementation Order)

Order derived **only** from current repo plans (`IMPLEMENTATION_PLAN.md`, `docs/ROADMAP.md`) and code gaps. No speculative features.

---

## Immediate — finish Epic 7

1. Production overtime → time-up alert on live RPC data  
2. Demote/gate `main_lobby` so demo cannot be mistaken for product  
3. Close remaining UI_PARITY_AUDIT P0 items on live data  
4. Strip/forbid coins/membership UI from any production path  

**Exit:** One Flutter staff app over live RPCs with Lobby chrome.

---

## Epic 8 — Floor sync foundation (M3)

1. Add Drift + DAOs  
2. Implement `sync_pull` RPC + watermark/soft-delete  
3. Connectivity + staleness state  
4. Outbox table + engine wired (handlers registered; offline start/stop not enabled yet)  
5. Prove 40-station floor smoothness  

---

## Epic 9 — Session completeness (M4 remainder)

1. RPCs: `session_extend`, `session_cancel`  
2. Start sheet: WHO (member) / WHAT (game) / HOW LONG (plan)  
3. Concurrency race proof on one-live-session index  
4. Pricing snapshot single normative shape  

---

## Epic 10 — Members P0 (M5) — **shipped 2026-08-05**

1. RPCs: search/get/create/update/set_blocked (no client SELECT) ✅  
2. Flutter Members (+ wallet/loyalty/notes when present) ✅  
3. Replace Web member fixtures ✅  
4. Phone E.164 via `app.normalise_phone` ✅  
5. CRM depth + wallet/loyalty/memberships (Waves B/C) ✅  

**Next focus:** Epic 11 Inventory P0, or Owner catalogue CRUD.

---

## Epic 11 — Inventory P0 (M8)

1. `inventory_adjust` (+ receive path)  
2. Counter sale UX complete  
3. Flutter Stock + Web Inventory live  
4. Low-stock from real `product_stock`  

---

## Epic 12 — Offline enablement (M9)

1. Enable outbox for `session_start` / `session_stop` only  
2. Sync Issues UI  
3. Persist 24h stale contact  
4. Idempotency E2E; zero silent discard  

---

## Epic 13 — Tenant #2 & config UIs (M10)

1. Settings / pricing / tax / staff / roles UIs  
2. Hardcoding audit pass  
3. Second arena with zero code/SQL changes  

---

## Parallel / after M7 — Owner Web OW2–OW9

Wire fixtures → RPCs: stations admin, catalogue, reports, audit viewer, settings. Keep same RPCs as mobile — no parallel business rules.

---

## Explicitly later (do not jump ahead)

- CRM wallet/loyalty (D28a after M10)  
- Super Admin platform schema (D38)  
- Customer app / portal / website  
- AI packs  
- FCM / Realtime  

---

## Fix-now hygiene (any epic)

| Item | Why |
|---|---|
| Update `tests/00_harness_test.sql` public function list | Currently stale |
| Update `supabase/README.md` past M1 | Misleading |
| Align CLAUDE.md with D26a (`web/` in repo) | Agent confusion |
| Android release signing | Blocks store builds |
| Remove orphan `NavigationShell.tsx` or wire it | Dead code |
