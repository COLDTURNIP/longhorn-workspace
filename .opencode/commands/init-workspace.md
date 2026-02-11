---
description: Initialize the workspace repositories and indices (execute by default; use --dry-run/--json to customize)
---

Initialize the workspace repositories and generate architectural indices. By default this performs real clone/init actions and indexing; append `--dry-run` to preview and `--json` for JSON-only output.

```bash
bash .opencode/commands/init-workspace.sh $ARGUMENTS
```

Options:

- --dry-run   # Preview actions without making changes
- --json      # Output machine-readable JSON
