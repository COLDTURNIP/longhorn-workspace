---
name: go-import-check
description: Use after adding or modifying Go files under repo/* and before declaring Go implementation complete. Checks changed non-vendor files against the workspace Longhorn import convention.
compatibility: Requires Python 3, Git, and repo/longhorn-manager/.github/scripts/check_go_imports.py.
metadata:
  version: "1.0"
---

# Go Import Check

Run the workspace import convention gate after modifying Go source in any `repo/*` repository.

## Usage

From the workspace root:

```sh
python3 agent-skills/go-import-check/scripts/check.py
```

To check selected repositories:

```sh
python3 agent-skills/go-import-check/scripts/check.py repo/longhorn-instance-manager repo/longhorn-manager
```

The script checks added, modified, and untracked Go files. It excludes vendor, generated, and distribution paths. A checker failure blocks completion.

`repo/longhorn-manager/.github/scripts/check_go_imports.py` is the executable source of truth. Do not infer ordering from examples when they disagree with the checker.
