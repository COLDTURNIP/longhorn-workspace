---
description: Initialize all Longhorn repositories from repo/repo-list (execute by default; use --dry-run/--json/--force to customize)
---

Run the repo initialization workflow. By default this performs real clone/init actions; append `--dry-run` to preview, `--json` for JSON-only output, and `--force` to allow branch cleanup.

```bash
bash .opencode/commands/repo-init.sh $ARGUMENTS
```
