#!/usr/bin/env bash
# Defensive shell prelude shared by Longhorn workspace skills

set -euo pipefail

# Defaults (scripts may override before sourcing)
: "${SCRIPT_NAME:=$(basename "$0")}"
DRY_RUN=${DRY_RUN:-true}
FORCE=${FORCE:-false}
JSON_LOG=${JSON_LOG:-false}
NO_COLOR=${NO_COLOR:-false}
EXIT_OK=0
EXIT_ARG=2
EXIT_ENV=3
DEFENSIVE_POSITIONAL_ARGS=()

log_line() {
  local level=$1 msg=$2 ts
  ts=$(date -Iseconds)
  if [ "$JSON_LOG" = true ]; then
    printf '{"time":"%s","level":"%s","msg":"%s"}\n' "$ts" "$level" "$msg"
  else
    printf '[%s] [%s] %s\n' "$ts" "$level" "$msg"
  fi
}

info() { log_line INFO "$1"; }
warn() { log_line WARN "$1"; }
error() { log_line ERROR "$1" >&2; }

defensive_show_help() {
  if declare -f usage >/dev/null 2>&1; then
    usage
  else
    cat <<USAGE
${SCRIPT_NAME} [options]
  --execute           Perform actions (default is dry-run)
  --force             Permit destructive steps (requires --execute)
  --json-log          Emit JSON log lines
  --no-color          Disable ANSI color sequences in script output
  -n, --dry-run       Force dry-run mode (default)
  -h, --help          Show this help message
USAGE
  fi
}

defensive_parse_args() {
  DEFENSIVE_POSITIONAL_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --execute) DRY_RUN=false ;;
      --force) FORCE=true ;;
      --json-log) JSON_LOG=true ;;
      --no-color) NO_COLOR=true ;;
      -n|--dry-run) DRY_RUN=true ;;
      -h|--help)
        defensive_show_help
        exit "$EXIT_OK"
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          DEFENSIVE_POSITIONAL_ARGS+=("$1")
          shift
        done
        break
        ;;
      -*)
        error "Unknown option: $1"
        defensive_show_help
        exit "$EXIT_ARG"
        ;;
      *)
        DEFENSIVE_POSITIONAL_ARGS+=("$1")
        ;;
    esac
    shift || true
  done
}

defensive_require_clean_tree() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain)" ]; then
      die "Working tree dirty; stash or commit changes before running $SCRIPT_NAME"
    fi
  else
    warn "Not inside a git repository; skipping clean tree check"
  fi
}

defensive_require_upstream_head() {
  if ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
    die "Missing refs/remotes/upstream/HEAD. Configure upstream remote before continuing."
  fi
}

defensive_record_safety_ref() {
  if git rev-parse HEAD >/dev/null 2>&1; then
    git rev-parse HEAD > .safety-ref || warn "Unable to record safety ref"
  fi
}

defensive_backup_file() {
  local target=$1
  if [ ! -e "$target" ]; then
    warn "No existing file to back up: $target"
    return
  fi
  local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$target" "$backup"
  info "Backed up $target to $backup"
}

defensive_atomic_write() {
  local target=$1
  local tmp
  tmp=$(mktemp "${target}.XXXX")
  cat >"$tmp"
  mv "$tmp" "$target"
}

defensive_run_cmd() {
  local cmd=$1
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] $cmd"
  else
    info "[EXEC] $cmd"
    eval "$cmd"
  fi
}

defensive_require_force() {
  local action=$1
  if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
    die "Refusing to ${action} without --force"
  fi
}

die() {
  error "$1"
  exit "$EXIT_ENV"
}
