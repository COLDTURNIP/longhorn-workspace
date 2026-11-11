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
# Workspace checks execute by default; --dry-run switches to preview mode.
DRY_RUN=${DRY_RUN:-false}
source "$WORKSPACE_ROOT/scripts/lib/defensive_prelude.sh"

BUILD_CHECKS=false
custom_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      custom_args+=("$@")
      break
      ;;
    --build)
      BUILD_CHECKS=true
      ;;
    *)
      custom_args+=("$1")
      ;;
  esac
  shift
done

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Check workspace Git/remotes and working-tree state. Use --build for toolchain checks.

Options:
  --execute           Run selected checks (default)
  --build             Also check Go, Docker, Docker Buildx, and make
  --dry-run, -n       Preview selected checks without executing commands
  --json-log          Emit JSON-formatted log lines
  --no-color          Disable ANSI color output (not used)
  --force             Reserved (no effect)
  -h, --help          Show this help
USAGE
}

defensive_parse_args "${custom_args[@]}"

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "verify-setup does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

if [ "$DRY_RUN" = true ]; then
  if [ "$BUILD_CHECKS" = true ]; then
    info "Dry-run: Would check workspace Git/remotes and working-tree state, plus Go, Docker, Docker Buildx, and make"
  else
    info "Dry-run: Would check workspace Git/remotes and working-tree state"
  fi
  exit "$EXIT_OK"
fi

check_go() {
  if ! command -v go >/dev/null 2>&1; then
    die "Go binary not found. Install Go before using --build"
  fi
  local version
  version=$(go version | awk '{print $3}' | sed 's/go//')
  info "Go version: $version"
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
  # jj-first: in a jj repo the working copy is always a live change;
  # report content changes without modifying user file content.
  local status_output
  if test -d .jj && command -v jj >/dev/null 2>&1; then
    if ! status_output=$(jj diff --summary 2>/dev/null); then
      die "Unable to inspect jj working change"
    fi
    if [ -n "$status_output" ]; then
      warn "Working change has content; preserving user file content (jj diff)"
      return
    fi
  else
    if ! status_output=$(git status --porcelain 2>/dev/null); then
      die "Unable to inspect Git working tree"
    fi
    if [ -n "$status_output" ]; then
      warn "Working tree has uncommitted changes; preserving user file content"
      return
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

check_git_remotes
check_clean_tree

if [ "$BUILD_CHECKS" = true ]; then
  check_go
  check_docker
  check_make_and_buildx
  check_path
fi

info "[SUCCESS] verify-setup completed"
