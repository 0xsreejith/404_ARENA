# Arena OS

Multi-tenant operations platform for gaming centres — floor, sessions, checkout, stock, members, and shift cash in one system.

**404 Arena is tenant #1 (pilot). It is not the product.**

---

## Status (2026-08-04)

| Item | State |
|---|---|
| Schema + security core (M1) | Done |
| Epics 3C–6 (checkout integrity, auth, floor billing, shifts) | Done |
| Epic 7 (Lobby chrome on live data) | In progress (Phases 1–2) |
| Formal MVP exit (ROADMAP M7) | **Not complete** |
| Commercial SaaS catalogue | Mostly documentation — not built |

**What works today:** email auth → arena select → floor → start/pause/resume/stop → checkout settle → shift open/close (Flutter + Owner Web live panels).

**What does not:** members CRM, inventory admin, offline sync, real reports, memberships/wallet, most Owner Web modules (fixture UI).

Full honesty package: **[`docs/HANDOVER/`](docs/HANDOVER/)** — start at [`PROJECT_HEALTH_REPORT.md`](docs/HANDOVER/PROJECT_HEALTH_REPORT.md).

---

## Repository layout

```
mobile/      Flutter staff / manager app (phone + tablet)
web/         Owner / staff React app (D26a)
supabase/    Migrations, RPCs, RLS, seed, pgTAP
docs/        Binding product contract
scripts/     ci.sh, db.sh
```

---

## Quick start

### Database

```bash
./scripts/db.sh start
./scripts/db.sh reset    # migrations + seed
./scripts/db.sh test
```

### Flutter

```bash
cd mobile
cp env/development.json.example env/development.json
# set SUPABASE_URL + SUPABASE_ANON_KEY from `supabase status`
flutter pub get
flutter run --flavor development \
  -t lib/main_development.dart \
  --dart-define-from-file=env/development.json
```

### Owner Web

```bash
cd web
npm install
npm run dev   # http://localhost:3000
```

Details: [`docs/HANDOVER/13_DEVELOPER_SETUP.md`](docs/HANDOVER/13_DEVELOPER_SETUP.md).

---

## Documentation map

| Document | Contents |
|---|---|
| [`docs/HANDOVER/`](docs/HANDOVER/) | **Codebase audit & handover (start here for onboarding)** |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | **Authoritative** decisions |
| [`docs/MVP.md`](docs/MVP.md) | P0 scope |
| [`docs/DATABASE.md`](docs/DATABASE.md) | Schema + money algorithms |
| [`docs/API.md`](docs/API.md) | RPC contract (target; verify against migrations) |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Auth, RLS, privacy |
| [`docs/OFFLINE.md`](docs/OFFLINE.md) | Offline matrix |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | M0–M10 |
| [`docs/commercial/`](docs/commercial/) | Full SaaS bible (aspirational) |
| [`CLAUDE.md`](CLAUDE.md) | Agent rules (Owner Web layout note may lag D26a) |

`docs/DECISIONS.md` wins any disagreement.

---

## Principles

1. Server owns money, stock, and permissions  
2. Mutations via `SECURITY DEFINER` RPCs only  
3. Composite tenant foreign keys  
4. No Dio / parallel REST backend  
5. Pricing is data — never hardcoded rates in code  
6. Checkout does not work offline  

---

## MVP in one line

Run one real gaming centre's trading day with no notebook, and balance the drawer at close (`docs/ROADMAP.md` M7). Tenant #2 is validated afterwards (M10).
# 404_ARENA
