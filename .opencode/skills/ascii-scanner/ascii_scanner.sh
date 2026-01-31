#!/usr/bin/env bash
# ascii_scanner.sh - Force ASCII-only compliance check.
# Target: 0x00-0x7F range only.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

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
