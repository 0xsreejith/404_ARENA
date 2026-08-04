# PROJECT HEALTH REPORT

**Arena OS · Audit date 2026-08-04 · Codebase-derived only**

---

## Verdict

Arena OS has a **strong multi-tenant backend foundation** and a **working core trading path** (auth → floor → session → checkout → shift). It is **not** a finished MVP, **not** production-ready SaaS, and **must not** be sold on Owner Web dashboards/CRM/reports (those are fixtures).

---

## Scores

| Metric | Value |
|---|---|
| **Overall completion** (toward formal M7 MVP) | **~58%** |
| **Core business completion** (single-centre trading day) | **~68%** |
| **Current operational MVP** (what works today) | **~65%** |
| **Commercial SaaS completion** (`docs/commercial/`) | **~8%** |
| **Production readiness** | **~30%** |
| **Overall product score** | **~5.0 / 10** |

Detail: [`20_PROJECT_SCORE.md`](./20_PROJECT_SCORE.md) · [`01_PROJECT_STATUS.md`](./01_PROJECT_STATUS.md)

---

## What is real

- Supabase Auth + `me` + arena select + device register  
- Floor snapshot; session start/pause/resume/stop  
- Checkout open → preview → settle (single payment; needs open shift)  
- Shift open / summary / close  
- 28-table schema, RLS, algorithms, 20 public RPCs, solid pgTAP  

## What looks real but is not

- Flutter `lobby_ui` members/stock/PIN/coins (`DemoData`)  
- Owner Web dashboard KPIs, reports, members, inventory, staff, settings, expenses, integrations  

---

## Estimated remaining work

| Scope | Estimate (engineering order-of-magnitude) |
|---|---|
| Finish Epic 7 + hygiene | ~1–2 weeks |
| Epics 8–12 (sync, sessions, members, inventory, offline) | ~6–10 weeks |
| Epic 13 + PITR go-live rehearsal | ~2–3 weeks |
| **Formal M7 MVP** | **~2–3 months** focused core work |
| Owner Web live data (OW2–OW9) | +1–2 months parallel/after |
| Full commercial catalogue | **many quarters** — mostly unbuilt |

Estimates assume one strong full-stack engineer familiar with the stack; not calendar commitments.

---

## Highest priority next tasks

1. Exit Epic 7 — one production Flutter app; kill dual-demo confusion  
2. Members P0 RPCs + session start WHO picker  
3. Inventory adjust/receive + snack UX  
4. Offline start/stop (after Drift/`sync_pull` foundation)  
5. PITR + real trading-day drawer proof at pilot  
6. Strip fake Owner Web metrics from any external demo  

See [`12_NEXT_TASK.md`](./12_NEXT_TASK.md).

---

## Biggest risks

| Risk | Impact |
|---|---|
| Stakeholders treat fixture Owner Web as live product | False confidence / bad decisions |
| Dual Flutter apps diverge forever | Double maintenance; ship wrong binary |
| Skipping members/inventory/offline then calling MVP done | Pilot fails on real day |
| Hardcoded client tax/branding creeping back | Breaks D33 / multi-tenant promise |
| API.md treated as implemented | Agents invent UI for missing RPCs |

---

## Biggest technical debt

1. `lobby_ui` DemoData parallel world  
2. Owner Web `ownerFixtures.ts` across W1–W13  
3. Missing Drift/outbox/`sync_pull` while docs assume offline architecture  
4. Incomplete session start / product add UX vs capable RPCs  
5. Stale harness test + stale CLAUDE/supabase README claims  
6. No web tests; thin Flutter feature tests  
7. Debug Android signing  

---

## Recommended roadmap

```
NOW     Epic 7 exit + doc/harness hygiene
NEXT    Epic 8 sync foundation
THEN    Epic 9 session completeness
THEN    Epic 10 members → Epic 11 inventory
THEN    Epic 12 offline → Epic 13 tenant #2 + PITR
PARALLEL (after money path stable)  Owner Web OW* live wiring
LATER   CRM/wallet, Super Admin, customer app, AI stubs
```

Do **not** reorder to build commercial surfaces before M7.

---

## Handover package index

[`README.md`](./README.md) lists all 20 documents.
