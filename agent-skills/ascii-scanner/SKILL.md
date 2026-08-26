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

To maximize efficiency, **avoid scanning the entire repository**; target only specific files or staged changes.

```bash
# Repo subrepos (always git; subrepos under repo/ do not use jj):
git -C "repo/<repo-name>" diff --diff-filter=ACM --name-only HEAD \
  | grep -Ev '^(vendor/|generated/|dist/|zz_generated\.)' \
  | xargs -r -I {} bash agent-skills/ascii-scanner/ascii_scanner.sh --execute "repo/<repo-name>/{}"

# Workspace-root files (jj-first):
if test -d .jj && command -v jj >/dev/null 2>&1; then
  jj diff --summary | grep -v '^D ' | cut -d' ' -f2-
else
  git diff --diff-filter=ACM --name-only HEAD
fi | xargs -r -I {} bash agent-skills/ascii-scanner/ascii_scanner.sh --execute "{}"

# Non-repo paths (scan specific files directly, no VCS diff needed):
bash agent-skills/ascii-scanner/ascii_scanner.sh --execute <file_path_1> <file_path_2>
```

## Expected Outcomes

- **Success (Exit 0):** Confirms all files are ASCII compliant.
- **Failure (Exit 1):** Returns a list of violations with file paths, line numbers, and the offending content.
