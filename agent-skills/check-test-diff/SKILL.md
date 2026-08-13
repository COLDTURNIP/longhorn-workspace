---
name: check-test-diff
description: >
  Use before merging or after large/automated changes to verify no *_test.go files were
  accidentally deleted or had more than 100 lines removed in the current diff.
compatibility: opencode
metadata:
  version: "0.2"
  impact: High
  tags: ["tests", "diff", "guard", "qa"]
---

# Skill: check-test-diff

## Description

This skill enforces QA safety by guarding against accidental or excessive changes to Go test files (`*_test.go`) in git diffs. It fails if any test file is deleted, or if any test file has more than 100 lines deleted in a single diff.

## When to Use

- As a pre-merge or CI guard to prevent accidental removal or mass modification of test coverage.
- When reviewing large or automated changes that may unintentionally impact test files.

## Usage

Run the shell script in this directory to check the current diff:

```
bash agent-skills/check-test-diff/check_test_diff.sh
```

To check a specific repository (optional):

```
bash agent-skills/check-test-diff/check_test_diff.sh --repo repo/<repo-name>
```

## Expected Outcomes

- **Exit code 0**: No forbidden test file deletions or excessive line deletions detected. Prints a summary of test file changes.
- **Exit code 1**: One or more `*_test.go` files deleted, or a test file has >100 lines deleted. Prints details of violations and fails the check.

## Notes

- This skill does not run or select test suites; it only guards against risky test file diffs.
- ASCII-only output and file compliance enforced.
