# 02 — What's Real

Status labels used everywhere in this package:

| Label | Meaning |
|---|---|
| **Production** | Live Supabase Auth/RPC path; intended for real use once env is configured |
| **Partial** | Backend and/or UI exist but incomplete vs contract |
| **Mock** | UI exists with fixture/demo data; looks complete, is not |
| **Hardcoded** | Static values/arrays in source; not driven by tenant data |
| **Not Started** | No feature folder / RPC / page wired |

---

## Cross-cutting

| Module | Status | Notes |
|---|---|---|
| Multi-tenant schema | **Production** | 28 tables, composite FKs, RLS |
| Permission catalogue | **Production** | 33 codes; staff/manager/owner roles |
| `provision_arena` | **Production** | service_role only |
| Seed fixture tenant | **Hardcoded** (intentional) | Dev/staging only; `[FIXTURE]` prefix |
| Offline / outbox / Drift | **Not Started** | Spec exists; deps deferred |
| Realtime floor | **Not Started** | Poll intended; no publications |
| FCM / push | **Not Started** | Deferred in pubspec |
| Receipt printing | **Not Started** | Settle returns receipt fields; no printer |
| Split payments | **Not Started** | Settle is single payment |
| Memberships / wallet / coins | **Not Started** (P0 forbid) | Demo UI only in lobby/fixtures |

---

## Authentication & tenancy

| Module | Status | Evidence |
|---|---|---|
| Email/password sign-in | **Production** | Flutter `AuthRepository`; Web `Login.tsx` + Supabase Auth |
| `me` context (arenas, role, permissions, branding) | **Production** | RPC `me` |
| Branch / arena selection | **Production** | Flutter `BranchSelectorScreen`; Web `BranchSelector` |
| Device registration | **Production** | RPC `register_device` |
| PIN / staff picker login | **Mock** | Flutter `lobby_ui` only |
| Permission-gated navigation | **Partial** | Router + gates; unfinished modules omitted |
| D18 stale client (24h) | **Partial** | In-memory only; lost on process kill |
| OAuth / magic link | **Not Started** | — |

---

## Floor & sessions

| Module | Status | Evidence |
|---|---|---|
| Floor snapshot | **Production** | RPC `floor_snapshot`; Flutter + Web Live Floor |
| Station cards + derived states | **Partial** | live/ending/overtime/paused derived client-side; Epic 7 parity incomplete |
| Start session | **Partial** | RPC works; UI lacks member/game pickers |
| Pause / resume / stop | **Production** | RPCs + Flutter/Web UI |
| End & bill → checkout | **Production** | Epic 5 wire-up |
| Unbilled sessions | **Production** | RPC `unbilled_sessions` + floor snapshot fields |
| Session extend | **Not Started** | No RPC |
| Session cancel | **Not Started** | No RPC |
| Station set maintenance | **Partial** | RPC `station_set_status` exists; limited UI |
| Lobby demo floor | **Mock** | `DemoData` stations |

---

## Checkout & billing

| Module | Status | Evidence |
|---|---|---|
| Open checkout from session | **Production** | `checkout_open` |
| Order preview (server totals) | **Production** | `order_preview` money strings |
| Apply discount | **Partial** | RPC + Flutter; permission-gated |
| Add product to order | **Partial** | RPC `order_add_product`; UI limited |
| Settle payment | **Partial** | Single method settle works; needs open shift |
| Void open order | **Partial** | RPC exists; UI coverage thin |
| Counter sale (no session) | **Partial** | Supported by `checkout_open` null session; UI incomplete |
| Client-side tax math | **Mock** | Lobby demo GST toggle only — not production |

---

## Shift & cash

| Module | Status | Evidence |
|---|---|---|
| Open shift | **Production** | `shift_open` + Flutter/Web |
| Current shift | **Production** | `shift_current` |
| Shift summary | **Production** | `shift_summary` |
| Close shift + variance | **Production** | `shift_close` |
| Cash movements / expenses | **Not Started** | Tables not in P0 schema |

---

## Members

| Module | Status | Evidence |
|---|---|---|
| Members table (DB) | **Partial** | Schema exists; no client SELECT (by design) |
| Member RPCs | **Not Started** | No public member_* functions |
| Flutter Members (production) | **Not Started** | No feature route |
| Flutter Members (lobby) | **Mock** | `DemoData.members` |
| Web Members / plans / record | **Mock** | `ownerFixtures` |

---

## Inventory

| Module | Status | Evidence |
|---|---|---|
| Products / stock tables | **Partial** | Schema + movement triggers; seed products |
| Sell via checkout | **Partial** | `order_add_product` + settle stock move |
| Inventory adjust / receive RPCs | **Not Started** | No `inventory_adjust` |
| Flutter Stock (production) | **Not Started** | — |
| Flutter Stock (lobby) | **Mock** | `DemoData.products` |
| Web Inventory | **Mock** | Fixtures + toast actions |

---

## Reports & dashboard

| Module | Status | Evidence |
|---|---|---|
| Flutter reports | **Not Started** | — |
| Web Dashboard KPIs/charts | **Mock** | Fixtures; floor strip Partial |
| Web Reports | **Mock** | All fixture/static |
| Audit log viewer | **Not Started** | Table + RLS exist; no UI/RPC search |

---

## Owner Web admin modules

| Module | Status |
|---|---|
| Login / shell / theme | **Partial** |
| Live Floor + Checkout + Shift | **Production** |
| Games / Stations admin | **Mock** / **Hardcoded** |
| Staff & roles UI | **Mock** |
| Settings | **Hardcoded** / **Mock** |
| Expenses / Integrations | **Mock** |
| Search / Export chrome | **Hardcoded** |

---

## Commercial surfaces

| Surface | Status |
|---|---|
| Flutter Customer App | **Not Started** |
| Super Admin / platform schema | **Not Started** |
| Marketing website | **Not Started** |
| Customer portal | **Not Started** |
| AI insights | **Not Started** |

---

## Verdict

**What is actually working today:** staff email auth, arena select, floor view, start/pause/resume/stop, checkout settle (with open shift), shift open/close — on Flutter production app and Owner Web live panels — against a migrated Supabase project with seed data.

**What looks working but is not:** lobby demo members/stock/PIN; Owner Web dashboard, reports, CRM, catalogue admin, expenses, integrations, settings.
