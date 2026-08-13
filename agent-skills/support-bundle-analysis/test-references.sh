#!/usr/bin/env bash
# Reference Validation Test for Support Bundle Analysis Skill

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
SKILL_DIR="agent-skills/support-bundle-analysis"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]
Validate cross-module references and anchors for support-bundle-analysis skill.
Options: --execute (default), --dry-run, --json-log, --no-color, --force (unused), -h/--help
USAGE
}

defensive_parse_args "$@"
if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "This script does not take positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

if [ "$DRY_RUN" = true ]; then
  info "[DRY-RUN] Would validate references in support-bundle-analysis skill"
  exit "$EXIT_OK"
fi

SKILL_DIR="agent-skills/support-bundle-analysis"
PASSED=0
FAILED=0

info "=== Reference Validation Test ==="

echo "Test 1: File References"
for file in SKILL.md diagnostic-flows.md patterns-library.md; do
    if [ -f "$SKILL_DIR/$file" ]; then
        info "  [PASS] $file exists"
        PASSED=$((PASSED + 1))
    else
        error "  [FAIL] $file does NOT exist"
        FAILED=$((FAILED + 1))
    fi
done
echo ""

echo "Test 2: diagnostic-flows.md Anchors"
ANCHORS=("pod-diagnosis" "node-diagnosis" "storage-diagnosis" "network-diagnosis" "pod-quick-scan" "node-quick-scan" "storage-quick-scan" "network-quick-scan")
for anchor in "${ANCHORS[@]}"; do
    if grep -q "{#$anchor}" "$SKILL_DIR/diagnostic-flows.md"; then
        info "  [PASS] Anchor #$anchor exists"
        PASSED=$((PASSED + 1))
    else
        error "  [FAIL] Anchor #$anchor NOT found"
        FAILED=$((FAILED + 1))
    fi
done
echo ""

echo "Test 3: patterns-library.md Anchors"
ANCHORS=("timeline-reconstruction" "5-whys-method" "evidence-based-analysis" "patterns-library" "examples" "example-1" "example-2" "quick-reference")
for anchor in "${ANCHORS[@]}"; do
    if grep -q "{#$anchor}" "$SKILL_DIR/patterns-library.md"; then
        info "  [PASS] Anchor #$anchor exists"
        PASSED=$((PASSED + 1))
    else
        error "  [FAIL] Anchor #$anchor NOT found"
        FAILED=$((FAILED + 1))
    fi
done
echo ""

echo "Test 4: References in SKILL.md"
if grep -q "@diagnostic-flows.md" "$SKILL_DIR/SKILL.md"; then
    info "  [PASS] References to @diagnostic-flows.md found"
    PASSED=$((PASSED + 1))
else
    error "  [FAIL] No references to @diagnostic-flows.md"
    FAILED=$((FAILED + 1))
fi

if grep -q "@patterns-library.md" "$SKILL_DIR/SKILL.md"; then
    info "  [PASS] References to @patterns-library.md found"
    PASSED=$((PASSED + 1))
else
    error "  [FAIL] No references to @patterns-library.md"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 5: XML Tags Validation"
if grep -q "<mandatory_requirements>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</mandatory_requirements>" "$SKILL_DIR/SKILL.md"; then
    info "  [PASS] <mandatory_requirements> tag properly closed"
    PASSED=$((PASSED + 1))
else
    error "  [FAIL] <mandatory_requirements> tag not properly closed"
    FAILED=$((FAILED + 1))
fi

if grep -q "<step_1>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</step_1>" "$SKILL_DIR/SKILL.md" && \
   grep -q "<ticket_scope>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</ticket_scope>" "$SKILL_DIR/SKILL.md" && \
   grep -q "<outside_ticket_scope>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</outside_ticket_scope>" "$SKILL_DIR/SKILL.md"; then
    info "  [PASS] <step_1> extraction decision tags properly closed"
    PASSED=$((PASSED + 1))
else
    error "  [FAIL] <step_1> extraction decision tags not properly closed"
    FAILED=$((FAILED + 1))
fi

if grep -q "<step_2>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</step_2>" "$SKILL_DIR/SKILL.md" && \
   grep -q "<ticket_scope>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</ticket_scope>" "$SKILL_DIR/SKILL.md" && \
   grep -q "<outside_ticket_scope>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</outside_ticket_scope>" "$SKILL_DIR/SKILL.md"; then
    info "  [PASS] <step_2> problem decision tags properly closed"
    PASSED=$((PASSED + 1))
else
    error "  [FAIL] <step_2> problem decision tags not properly closed"
    FAILED=$((FAILED + 1))
fi

if grep -q "<problem_classification>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</problem_classification>" "$SKILL_DIR/SKILL.md"; then
    info "  [PASS] <problem_classification> tag properly closed"
    PASSED=$((PASSED + 1))
else
    error "  [FAIL] <problem_classification> tag not properly closed"
    FAILED=$((FAILED + 1))
fi
echo ""

info "=== Test Summary ==="
info "PASSED: $PASSED"
info "FAILED: $FAILED"

if [ $FAILED -eq 0 ]; then
    info "All tests PASSED!"
    exit "$EXIT_OK"
else
    die "Some tests FAILED!"
fi
