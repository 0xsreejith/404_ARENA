# 04 — Architecture

---

## Repository layout

```
404_ARENA/                         # Workspace (audits, HTML prototype, support.js)
└── arena-os/                      # Git product repository
    ├── mobile/                    # Flutter staff/manager app
    ├── web/                       # Owner / staff React SPA (D26a)
    ├── supabase/                  # Migrations, seed, pgTAP
    ├── docs/                      # Binding product contract
    ├── scripts/                   # ci.sh, db.sh
    ├── .github/workflows/ci.yml
    ├── CLAUDE.md                  # Agent/contributor rules (partially stale vs D26a)
    └── README.md
```

---

## System architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  Flutter staff app  │     │  Owner Web (React)  │
│  Riverpod + go_router│     │  AuthContext + screens│
└──────────┬──────────┘     └──────────┬──────────┘
           │  supabase-js / supabase_flutter
           │  Auth + RPC only (no Dio, no custom REST)
           ▼
┌─────────────────────────────────────────────────┐
│                 Supabase                         │
│  Auth · PostgREST SELECT (RLS) · SECURITY DEFINER│
│  RPCs · Postgres 17 · (Realtime service unused) │
└─────────────────────────────────────────────────┘
```

**D24:** There is no separate application backend.  
**D05:** All stateful/financial mutations go through `SECURITY DEFINER` RPCs.  
**Clients:** anon key only (D37). Never `service_role` in apps.

---

## Flutter feature structure

```
mobile/lib/
  app/           ArenaApp, bootstrap, router, theme
  core/          config, errors, logging, money, permissions, supabase
  features/
    auth/        Login, AuthController, AuthRepository
    tenant/      Branch select, TenantController
    devices/     DeviceRepository
    floor/       FloorScreen, FloorController, FloorRepository
    checkout/    CheckoutScreen, controller, repository
    shift/       ShiftScreen, controller, repository
    shell/       StaffShell, StaleScreen, NoAccessScreen
    permissions/ PermissionGate
    lobby_ui/    DEMO shell — DemoData, no Supabase
```

**Pattern:** UI → Riverpod `Notifier` controller → Repository → `supabase.rpc(...)`.

Reads are intended to be Stream-shaped for future Realtime; current floor uses poll/timer UI refresh, not Realtime channels.

---

## React structure

```
web/src/
  App.tsx              Auth gate + OwnerRouter
  context/AuthContext  Session + me() + arena selection
  components/          LiveFloorGrid, CheckoutPanel, ShiftPanel, OwnerShell
  pages/               Login, DashboardPage, OwnerPages (many screens)
  services/            supabase, floor, shift, checkout, device
  data/ownerFixtures   Mock back-office data
  styles/              owner.css (light back-office), cyber.css (dark floor/shift)
  theme/tokens.ts      OWNER_LIGHT / OWNER_DARK
```

**Routing:** In-memory screen state (no react-router). Decorative URL strip only.

---

## Riverpod (Flutter)

| Provider | Role |
|---|---|
| `authControllerProvider` | Sign-in state |
| `tenantControllerProvider` | Arenas, branding, permissions, currency |
| `floorControllerProvider` | Snapshot + 1s UI ticker |
| `checkoutControllerProvider` | Checkout flow |
| `shiftControllerProvider` | Shift open/close/summary |
| `canProvider` | Permission family |
| `goRouterProvider` | Redirect machine |
| `lastServerContactProvider` | Stale gate clock |

No Bloc / GetX. Freezed not yet adopted.

---

## Supabase / RPC flow

1. Client authenticates → JWT
2. Client calls `rpc('name', params)` with `p_arena_id`
3. Function `SECURITY DEFINER` → `app.require_permission(arena, code)`
4. Actor from `app.current_actor_id()` — never a client param
5. Mutations write tables; audit via `app.audit`; idempotency via `claim/complete`
6. Client SELECT (where granted) is RLS-scoped; members/receipt_counters/idempotency_keys have no SELECT

---

## Authentication flow

```
Sign in (email/password)
  → session
  → rpc me()
  → arenas[] + permissions[]
  → select arena
  → register_device
  → first permitted route (/floor or /shift)
  → stale redirect if >24h since last server contact (in-memory)
```

---

## Session flow

```
floor_snapshot
  → idle station → session_start (client UUID, plan, optional member/game)
  → active ↔ paused (pause/resume)
  → session_stop → station free; session completed
  → unbilled until checkout_open → settle
```

Stored statuses only: `active | paused | completed | cancelled`.  
Derived UI: `idle | live | ending | overtime | paused | maintenance | inactive`.  
**Never write DB on timer tick.**

---

## Checkout flow

```
checkout_open(order_id, session_id?)
  → optional order_add_product
  → optional order_apply_discount
  → order_preview (authoritative totals as strings)
  → order_settle (requires open shift; single payment)
  → receipt number from app.next_receipt_number
  → stock movements on settle
```

Offline checkout is forbidden (D15).

---

## Theme

| Surface | Theme |
|---|---|
| Flutter production | Dark `ArenaTheme` — Barlow, JetBrains Mono, Chakra Petch accents |
| Flutter lobby_ui | Lobby HTML port + animations |
| Owner Web shell | Light canvas `#F4F5F8`, accent `#4C4DDC` (`owner.css`) |
| Owner Live Floor / Shift | Dark cyber tokens (`cyber.css`) |

Branding fields on `arena_settings`: `brand_name`, `logo_url`, `primary_color`, `accent_color` — returned by `me`.

---

## Data flow rules

1. Server owns money — Flutter/React never submit computed bill amounts for storage
2. Money: Postgres `numeric(12,2)` ↔ Dart minor-unit `int` (parse string, never `double`)
3. Client-generated UUIDs for sessions/orders/payments/devices
4. Idempotency keys on mutating RPCs where implemented
5. 404 Arena is tenant data, never product code (D33)
