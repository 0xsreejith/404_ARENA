#!/usr/bin/env bash
#
# Runs the same checks CI runs, locally.
#
# Two suites, deliberately kept separate (D35, ARCHITECTURE.md §13):
# a Flutter test can never substitute for a database security test.
#
#   scripts/ci.sh            both suites
#   scripts/ci.sh flutter    analyzer, format, Flutter tests
#   scripts/ci.sh database   migration guard + replay + lint + pgTAP (needs Docker)
#   scripts/ci.sh guard      the no-tenant-data-in-migrations scan alone

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }

run_flutter() {
  bold "── Flutter ─────────────────────────────────────────────────────────"
  cd "$ROOT/mobile"
  flutter pub get
  bold "dart format (check only)"
  dart format --output=none --set-exit-if-changed --line-length 100 lib test
  bold "flutter analyze"
  flutter analyze --fatal-infos --fatal-warnings
  bold "flutter test"
  flutter test
  cd "$ROOT"
  green "Flutter checks passed"
}

# The SQL counterpart to mobile/test/guards/source_guard_test.dart: migrations
# run against production, so no tenant's name, currency, timezone, dial code or
# tax component may appear in one (CLAUDE.md, D31, D33). Fixture data lives in
# supabase/seed.sql, which never reaches production.
#
# Comment lines are exempt, exactly as they are in the Dart guard: a comment
# explaining why something is forbidden must not trip the guard forbidding it.
run_migration_guard() {
  bold "── Migration guard ─────────────────────────────────────────────────"
  local pattern='\[FIXTURE\]|404[[:space:]]*Arena|CGST|SGST|IGST|GSTIN|Asia/Kolkata|.INR.|\+91'
  local offenders
  offenders="$(grep -rnE --include='*.sql' "$pattern" supabase/migrations 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*--' || true)"
  if [[ -n "$offenders" ]]; then
    red "Tenant or jurisdiction data found in a migration (CLAUDE.md, D31, D33):"
    echo "$offenders"
    return 1
  fi
  green "Migrations contain no tenant or jurisdiction data"
}

run_database() {
  run_migration_guard
  bold "── Database ────────────────────────────────────────────────────────"
  if ! docker info >/dev/null 2>&1; then
    red "Docker is not running — the pgTAP suite cannot run."
    red "Start Docker Desktop and retry, or run: scripts/ci.sh flutter"
    return 1
  fi
  bold "supabase start"
  supabase start
  bold "supabase db reset (migrations replay from empty)"
  supabase db reset
  bold "supabase db lint"
  # Both schemas: `app` holds the helpers every RPC's security depends on.
  supabase db lint --schema public --level warning
  supabase db lint --schema app --level warning
  bold "supabase test db (pgTAP)"
  supabase test db
  green "Database checks passed"
}

case "${1:-all}" in
  flutter)  run_flutter ;;
  database) run_database ;;
  guard)    run_migration_guard ;;
  all)      run_flutter; run_database ;;
  *)        echo "usage: scripts/ci.sh [flutter|database|guard|all]" >&2; exit 1 ;;
esac
