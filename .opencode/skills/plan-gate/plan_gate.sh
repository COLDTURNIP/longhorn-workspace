#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options] [plan_markdown_path]

Lint a Longhorn markdown plan for mandatory plan contract gates.

Options:
  --execute           Perform check (default dry-run semantics)
  --dry-run           Dry-run (default)
  --json-log          Emit JSON log lines
  -h, --help          Show this help
USAGE
}

defensive_parse_args "$@"

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 1 ]; then
  error "Only one optional plan path is allowed"
  defensive_show_help
  exit "$EXIT_ARG"
fi

# Default plan path per task
PLAN_PATH="${DEFENSIVE_POSITIONAL_ARGS[0]:-.sisyphus/plans/atlas-governance-p0-p1.md}"

if [ ! -f "$PLAN_PATH" ]; then
  die "Plan file not found: $PLAN_PATH"
fi

FAIL=0

require_contains() {
  local pattern=$1
  local label=$2
  if ! grep -Eq "$pattern" "$PLAN_PATH"; then
    error "Missing required content: $label"
    FAIL=1
  fi
}

check_required_contract() {
  require_contains "Plan Step Contract" "Plan Step Contract"
  require_contains "Action:" "Action:"
  require_contains "Target:" "Target:"
  require_contains "Verify Command:" "Verify Command:"
  require_contains "Done Criteria:" "Done Criteria:"
  require_contains "Pantoh Reference:" "Pantoh Reference:"
  require_contains "Writing purpose:" "Writing purpose:"
  require_contains "Global Hard Rules" "Global Hard Rules"
  require_contains "Forbidden references" "Forbidden references"
}

# Hotfix Retry Prompt block validation adapted from pantoh
check_hotfix_block() {
  if ! grep -q "Hotfix Retry Prompt" "$PLAN_PATH"; then
    return
  fi

  local in_block=0
  local target_count=0
  local objective_count=0
  local verify_count=0
  local verify_line=""
  local block_index=0

  while IFS= read -r line || [ -n "$line" ]; do
    if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*Hotfix Retry Prompt[[:space:]]*$|^[[:space:]]*#+[[:space:]]+Hotfix Retry Prompt[[:space:]]*$'; then
      if [ "$in_block" -eq 1 ]; then
        if [ "$target_count" -ne 1 ] || [ "$objective_count" -ne 1 ] || [ "$verify_count" -ne 1 ]; then
          error "Hotfix Retry Prompt block $block_index must contain exactly one Target file, Change objective, and Verify line"
          FAIL=1
        fi
        if [ "$verify_count" -eq 1 ] && printf '%s\n' "$verify_line" | grep -Eq '&&|\|\||;|\|'; then
          error "Hotfix Retry Prompt block $block_index Verify must be a single command"
          FAIL=1
        fi
      fi
      in_block=1
      block_index=$((block_index + 1))
      target_count=0
      objective_count=0
      verify_count=0
      verify_line=""
      continue
    fi

    if [ "$in_block" -eq 1 ] && printf '%s\n' "$line" | grep -Eq '^[[:space:]]*#+[[:space:]]+'; then
      if [ "$target_count" -ne 1 ] || [ "$objective_count" -ne 1 ] || [ "$verify_count" -ne 1 ]; then
        error "Hotfix Retry Prompt block $block_index must contain exactly one Target file, Change objective, and Verify line"
        FAIL=1
      fi
      if [ "$verify_count" -eq 1 ] && printf '%s\n' "$verify_line" | grep -Eq '&&|\|\||;|\|'; then
        error "Hotfix Retry Prompt block $block_index Verify must be a single command"
        FAIL=1
      fi
      in_block=0
      continue
    fi

    if [ "$in_block" -eq 1 ]; then
      if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*Target file:[[:space:]]+.+$'; then
        target_count=$((target_count + 1))
      fi
      if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*Change objective:[[:space:]]+.+$'; then
        objective_count=$((objective_count + 1))
      fi
      if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*Verify:[[:space:]]+.+$'; then
        verify_count=$((verify_count + 1))
        verify_line="$line"
      fi
    fi
  done < "$PLAN_PATH"

  if [ "$in_block" -eq 1 ]; then
    if [ "$target_count" -ne 1 ] || [ "$objective_count" -ne 1 ] || [ "$verify_count" -ne 1 ]; then
      error "Hotfix Retry Prompt block $block_index must contain exactly one Target file, Change objective, and Verify line"
      FAIL=1
    fi
    if [ "$verify_count" -eq 1 ] && printf '%s\n' "$verify_line" | grep -Eq '&&|\|\||;|\|'; then
      error "Hotfix Retry Prompt block $block_index Verify must be a single command"
      FAIL=1
    fi
  fi
}

info "Linting plan file: $PLAN_PATH"
check_required_contract
check_hotfix_block

if [ "$FAIL" -ne 0 ]; then
  die "plan-gate failed"
fi

info "[SUCCESS] plan-gate passed"
exit "$EXIT_OK"
