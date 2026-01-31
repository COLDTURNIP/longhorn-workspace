#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Validate Longhorn workspace prerequisites (Go, Docker, Dapper/make, git remotes, clean tree).

Options:
  --execute           Run all checks (default)
  --dry-run           Describe checks without executing
  --json-log          Emit JSON-formatted log lines
  --no-color          Disable ANSI color output (not used)
  --force             Reserved (no effect)
  -h, --help          Show this help
USAGE
}

defensive_parse_args "$@"

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "verify-setup does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

if [ "$DRY_RUN" = true ]; then
  info "Dry-run: Would check Go, Docker, make/dapper, git remotes, clean tree"
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

check_make() {
  if ! command -v make >/dev/null 2>&1; then
    die "make command missing. Install build-essential or equivalent"
  fi
  if ! command -v dapper >/dev/null 2>&1; then
    warn "dapper binary not found in PATH; make will download it on demand"
  fi
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
  if [ -n "$(git status --porcelain)" ]; then
    die "Working tree dirty; stash/commit changes before proceeding"
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
check_make
check_git_remotes
check_clean_tree
check_path

info "[SUCCESS] verify-setup completed"
