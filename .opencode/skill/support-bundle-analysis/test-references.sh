#!/bin/bash
# Reference Validation Test for Support Bundle Analysis Skill
# Tests all cross-module references and anchors

set -e

SKILL_DIR=".opencode/skill/support-bundle-analysis"
PASSED=0
FAILED=0

echo "=== Reference Validation Test ==="
echo ""

# Test 1: Check all file references exist
echo "Test 1: File References"
for file in SKILL.md diagnostic-flows.md patterns-library.md; do
    if [ -f "$SKILL_DIR/$file" ]; then
        echo "  [PASS] $file exists"
        ((PASSED++))
    else
        echo "  [FAIL] $file does NOT exist"
        ((FAILED++))
    fi
done
echo ""

# Test 2: Check anchor points in diagnostic-flows.md
echo "Test 2: diagnostic-flows.md Anchors"
ANCHORS=("pod-diagnosis" "node-diagnosis" "storage-diagnosis" "network-diagnosis" "pod-quick-scan" "node-quick-scan" "storage-quick-scan" "network-quick-scan")
for anchor in "${ANCHORS[@]}"; do
    if grep -q "{#$anchor}" "$SKILL_DIR/diagnostic-flows.md"; then
        echo "  [PASS] Anchor #$anchor exists"
        ((PASSED++))
    else
        echo "  [FAIL] Anchor #$anchor NOT found"
        ((FAILED++))
    fi
done
echo ""

# Test 3: Check anchor points in patterns-library.md
echo "Test 3: patterns-library.md Anchors"
ANCHORS=("timeline-reconstruction" "5-whys-method" "evidence-based-analysis" "patterns-library" "examples" "example-1" "example-2" "quick-reference")
for anchor in "${ANCHORS[@]}"; do
    if grep -q "{#$anchor}" "$SKILL_DIR/patterns-library.md"; then
        echo "  [PASS] Anchor #$anchor exists"
        ((PASSED++))
    else
        echo "  [FAIL] Anchor #$anchor NOT found"
        ((FAILED++))
    fi
done
echo ""

# Test 4: Check all references in SKILL.md
echo "Test 4: References in SKILL.md"
if grep -q "@diagnostic-flows.md" "$SKILL_DIR/SKILL.md"; then
    echo "  [PASS] References to @diagnostic-flows.md found"
    ((PASSED++))
else
    echo "  [FAIL] No references to @diagnostic-flows.md"
    ((FAILED++))
fi

if grep -q "@patterns-library.md" "$SKILL_DIR/SKILL.md"; then
    echo "  [PASS] References to @patterns-library.md found"
    ((PASSED++))
else
    echo "  [FAIL] No references to @patterns-library.md"
    ((FAILED++))
fi
echo ""

# Test 5: Check XML tags are well-formed
echo "Test 5: XML Tags Validation"
if grep -q "<mandatory_requirements>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</mandatory_requirements>" "$SKILL_DIR/SKILL.md"; then
    echo "  [PASS] <mandatory_requirements> tag properly closed"
    ((PASSED++))
else
    echo "  [FAIL] <mandatory_requirements> tag not properly closed"
    ((FAILED++))
fi

if grep -q "<confirmation_1>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</confirmation_1>" "$SKILL_DIR/SKILL.md"; then
    echo "  [PASS] <confirmation_1> tag properly closed"
    ((PASSED++))
else
    echo "  [FAIL] <confirmation_1> tag not properly closed"
    ((FAILED++))
fi

if grep -q "<confirmation_2>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</confirmation_2>" "$SKILL_DIR/SKILL.md"; then
    echo "  [PASS] <confirmation_2> tag properly closed"
    ((PASSED++))
else
    echo "  [FAIL] <confirmation_2> tag not properly closed"
    ((FAILED++))
fi

if grep -q "<problem_classification>" "$SKILL_DIR/SKILL.md" && \
   grep -q "</problem_classification>" "$SKILL_DIR/SKILL.md"; then
    echo "  [PASS] <problem_classification> tag properly closed"
    ((PASSED++))
else
    echo "  [FAIL] <problem_classification> tag not properly closed"
    ((FAILED++))
fi
echo ""

# Summary
echo "=== Test Summary ==="
echo "PASSED: $PASSED"
echo "FAILED: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "All tests PASSED!"
    exit 0
else
    echo "Some tests FAILED!"
    exit 1
fi
