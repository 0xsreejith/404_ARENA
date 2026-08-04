#!/usr/bin/env bash
#
# Database workflow for Arena OS.
#
# Migrations are forward-only and promoted development -> staging -> production
# (D34). This script is the only sanctioned path to a remote database, because
# it is where the guards live:
#
#   * production requires an explicit, typed confirmation
#   * a migration reaches production only after staging has applied it
#   * pulling remote data down is refused outright (D34: production data is
#     never copied into development)
#
# It never contains a credential. `supabase link` stores the project ref, and
# the database password is prompted for or read from SUPABASE_DB_PASSWORD in
# the caller's environment (D37).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

readonly ENVIRONMENTS=("development" "staging" "production")

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

die() { red "error: $*" >&2; exit 1; }

require_supabase_cli() {
  command -v supabase >/dev/null 2>&1 \
    || die "the Supabase CLI is not installed — see https://supabase.com/docs/guides/cli"
}

# Each environment is a separate Supabase project (D34). The ref is read from
# the environment so no project identifier is committed.
project_ref_var_for() {
  case "$1" in
    development) echo "SUPABASE_PROJECT_REF_DEVELOPMENT" ;;
    staging)     echo "SUPABASE_PROJECT_REF_STAGING" ;;
    production)  echo "SUPABASE_PROJECT_REF_PRODUCTION" ;;
    *) die "unknown environment '$1' (expected one of: ${ENVIRONMENTS[*]})" ;;
  esac
}

resolve_project_ref() {
  local env="$1" var ref
  var="$(project_ref_var_for "$env")"
  ref="${!var:-}"
  [[ -n "$ref" ]] || die "$var is not set. Export the $env project ref before running this."
  echo "$ref"
}

confirm_production() {
  bold ""
  red  "  You are about to modify the PRODUCTION database."
  bold "  Real tenants. Real money. Forward-only migrations."
  bold ""
  read -r -p '  Type "production" to continue: ' answer
  [[ "$answer" == "production" ]] || die "aborted"
}

usage() {
  cat <<'USAGE'
Usage: scripts/db.sh <command> [args]

Local development
  start                    Start the local Supabase stack (Docker required)
  stop                     Stop the local stack
  reset                    Recreate the local database from migrations + seed
  new <name>               Create a new timestamped migration file
  test                     Run the pgTAP suite against the local stack
  lint                     Static-check migrations for syntax errors

Promotion (D34: development -> staging -> production)
  status <env>             Show which migrations are applied remotely
  push <env>               Apply pending migrations to <env>
  seed <env>               Apply supabase/seed.sql to development or staging
  verify-parity <a> <b>    Confirm <a> and <b> are on the same migration set

<env> is one of: development, staging, production

Guards
  * push production requires typed confirmation
  * push production refuses unless staging is already up to date
  * seed refuses production outright — fixture pricing never reaches it (D33)
  * there is no "pull data" command by design (D34)
USAGE
}

cmd_start() {
  docker info >/dev/null 2>&1 || die "Docker is not running — the local Supabase stack needs it"
  supabase start
}

cmd_stop() { supabase stop; }

cmd_reset() {
  docker info >/dev/null 2>&1 || die "Docker is not running"
  supabase db reset
}

cmd_new() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "usage: scripts/db.sh new <name>   e.g. new tenant_core"
  supabase migration new "$name"
}

cmd_test() {
  docker info >/dev/null 2>&1 || die "Docker is not running — pgTAP runs inside the local stack"
  supabase test db
}

cmd_lint() {
  docker info >/dev/null 2>&1 || die "Docker is not running"
  supabase db lint --schema public --level warning
}

cmd_status() {
  local env="${1:-}"; [[ -n "$env" ]] || die "usage: scripts/db.sh status <env>"
  local ref; ref="$(resolve_project_ref "$env")"
  supabase link --project-ref "$ref" >/dev/null
  supabase migration list --linked
}

cmd_push() {
  local env="${1:-}"; [[ -n "$env" ]] || die "usage: scripts/db.sh push <env>"
  local ref; ref="$(resolve_project_ref "$env")"

  if [[ "$env" == "production" ]]; then
    # Forward-only promotion: production never receives a migration that
    # staging has not already accepted (D34).
    local staging_ref="${SUPABASE_PROJECT_REF_STAGING:-}"
    [[ -n "$staging_ref" ]] \
      || die "SUPABASE_PROJECT_REF_STAGING must be set so staging parity can be checked before a production push"
    bold "Checking staging is up to date first..."
    supabase link --project-ref "$staging_ref" >/dev/null
    if supabase migration list --linked | grep -qE '^\s*[0-9]+\s*\|\s*\|'; then
      die "staging has unapplied migrations — promote to staging before production"
    fi
    confirm_production
  fi

  supabase link --project-ref "$ref" >/dev/null
  supabase db push --linked
  green "applied pending migrations to $env"
}

# Fixture data (D33). Development and staging only, and the refusal below is
# not advisory: production pricing is entered by a tenant user, and a
# [FIXTURE]-prefixed rate reaching a real invoice is a commercial incident.
cmd_seed() {
  local env="${1:-}"; [[ -n "$env" ]] || die "usage: scripts/db.sh seed <development|staging>"

  if [[ "$env" == "production" ]]; then
    die "refusing to seed production. Fixture pricing is development and staging only (D33).
Real production pricing is configured by a tenant user before M4 acceptance."
  fi

  local ref; ref="$(resolve_project_ref "$env")"

  # Second guard: the environment variables could be crossed over.
  if [[ -n "${SUPABASE_PROJECT_REF_PRODUCTION:-}" && "$ref" == "${SUPABASE_PROJECT_REF_PRODUCTION}" ]]; then
    die "'$env' resolves to the production project ref — refusing to seed"
  fi

  command -v psql >/dev/null 2>&1 \
    || die "psql is required to apply a seed to a remote project"

  local url
  supabase link --project-ref "$ref" >/dev/null
  url="$(supabase db url --linked)" || die "could not resolve the database URL for $env"

  # The seed reads its parameters from settings rather than hardcoding a tenant.
  # Accounts are created without a usable password unless one is supplied.
  {
    printf "set arena_os.seed_password = %s;\n" "$(printf "'%s'" "${ARENA_OS_SEED_PASSWORD:-}")"
    [[ -n "${ARENA_OS_SEED_ARENA_NAME:-}" ]] \
      && printf "set arena_os.seed_arena_name = '%s';\n" "$ARENA_OS_SEED_ARENA_NAME"
    [[ -n "${ARENA_OS_SEED_TIMEZONE:-}" ]] \
      && printf "set arena_os.seed_timezone = '%s';\n" "$ARENA_OS_SEED_TIMEZONE"
    [[ -n "${ARENA_OS_SEED_CURRENCY:-}" ]] \
      && printf "set arena_os.seed_currency = '%s';\n" "$ARENA_OS_SEED_CURRENCY"
    [[ -n "${ARENA_OS_SEED_DIAL_CODE:-}" ]] \
      && printf "set arena_os.seed_dial_code = '%s';\n" "$ARENA_OS_SEED_DIAL_CODE"
    cat "$ROOT/supabase/seed.sql"
  } | psql "$url" -v ON_ERROR_STOP=1 -f -

  green "seeded $env with [FIXTURE] data"
}

cmd_verify_parity() {
  local a="${1:-}" b="${2:-}"
  [[ -n "$a" && -n "$b" ]] || die "usage: scripts/db.sh verify-parity <env> <env>"
  local ref_a ref_b out_a out_b
  ref_a="$(resolve_project_ref "$a")"; ref_b="$(resolve_project_ref "$b")"
  supabase link --project-ref "$ref_a" >/dev/null
  out_a="$(supabase migration list --linked)"
  supabase link --project-ref "$ref_b" >/dev/null
  out_b="$(supabase migration list --linked)"
  if [[ "$out_a" == "$out_b" ]]; then
    green "$a and $b are on the same migration set"
  else
    red "$a and $b differ:"; diff <(echo "$out_a") <(echo "$out_b") || true; exit 1
  fi
}

require_supabase_cli

case "${1:-}" in
  start)         shift; cmd_start "$@" ;;
  stop)          shift; cmd_stop "$@" ;;
  reset)         shift; cmd_reset "$@" ;;
  new)           shift; cmd_new "$@" ;;
  test)          shift; cmd_test "$@" ;;
  lint)          shift; cmd_lint "$@" ;;
  status)        shift; cmd_status "$@" ;;
  push)          shift; cmd_push "$@" ;;
  seed)          shift; cmd_seed "$@" ;;
  verify-parity) shift; cmd_verify_parity "$@" ;;
  ""|-h|--help)  usage ;;
  *)             usage; die "unknown command '$1'" ;;
esac
