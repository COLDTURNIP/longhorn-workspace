---
description: Initialize workspace repositories and indices, then report repo location and current repos.
---

Initialize the workspace repositories and generate architectural indices. By default this performs real clone/init actions and indexing; append `--dry-run` to preview and `--json` for JSON-only output.

After execution, the agent must summarize:

1. Repository location is `repo/` (see `AGENTS.md` context loading and repo setup guidance).
2. Current repositories under `repo/`.
3. Each initialized repository uses `upstream` as the git remote name, and local branch `upstream` aligns with the upstream default branch (`main` or `master`) per repo-init behavior.
4. Repository definitions come from `repo/repo-list.json` (path key -> `upstream` required, `origin` optional).

```bash
bash .opencode/commands/init-workspace.sh $ARGUMENTS
```

Options:

- --dry-run   # Preview actions without making changes
- --json      # Output machine-readable JSON
