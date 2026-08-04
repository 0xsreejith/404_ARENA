# 13 — Developer Setup

---

## Clone

```bash
git clone <your-arena-os-remote> arena-os
cd arena-os
```

Product root is `arena-os/` (contains `mobile/`, `web/`, `supabase/`, `docs/`).

---

## Requirements

| Tool | Purpose |
|---|---|
| Flutter (stable) | Staff app — SDK constraint `^3.12.0` |
| Dart (bundled) | Analyze / test |
| Node.js 20+ / npm | Owner Web |
| Docker | Local Supabase |
| Supabase CLI | DB start/reset/test/push |
| Git | — |
| Xcode / Android Studio | Device/simulator builds |

Optional: `gh` for GitHub PRs.

---

## Environment — Flutter

```bash
cd mobile
cp env/development.json.example env/development.json
```

Fill:

```json
{
  "ARENA_ENV": "development",
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_ANON_KEY": "<anon key from supabase status>"
}
```

Rules:
- Anon / publishable key only — never `service_role` (D37)
- `env/*.json` gitignored; commit only `*.example`
- For remote: URL + anon from Supabase project Settings → API

---

## Environment — Web

```bash
cd web
# optional .env
# VITE_SUPABASE_URL=http://127.0.0.1:54321
# VITE_SUPABASE_ANON_KEY=<anon>
```

Code falls back to `http://127.0.0.1:54321` and a stub JWT if unset — usable only against local stack.

---

## Database — local

```bash
# from arena-os/
./scripts/db.sh start          # Docker Supabase
./scripts/db.sh reset          # migrations + seed.sql
./scripts/db.sh test           # pgTAP
./scripts/db.sh lint           # migration lint
./scripts/db.sh new <name>     # new migration file
./scripts/db.sh stop
```

Seed password for sign-in (example):

```bash
# See scripts/db.sh seed — set arena_os.seed_password when seeding remote staging/dev
```

Local seed creates `owner@arena-os.local`, `manager@arena-os.local`, `staff@arena-os.local`. Password empty by default unless configured — set password for interactive login.

Get local anon key:

```bash
supabase status
```

---

## Run Flutter

```bash
cd mobile
flutter pub get

flutter run --flavor development \
  -t lib/main_development.dart \
  --dart-define-from-file=env/development.json

# Design demo (no backend)
flutter run -t lib/main_lobby.dart
```

Staging / production flavors analogous with their env files.

---

## Run Web

```bash
cd web
npm install
npm run dev          # Vite → http://localhost:3000
npm run build
npm run lint         # tsc --noEmit
npm run preview
```

---

## Test

```bash
# Flutter
cd mobile && flutter test
dart format --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings

# Database
cd .. && ./scripts/db.sh test

# Full local CI mirror
./scripts/ci.sh all
# or: ./scripts/ci.sh flutter | database | guard
```

Web: **no test suite**.

---

## Analyze / format / build

| Target | Command |
|---|---|
| Flutter analyze | `flutter analyze --fatal-infos --fatal-warnings` |
| Flutter format | `dart format .` |
| Flutter build | `flutter build apk` / `ipa` with flavor + dart-defines |
| Web typecheck | `npm run lint` |
| Web build | `npm run build` |

Android release still signs with **debug** keystore (`TODO(M7)` in Gradle).

---

## Remote DB promotion

```bash
export SUPABASE_PROJECT_REF_DEVELOPMENT=...
export SUPABASE_PROJECT_REF_STAGING=...
export SUPABASE_PROJECT_REF_PRODUCTION=...

./scripts/db.sh status staging
./scripts/db.sh push staging
./scripts/db.sh verify-parity development staging
# production requires typing "production"
./scripts/db.sh push production
```

`seed` refuses production. Never pull production data to development (D34).

---

## CI

GitHub Actions `.github/workflows/ci.yml`:
1. Flutter job — pub get, format, analyze, test  
2. Database job — guard, supabase start, reset, lint, pgTAP  
3. Aggregator `ci` requires both green  

No secrets / no service_role in CI.

---

## Docs to read first

1. `docs/DECISIONS.md`  
2. `docs/HANDOVER/` (this package)  
3. `docs/MVP.md`, `docs/API.md`, `docs/DATABASE.md`  
4. `CLAUDE.md` (note: Owner Web layout line is stale vs D26a)
