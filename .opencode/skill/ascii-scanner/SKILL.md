---
name: ascii-scanner
description: Enforces workspace-wide ASCII-only (0x00-0x7F) compliance to ensure cross-platform compatibility and repository hygiene.
compatibility: opencode
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
Execute from the workspace root. To maximize efficiency, **avoid scanning the entire repository**; target only specific files or staged changes.

```bash
# Scan specific modified files (e.g., using git status/diff)
bash .opencode/skill/ascii-scanner/ascii_scanner.sh <file_path_1> <file_path_2>

# Recommended: Scan only staged files in a repo
git -C repo/longhorn-manager diff --cached --name-only | xargs -I {} bash .opencode/skill/ascii-scanner/ascii_scanner.sh repo/longhorn-manager/{}
```

## Expected Outcomes

- **Success (Exit 0):** Confirms all files are ASCII compliant.
- **Failure (Exit 1):** Returns a list of violations with file paths, line numbers, and the offending content.
