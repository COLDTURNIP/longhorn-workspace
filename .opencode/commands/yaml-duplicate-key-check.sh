#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
EXIT_OK=0
EXIT_ARG=2
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

# Run an inline Python3 checker. Script is read-only and reports duplicate keys.
python3 - "$@" "${FILES[@]}" <<'PY'
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
