#!/usr/bin/env bash

set -euo pipefail

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
source "$WORKSPACE_ROOT/scripts/lib/python_runtime.sh"
EXIT_FAIL=1
DRY_RUN=false
FILES=()

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [--dry-run] <yaml-file> [yaml-file...]

Detect duplicate YAML keys in one or more files.

Options:
  --execute           Execute check (default)
  --dry-run           Print planned checks without parsing files
  -h, --help          Show this help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --execute)
      DRY_RUN=false
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit "$EXIT_OK"
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        FILES+=("$1")
        shift
      done
      break
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage
      exit "$EXIT_ARG"
      ;;
    *)
      FILES+=("$1")
      ;;
  esac
  shift || true
done

if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'At least one YAML file is required\n' >&2
  usage
  exit "$EXIT_ARG"
fi

if [ "$DRY_RUN" = true ]; then
  printf '[DRY-RUN] would check %s file(s) for duplicate YAML keys\n' "${#FILES[@]}"
  for f in "${FILES[@]}"; do
    printf '[DRY-RUN] %s\n' "$f"
  done
  exit "$EXIT_OK"
fi

if ! resolve_python_command; then
  exit "$EXIT_FAIL"
fi

# Run an inline Python checker. Script is read-only and reports duplicate keys.
python_cmd - "$@" "${FILES[@]}" <<'PY'
import re
import sys

files = sys.argv[1:]

if not files:
    print("internal error: no files", file=sys.stderr)
    sys.exit(2)

missing = False
violations = []

# match 'key: rest' lines ignoring lines that start with '-' or '#'
key_re = re.compile(r"^(?P<indent>[ \t]*)(?P<key>[^#:\-][^:]*?)\s*:\s*(?P<rest>.*)$")

for path in files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"missing file: {path}", file=sys.stderr)
        missing = True
        continue

    stack = [(-1, {})]

    for idx, raw in enumerate(lines, start=1):
        line = raw.rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        m = key_re.match(line)
        if not m:
            continue

        indent = len(m.group("indent").replace("\t", "    "))
        key = m.group("key").strip()

        while stack and indent <= stack[-1][0]:
            stack.pop()
        if not stack:
            stack = [(-1, {})]

        keys = stack[-1][1]
        if key in keys:
            violations.append((path, idx, key))
        else:
            keys[key] = idx

        rest = m.group("rest").strip()
        if rest == "":
            stack.append((indent, {}))

if missing:
    sys.exit(2)

if violations:
    for path, line, key in violations:
        print(f"duplicate-key: {path}:{line}: {key}", file=sys.stderr)
    sys.exit(1)

for path in files:
    print(f"ok: {path}")
sys.exit(0)
PY
