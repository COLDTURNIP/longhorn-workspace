#!/usr/bin/env bash
# ascii_scanner.sh - Force ASCII-only compliance check.
# Target: 0x00-0x7F range only.

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

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options] <target_path>

Scan files/dirs for non-ASCII bytes (0x00-0x7F allowed).

Options:
  --execute           Run scan (default)
  --dry-run           Describe scan target and exit
  --json-log          Emit JSON logs
  --no-color          Disable ANSI color (not used)
  --force             Unused (kept for interface parity)
  -h, --help          Show help
USAGE
}

defensive_parse_args "$@"

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -lt 1 ]; then
    error "Target path required"
    defensive_show_help
    exit "$EXIT_ARG"
fi

TARGET=${DEFENSIVE_POSITIONAL_ARGS[0]#@}

if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] Would scan target: $TARGET"
    exit "$EXIT_OK"
fi

if [ ! -e "$TARGET" ]; then
    die "Target path does not exist: $TARGET"
fi

info "[INFO] Scanning for non-ASCII characters in: $TARGET"
FOUND_VIOLATIONS=$(LC_ALL=C grep -rnP '[^\x00-\x7f]' "$TARGET" --exclude-dir=".git" || true)

if [ -n "$FOUND_VIOLATIONS" ]; then
    echo "------------------------------------------------------------"
    echo "[VIOLATION DETECTED] Non-ASCII characters found:"
    echo "$FOUND_VIOLATIONS"
    echo "------------------------------------------------------------"
    die "Compliance check failed. Remove non-ASCII characters."
else
    info "[SUCCESS] ASCII compliance check passed for: $TARGET"
    exit "$EXIT_OK"
fi
