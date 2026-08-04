# 01 — Project Status

**Audit date:** 2026-08-04  
**Source of truth:** current repository code under `arena-os/`  
**Authority:** `docs/DECISIONS.md` wins any conflict with older docs

---

## One-line status

Arena OS can run the **core trading path** end-to-end against Supabase (auth → floor → session → checkout → shift). Members, inventory, offline sync, reports, membership/wallet, and most Owner Web modules are **not production**. Formal MVP exit (`ROADMAP.md` M7) is **not met**.

---

## Completion scores (honest)

| Area | % | Basis |
|---|---|---|
| **Overall (toward formal MVP M7)** | **~58%** | Money path shipped; members/inventory/offline/PITR remaining |
| **Architecture** | **~82%** | Patterns, composite FKs, RPC-only writes, RLS landed; dual Flutter paths remain |
| **Flutter (staff app)** | **~52%** | Production auth/floor/checkout/shift; lobby demo parallel; no members/inventory/reports/offline |
| **React (Owner Web)** | **~35%** | Auth + live floor/shift/checkout real; W1–W13 UI shells mostly fixture |
| **Backend (RPCs / app helpers)** | **~62%** | 20 public RPCs through Epic 6/7; API.md member/sync/admin RPCs missing |
| **Database (schema)** | **~90%** | All 28 P0 tables + algorithms + RLS; branding/platform extras incomplete |
| **RPC contract vs `docs/API.md`** | **~48%** | Core ops present; extend/cancel, members, inventory adjust, sync, admin absent |
| **Testing** | **~55%** | Strong pgTAP (20 files); Flutter unit/guards only; web tests absent |
| **Deployment** | **~25%** | Local scripts + CI exist; remote PITR / production go-live not proven in-repo |
| **Production readiness** | **~30%** | Usable for local/pilot demo of trading path; not ready for paying multi-tenant SaaS |

### Derived product scores

| Metric | % |
|---|---|
| Core business (single-centre trading day) | **~68%** |
| Current operational MVP (what a shop can do today) | **~65%** |
| Commercial SaaS catalogue (`docs/commercial/`) | **~8%** |

---

## What is done

- M0 foundations (Flutter flavours, Money, AppFailure, theme, CI, pgTAP harness)
- M1 schema security core (28 tables, RLS, algorithms, `provision_arena`, seed)
- Epic 1 — `me`, branding columns, `register_device`
- Epic 2 — `floor_snapshot`, session start/pause/resume/stop, `station_set_status`
- Epic 3 + 3C — checkout open/add product/discount/preview/settle/void with M1 algorithms
- Epic 4 — Flutter/Web auth context, permissions, router, device register, stale gate
- Epic 5 — unbilled sessions, floor → checkout wire-up
- Epic 6 — shift open/current/summary/close
- Epic 7 Phase 1–2 — Lobby chrome on production Flutter shell; live station cards; `seat_capacity` on snapshot
- Owner Web light shell (W1–W13 page layouts) with live floor/shift

---

## Known blockers

1. **Formal MVP incomplete** — members (M5), inventory (M8), offline (M9), PITR rehearsal (M7 gate) missing
2. **Dual Flutter apps** — `ArenaApp` (Supabase) vs `main_lobby.dart` (DemoData); Epic 7 not fully exited
3. **Session start UI incomplete** — RPCs accept `memberId`/`gameId`; production UI does not pass them
4. **No receipt printing** — settle works; no printer integration
5. **Owner Web fixture debt** — dashboards/reports/CRM look finished but are mock
6. **Stale docs** — `CLAUDE.md` / some architecture sections still omit or ban in-repo Owner Web (superseded by D26a)
7. **Harness drift** — `tests/00_harness_test.sql` still expects only `provision_arena` in public
8. **Android release signing** — still debug keystore (`TODO(M7)`)

---

## Technical debt

| Debt | Severity |
|---|---|
| `lobby_ui` + `DemoData` parallel to production features | High |
| Owner Web fixture KPIs/charts masquerading as product | High |
| Drift / outbox / `sync_pull` not implemented (docs assume them) | High |
| Freezed / json_serializable / flutter_secure_storage deferred but still listed in CLAUDE.md stack | Medium |
| Ending-threshold / brand color fallbacks hardcoded in clients | Medium |
| `order_settle` single-payment vs API.md multi-payment array | Medium |
| No web tests; thin Flutter feature tests | Medium |
| Orphan `NavigationShell.tsx` | Low |
| `supabase/README.md` still says “Current state: M1” | Low |

---

## Missing features (relative to P0 / API.md)

- `session_extend`, `session_cancel`
- Member RPCs (`member_search/get/create/update/set_blocked`)
- `inventory_adjust` (+ full sell/receive UI)
- `sync_pull`, `outbox_discard`
- Admin catalogue CRUD RPCs
- Split payment / multi-tender settle
- Offline session start/stop
- Reports RPCs
- Membership / wallet / loyalty (intentionally post-MVP / D28a)
- Customer app, Super Admin, portal, website (commercial surfaces — not started)

---

## Hardcoded / demo data (summary)

See `03_HARDCODED.md`.

- Flutter `lobby_ui/demo_data.dart` — full fake centre
- Web `src/data/ownerFixtures.ts` — full fake back-office
- Seed `[FIXTURE]` pricing/tax/stations (dev/staging only — intentional)
- Client fallbacks: INR, brand colors `#7CFF4F` / `#00F0FF`

---

## Demo features

| Feature | Where | Nature |
|---|---|---|
| PIN staff login | Flutter `lobby_ui` | Demo only |
| Members / Stock / coins UI | Flutter `lobby_ui` | Demo only |
| Owner dashboard KPIs/charts | Web fixtures | Mock |
| Reports / expenses / integrations | Web fixtures | Mock |
| Staff permission toggles | Web | Toast-only |
| Search ⌘K / Export | Web chrome | Decorative |

---

## Future roadmap (from repo plans only)

**Immediate (Epic 7 finish → 8–13):** shell convergence → sync foundation → session completeness → members → inventory → offline → tenant #2

**Then Owner Web OW1–OW9**, Super Admin SA1–SA5, CRM1–CRM6, inventory/reports expansion, AI stubs

**Formal MVP exit:** ROADMAP M7 — one real trading day at pilot + drawer balance + PITR gate

---

## Current milestone

| Claim | Reality |
|---|---|
| README: “M1 · Epics 3C–6 complete · Epic 7 Phase 1” | Accurate |
| Trading path works | Accurate for auth/floor/checkout/shift against live RPCs |
| MVP done | **False** — M7 exit criteria not met |
| Commercial SaaS ready | **False** |
