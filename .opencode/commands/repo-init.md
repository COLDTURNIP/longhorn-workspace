---
description: Initialize or sync all Longhorn repositories from repo/repo-list.json (execute by default; use --dry-run/--json to customize)
---

Run the repo initialization workflow. By default this performs real clone/init actions; append `--dry-run` to preview and `--json` for JSON-only output.
The source of truth is `repo/repo-list.json`, where each key is a target path under `repo/` and each value defines a mandatory `upstream` full git URL and optional `origin` full git URL.

```bash
bash .opencode/commands/repo-init.sh $ARGUMENTS
```
