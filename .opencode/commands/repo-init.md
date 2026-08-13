---
description: Initialize or sync all Longhorn repositories from repo/repo-list.json (execute by default; use --dry-run/--json to customize)
---

Run the repo initialization workflow. By default this performs real clone/init actions; append `--dry-run` to preview and `--json` for JSON-only output.
The source of truth is `repo/repo-list.json`, where each key is a target path under `repo/` and each value defines a mandatory `upstream` full git URL and optional `origin` full git URL.

```bash
bash scripts/repo-init.sh $ARGUMENTS
```

Options:

- --dry-run      # Preview actions without making changes
- --json         # Output machine-readable JSON

`repo-init` always force-aligns local jj bookmark `main` to `trunk()` as part of reconciliation.

JSON results use a single schema with per-repo diagnostics:

- `trunk_branch`        # detected upstream trunk branch (`main` or `master`)
- `origin_tracking`     # origin tracking state (`tracked`, `missing-origin-<branch>`, `not-configured`, etc.)
- `main_bookmark_state` # local main bookmark state (`preserved`, `created-at-trunk`, `reset-to-trunk`)
