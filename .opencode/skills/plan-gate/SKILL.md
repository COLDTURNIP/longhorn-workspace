---
name: plan-gate
description: Lints Longhorn markdown execution plans for required step contract fields. Minimal contract; does not enforce pantoh-only close gates.
compatibility: opencode
---

# Skill: plan-gate

## Purpose

Validate Longhorn planning documents before execution. This gate enforces the presence of required step contract fields. It does not enforce pantoh-specific close gate or approval policies.

## Usage

```bash
bash .opencode/skills/plan-gate/plan_gate.sh [options] [plan_markdown_path]
```

- If no plan_markdown_path is provided, defaults to `.sisyphus/plans/atlas-governance-p0-p1.md`.

## Options

- `--execute`: Perform check (default dry-run semantics)
- `--dry-run`: Dry-run (default)
- `--json-log`: Emit JSON log lines
- `-h, --help`: Show help

## Contract Checks

The following fields/headings must be present in the plan:

- `Plan Step Contract`
- `Action:`
- `Target:`
- `Verify Command:`
- `Done Criteria:`
- `Pantoh Reference:`
- `Writing purpose:`
- `Global Hard Rules`
- `Forbidden references`

No pantoh-specific close gate or approval gate checks are enforced in this Longhorn skill.

## Hotfix Retry Prompt Gate

If the plan contains `Hotfix Retry Prompt`, each block must contain exactly one line each:

- `Target file: <path>`
- `Change objective: <one sentence>`
- `Verify: <single command>`

The `Verify` line must be a single command (no `&&`, `||`, `;`, or pipes).

## Exit Codes

- `0`: pass
- `2`: argument error
- `3`: gate failure
