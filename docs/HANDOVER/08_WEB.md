# 08 — Owner Web

**Package:** `arena-os-web` `0.1.0`  
**Path:** `arena-os/web/`  
**Stack:** Vite · React 18 · TypeScript · `@supabase/supabase-js` · lucide-react  
**No** react-router, chart library, test runner, or project README.

---

## Pages / screens

Navigation is in-memory (`OwnerShell` screen state). Decorative URL: `manage.arena-os.local/{path}`.

| Screen id | Component | Data status |
|---|---|---|
| `dash` | DashboardPage | **Partial** — fixtures KPIs; floor strip live with hardcoded fallback |
| `reports` | ReportsPage | **Mock** |
| `sessions` | SessionsPage | **Mock** |
| `members` | MembersPage | **Mock** |
| `member` | MemberRecordPage | **Mock** |
| `plans` | MembershipsPage | **Mock** |
| `shift` | ShiftPanel | **Production** (cyber surface) |
| `games` | GamesPage | **Mock** |
| `products` | InventoryPage | **Mock** |
| `expenses` | ExpensesPage | **Mock** |
| `live` | LiveFloorGrid | **Production** (cyber surface) |
| `stations` | StationsAdminPage | **Hardcoded** |
| `staff` | StaffPage | **Mock** |
| `integrations` | IntegrationsPage | **Mock** |
| `settings` | SettingsPage | **Hardcoded** / **Mock** |

Unauthenticated → `Login.tsx` (real Supabase password auth).

---

## Components

| Component | Role |
|---|---|
| `OwnerShell` | Sidebar, chrome, theme, toasts, nav |
| `LiveFloorGrid` | Live floor RPC UI |
| `CheckoutPanel` | Checkout RPCs |
| `ShiftPanel` | Shift RPCs |
| `BranchSelector` | Arena switch |
| `NavigationShell` | **Orphan** — unused dark cyber shell |

---

## Charts

Custom CSS/div bars — **no chart library**. All report/dashboard charts use fixture helpers (`hourlyBars`, `dailyBars`, `heatRows`, `payMix`, `zoneRows`) scaled by `RANGE_MUL`.

---

## Auth

1. `signInWithPassword`
2. `getSession` + `rpc('me')`
3. `onAuthStateChange`
4. `hasPermission(code)` from selected arena
5. Optional `register_device` when `station.view`

Env: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (fallback localhost defaults in code).

---

## Theme

| File | Role |
|---|---|
| `styles/owner.css` | Light Owner chrome (canvas `#F4F5F8`, accent `#4C4DDC`) |
| `styles/cyber.css` | Dark counter for Live Floor / Shift |
| `theme/tokens.ts` | Light/dark CSS variables; screen meta |

Fonts: Barlow, Chakra Petch, JetBrains Mono.

---

## Live RPC surface

`me` · `register_device` · `floor_snapshot` · `session_*` · `checkout_open` · `order_preview` · `order_settle` · `shift_*`

No `.from()` table queries in `src/`.

---

## Current status

- **Production-capable:** Login, Live Floor, Checkout, Shift
- **Prototype UI only:** Everything else in W1–W13
- Parity audit “Done” means **shell/layout**, not live data

---

## Missing pages (as product, not fixtures)

Real data wiring for: dashboard aggregates, reports, sessions history, members CRM, memberships, games admin, inventory admin, expenses, stations admin from DB, staff/roles mutations, settings RPCs, integrations, search, export, deep-link routing.
