# 03 — Hardcoded Values

Every hardcoded / fixture / demo value found in the repository.  
**Intentional seed fixtures** (D33) are listed separately from **product hardcoding debt**.

---

## A. Flutter Lobby Demo (`lobby_ui`)

### Where
`mobile/lib/features/lobby_ui/demo_data.dart`  
Consumed by all `lobby_ui` screens/widgets and `main_lobby.dart`.

### What
| Item | Detail |
|---|---|
| Brand | `404 Arena`, mark `404`, product `LOBBY OS` |
| Staff + PINs | Sreejith/`1234`, Prashanth/`1111`, Anand/`2222`, Justin/`3333` |
| Stations | 6 PS/VR/POOL stations with rates, games, players, statuses |
| Members | 6 people, `+91` phones, plans, coins, spend |
| Products | 6 SKUs with stock/sold |
| Shift snapshot | Float, cash/UPI, play sales |
| Collected | `collectedPaise = 642000` |
| Currency format | `inr()` → `₹` |
| Bill math | Client-side including optional 18% GST |

### Why
Design-parity shell ported from `404 Lobby OS.dc.html` before live RPC wiring.

### Replacement plan
Epic 7: converge production `ArenaApp` onto Lobby chrome over live RPCs; demote/gate `main_lobby`; never ship DemoData in production flavours. Guard test already forbids importing `demo_data` outside `lobby_ui`.

---

## B. Owner Web Fixtures

### Where
`web/src/data/ownerFixtures.ts`

### What
| Constant | Contents |
|---|---|
| `FIXTURE_MEMBERS` | 8 people |
| `FIXTURE_GAMES` | 7 titles |
| `FIXTURE_PRODUCTS` | 5 SKUs |
| `FIXTURE_SESSIONS` | 7 rows |
| `FIXTURE_PLANS` | 3 plans |
| `FIXTURE_STAFF` | 4 people |
| `FIXTURE_EXPENSES` | 4 rows |
| `FIXTURE_INTEGRATIONS` | 4 integrations |
| `FIXTURE_VISITS` | 5 visits |
| Helpers | `dashboardKpis`, `hourlyBars`, `dailyBars`, `heatRows`, `payMix`, `zoneRows`, `expiringMembers`, `lowStockProducts` |

### Consumers
`DashboardPage.tsx`, `OwnerPages.tsx`, `OwnerShell.tsx`, `theme/tokens.ts` (`RANGE_MUL`)

### Additional hardcoded UI
| Location | What |
|---|---|
| `DashboardPage.tsx` | Fallback floor rows if `floor_snapshot` fails |
| `OwnerPages.tsx` | Report tile `4120 * mul`; expenses profit `98000 - total`; inline stations array |
| `OwnerShell.tsx` | `unbilled = 1`; “SYNCED 12s AGO” |
| `Login.tsx` | Placeholder email `owner@arena.com` (UX only) |
| `services/supabase.ts` | Fallback URL `http://127.0.0.1:54321` + stub anon JWT |

### Why
HTML Owner Web parity (W1–W13) before CRM/report/admin RPCs exist.

### Replacement plan
Wire each page to real RPCs as Epics 10–11 / OW2–OW9 land; remove fixtures page-by-page; delete toast-only mutations.

---

## C. Production client fallbacks (debt)

| Location | Value | Why | Replacement |
|---|---|---|---|
| `tenant_controller.dart` | Colors `#7CFF4F` / `#00F0FF`; brand `Arena OS`; currency `INR` | Fallback if `me` branding missing | Always require settings from `me` |
| `checkout_controller.dart` | `currency = 'INR'` | Default | From arena context |
| `branch_selector_screen.dart` | `currency ?? 'INR'` | Default | From arena |
| `router.dart` | Device name `'Staff device'`; `appVersion: '0.1.0'` | Telemetry defaults | Build-time version / user-named device |
| `floor_screen.dart` | Strips `[FIXTURE]` prefix for display | Seed readability | Keep for seed only; production data never uses prefix |
| Production login UI | Literals `AOS` / `ARENA OS` | Branding chrome | Arena branding from `me` |
| Migration Epic 1 defaults | Same brand colors on `arena_settings` | Sensible defaults | Overridable per arena (already) |

---

## D. Database seed (intentional fixtures)

### Where
`supabase/seed.sql`

### What
| Item | Detail |
|---|---|
| Org / arena | `404 Labs` / `404 Arena` (overridable settings) |
| Users | `owner@` / `manager@` / `staff@arena-os.local` (fixed UUIDs `5eed…`) |
| Tax | `[FIXTURE] GST 18%` intra/inter with CGST/SGST/IGST |
| Stations | PC-01..03, Console-01 |
| Plans | `[FIXTURE] PC Open Play` 120/hr; Console 1-Hour Pack 150 |
| Products | Cola / Crisps stock 24 |
| Open shift | Float 500.00 so local settle works |

### Why
D33 — development/staging test vectors; seed refuses production and refuses if settled money exists.

### Replacement plan
Do **not** remove. Production pricing entered by tenant users. Never run seed on production (`scripts/db.sh seed` guards).

---

## E. What is NOT hardcoded (correct)

- Play charge, tax, discount, receipt series — computed in SQL via `app.*` algorithms
- Permission decisions — `app.require_permission`
- Actor — `auth.uid()` / `app.current_actor_id()`
- Tenant boundary — composite FKs + RLS

---

## F. Toast-only / fake actions (Web)

All show success UI without persistence:

Add/renew/block member · adjust coins · add game · restock/receive/adjust inventory · add expense · add station · staff permission toggles · integration connect · settings save · export queued
