#!/usr/bin/env bash

resolve_python_command() {
  if [ -n "${PYTHON_CMD_BIN:-}" ] && command -v "$PYTHON_CMD_BIN" >/dev/null 2>&1 && "$PYTHON_CMD_BIN" -c 'import sys' >/dev/null 2>&1; then
    return 0
  fi

  if [ -n "${PYTHON_CMD:-}" ]; then
    if command -v "$PYTHON_CMD" >/dev/null 2>&1 && "$PYTHON_CMD" -c 'import sys' >/dev/null 2>&1; then
      PYTHON_CMD_BIN="$PYTHON_CMD"
      return 0
    fi
    printf 'Configured PYTHON_CMD is not available or unusable: %s\n' "$PYTHON_CMD" >&2
    return 1
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON_CMD_BIN="python3"
    return 0
  fi

  if command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PYTHON_CMD_BIN="python"
    return 0
  fi

  printf 'Python runtime not found. Install python3 or python, or set PYTHON_CMD.\n' >&2
  return 1
}

python_cmd() {
  if ! resolve_python_command; then
    return 1
  fi
  "$PYTHON_CMD_BIN" "$@"
}
