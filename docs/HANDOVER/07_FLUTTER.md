# 07 — Flutter App

**Package:** `arena_os` `0.1.0+1`  
**Path:** `arena-os/mobile/`  
**SDK:** Dart `^3.12.0`

---

## Two entrypoints

| Entry | Purpose | Data |
|---|---|---|
| `main_development.dart` / `staging` / `production` | Production staff app | Supabase |
| `main_lobby.dart` | Design/demo shell | `DemoData` only |

Treat `lobby_ui` as a **design artifact**. Ship/maintain production features under `auth`, `floor`, `checkout`, `shift`, `tenant`, `shell`, `devices`.

---

## Features (production)

| Feature | Status | Notes |
|---|---|---|
| Auth email/password | Production | |
| Branch select + device register | Production | |
| Floor snapshot + station cards | Production / Partial | Session start missing member/game |
| Session pause/resume/stop | Production | |
| Checkout | Partial | No printer; memberId often unset |
| Shift open/close/summary | Production | |
| Permissions / stale / no-access | Partial | |
| Members | Not Started (demo in lobby) | |
| Inventory | Not Started (demo in lobby) | |
| Reports | Not Started | |
| Offline | Not Started | Drift deferred |

---

## Routing (`lib/app/router.dart`)

| Path | Screen | Gate |
|---|---|---|
| `/sign-in` | LoginScreen | — |
| `/arenas` | BranchSelectorScreen | session |
| `/stale` | StaleScreen | D18 |
| `/no-access` | NoAccessScreen | — |
| `/floor` | FloorScreen | session.view \|\| station.view |
| `/shift` | ShiftScreen | shift.view |
| `/checkout/:orderId` | CheckoutScreen | payment.create |

Redirect machine: session → arena → staleness → permission → destination.  
Shell: `StaffShell` wraps floor/shift/checkout.

---

## Controllers & repositories

| Feature | Controller | Repository RPCs |
|---|---|---|
| Auth | AuthControllerNotifier | Auth API + `me` |
| Tenant | TenantController | from `me` |
| Floor | FloorController | floor_snapshot, session_* |
| Checkout | CheckoutController | checkout_open, order_preview, order_apply_discount, order_settle |
| Shift | ShiftController | shift_current/open/summary/close |
| Devices | — | register_device + SharedPreferences UUID |

---

## Widgets / theme / animations

- Theme: `ArenaTheme.dark`, `ArenaColors`, Google Fonts (Barlow, JetBrains Mono, Chakra Petch)
- Min touch 56; no decorative splash
- Lobby animations (`lobby_anims.dart`): blink, breathe, overtime pulse, etc. — used heavily in demo; production shell lighter
- Production floor uses shared live station card data path (Epic 7 Phase 2)

---

## State management

Riverpod 3 only. No Dio. Hand-written state classes (no Freezed yet).

---

## Offline

**Not implemented.** Spec in `docs/OFFLINE.md`. `OfflineFailure` type exists unused. Drift/sqlite deferred in pubspec. Stale gate is in-memory only.

---

## Environment

```bash
# Copy example
cp env/development.json.example env/development.json
# Fill SUPABASE_URL + SUPABASE_ANON_KEY (anon only)

flutter run --flavor development \
  -t lib/main_development.dart \
  --dart-define-from-file=env/development.json

# Demo only
flutter run -t lib/main_lobby.dart
```

Android flavors: `development` / `staging` / `production`.

---

## Tests

| Suite | Coverage |
|---|---|
| `test/core/**` | Env, failures, logging, money |
| `test/app/theme_test.dart` | Theme |
| `test/guards/source_guard_test.dart` | No Dio/Bloc/secrets/tenant literals |
| `test/no_demo_data_in_production_test.dart` | Demo isolation |

**Absent:** feature widget tests, integration_test, goldens.

---

## Known issues

1. Dual app paths until Epic 7 exits
2. Session start UI omits member/game
3. Release Android still uses debug keystore
4. Source guard may conflict with remaining INR/`404 Arena` strings in production/demo
5. `mobile/README.md` is still the default Flutter template
6. CLAUDE.md lists Freezed/Drift as stack — not yet in pubspec
