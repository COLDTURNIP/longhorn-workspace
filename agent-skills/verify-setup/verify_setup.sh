#!/usr/bin/env bash

resolve_script_dir() {
  local source_path=${BASH_SOURCE[0]} source_dir target
  while [ -h "$source_path" ]; do
    source_dir=$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P)
    target=$(readlink "$source_path")
    case "$target" in
      /*) source_path=$target ;;
      *) source_path="$source_dir/$target" ;;
    esac
  done
  CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P
}
SCRIPT_DIR=$(resolve_script_dir)
WORKSPACE_ROOT=$SCRIPT_DIR
while [ ! -f "$WORKSPACE_ROOT/AGENTS.md" ] || [ ! -d "$WORKSPACE_ROOT/agent-skills" ] || [ ! -d "$WORKSPACE_ROOT/repo" ]; do
  PARENT_DIR=$(dirname "$WORKSPACE_ROOT")
  if [ "$PARENT_DIR" = "$WORKSPACE_ROOT" ]; then
    printf '%s\n' "Longhorn workspace root not found" >&2
    exit 3
  fi
  WORKSPACE_ROOT=$PARENT_DIR
done
cd "$WORKSPACE_ROOT"
source "$WORKSPACE_ROOT/scripts/lib/defensive_prelude.sh"

# Support a local --plan-mode flag without changing defensive_prelude parsing
PLAN_MODE=false
plan_mode_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan-mode)
      PLAN_MODE=true
      shift
      ;;
    *)
      plan_mode_args+=("$1")
      shift
      ;;
  esac
done
set -- "${plan_mode_args[@]:-}"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Validate Longhorn workspace prerequisites (Go, Docker, Docker Buildx, make, git remotes, clean tree).

Options:
  --execute           Run all checks (default)
  --dry-run           Describe checks without executing
  --json-log          Emit JSON-formatted log lines
  --no-color          Disable ANSI color output (not used)
  --force             Reserved (no effect)
  --plan-mode         Also verify plan-mode prerequisites
  -h, --help          Show this help
USAGE
}

defensive_parse_args "$@"

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "verify-setup does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

if [ "$DRY_RUN" = true ] && [ "$PLAN_MODE" != true ]; then
  info "Dry-run: Would check Go, Docker, Docker Buildx, make, git remotes, clean tree"
  exit "$EXIT_OK"
fi

# When plan-mode is enabled, run lightweight plan-mode prereqs (non-fatal warnings)
check_plan_mode_prerequisites() {
  # Only act if plan-mode enabled
  if [ "$PLAN_MODE" != true ]; then
    return
  fi

  # Verify plan-mode prerequisites (fatal if missing)
  local plan_doc="AGENTS.d/plan-and-delegation.md"

  if [ ! -f "$plan_doc" ]; then
    die "plan-mode requires $plan_doc"
  fi
  if ! grep -q "Plan Step Contract" "$plan_doc" 2>/dev/null; then
    die "plan-mode check failed: missing Plan Step Contract marker in $plan_doc"
  fi
  # If boulder state exists, inspect active_plan and warn if it references a missing file
  local bfile=".sisyphus/boulder.json"
  if [ ! -f "$bfile" ]; then
    return
  fi

  # Extract the active_plan value from the JSON file (simple sed-based parse)
  local active
  active=$(sed -n 's/.*"active_plan"[[:space:]]*:[[:space:]]*"\([^" ]*\)".*/\1/p' "$bfile" || true)
  if [ -n "$active" ]; then
    if [ ! -f "$active" ]; then
      warn ".sisyphus/boulder.json active_plan points to missing file: $active"
    fi
  fi
}

check_plan_mode_prerequisites

# If running in dry-run after executing plan-mode prereqs, exit early to avoid
# performing environment checks that may fail in CI/local without required tools.
if [ "$DRY_RUN" = true ]; then
  info "Dry-run (plan-mode): performed plan-mode prereqs"
  exit "$EXIT_OK"
fi

MIN_GO_VERSION=${MIN_GO_VERSION:-1.21}

check_go() {
  if ! command -v go >/dev/null 2>&1; then
    die "Go binary not found. Install Go >= $MIN_GO_VERSION"
  fi
  VERSION=$(go version | awk '{print $3}' | sed 's/go//')
  info "Go version: $VERSION"
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    die "docker binary not found. Install Docker desktop/engine"
  fi
  if ! docker info >/dev/null 2>&1; then
    die "Docker daemon unreachable. Start Docker before proceeding"
  fi
  info "Docker daemon reachable"
}

check_make_and_buildx() {
  if ! command -v make >/dev/null 2>&1; then
    die "make command missing. Install build-essential or equivalent"
  fi
  if ! docker buildx version >/dev/null 2>&1; then
    die "docker buildx unavailable. Install/enable Docker Buildx before running native Longhorn Make targets"
  fi
  info "Make and Docker Buildx available"
}

check_git_remotes() {
  local remote_status="ok"
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    die "verify-setup must run inside the workspace git repository"
  fi
  if ! git remote get-url upstream >/dev/null 2>&1; then
    warn "Missing upstream remote; configure one when collaborating with Longhorn upstream"
    remote_status="warn"
  elif ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
    warn "Cannot resolve refs/remotes/upstream/HEAD. Run 'git remote set-head upstream --auto' later"
    remote_status="warn"
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    warn "origin remote missing. PR pushes expect origin/<feature>"
    remote_status="warn"
  fi
  if [ "$remote_status" = "ok" ]; then
    info "Git remotes configured correctly"
  fi
}

check_clean_tree() {
  if [ "${SKIP_CLEAN_CHECK:-false}" = true ]; then
    warn "Skipping clean tree check due to SKIP_CLEAN_CHECK=true"
    return
  fi
  # jj-first: in a jj repo the working copy is always a live change;
  # treat it as dirty only when jj diff reports actual content.
  if test -d .jj && command -v jj >/dev/null 2>&1; then
    if [ -n "$(jj diff --summary 2>/dev/null)" ]; then
      die "Working change has content; complete or abandon before proceeding (jj diff)"
    fi
  else
    if [ -n "$(git status --porcelain)" ]; then
      die "Working tree dirty; stash/commit changes before proceeding"
    fi
  fi
  info "Working tree clean"
}

check_path() {
  if command -v go >/dev/null 2>&1; then
    GOPATH_BIN="${GOPATH:-$HOME/go}/bin"
    case ":$PATH:" in
      *":$GOPATH_BIN:"*) ;;
      *) warn "PATH missing $GOPATH_BIN; Go-installed tools may be unavailable" ;;
    esac
  fi
}

check_go
check_docker
check_make_and_buildx
check_git_remotes
check_clean_tree
check_path

info "[SUCCESS] verify-setup completed"
