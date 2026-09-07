---
name: ascii-scanner
description: >
  Use before committing changes in repo/, after generating analysis reports in ticket/,
  or after any multi-file refactoring task, to catch non-ASCII characters, emojis, or
  smart quotes that violate the ASCII-only policy.
metadata:
  version: "1.0"
  impact: High (Policy Enforcement)
  tags: ["compliance", "validation", "lint", "ascii"]
---

# Skill: ascii-scanner

## Description
An automated validation tool to enforce the workspace-wide ASCII-only policy (0x00-0x7F). It identifies non-ASCII characters, emojis, and smart quotes that violate the "Global Constitution."

## When to Use
- **Pre-Commit**: Before staging any changes in `repo/`.
- **After Reporting**: After generating `ticket/*/analysis_report.md`.
- **CI/CD Simulation**: Whenever an Agent completes a multi-file refactoring task.

## Usage
Execute from the workspace root. Uses defensive prelude: default dry-run; use `--execute` to run. Supports `--json-log`, `--no-color`, `--force` (unused), `--dry-run`.

Select the changed files using the active harness tools and the target
repository's VCS workflow. Avoid scanning the entire repository. The scanner
accepts one file or directory per invocation; run it once for each selected
file so additional paths are not silently skipped.

```bash
bash agent-skills/ascii-scanner/ascii_scanner.sh --execute <file_path>
```

## Expected Outcomes

- **Exit 0:** The selected target passed, or a dry-run preview was shown. Only `--execute` performs the scan.
- **Nonzero exit:** Read the diagnostic and resolve the reported violation or argument/environment error.
