---
name: repo-init
description: Clones every upstream Longhorn repository from repo/repo-list and prepares tracking upstream branches without configuring personal forks.
compatibility: opencode
metadata:
  version: "1.0"
  tags: ["initialization", "workspace", "repos"]
---

# Skill: repo-init

## Purpose

This skill initializes all Longhorn-related repositories found in `repo/repo-list`, cloning only the official upstream repo for each and creating a local branch that tracks the default upstream branch. Repository initialization runs in parallel, reports a per-repo result summary, and emits a JSON summary at the end.
No personal fork (origin remote) is configured.

## Usage

Dry-run (default):

```bash
bash .opencode/skills/repo-init/repo_init.sh
```

Execute clone/init actions (requires confirmation for branch cleanup):

```bash
bash .opencode/skills/repo-init/repo_init.sh --execute --force
```

## Process Details

1. Reads `repo/repo-list` and processes each repository name (skipping empty lines or comments).
2. Initializes repositories in parallel and writes a per-repo status file.
3. Clones each official upstream repository into the `repo/` directory.
4. Detects the upstream default branch (via `git remote show`, `git remote set-head --auto`, or `git ls-remote --symref`) and records it so `git symbolic-ref refs/remotes/upstream/HEAD` resolves to the correct branch (e.g., `refs/remotes/upstream/main`).
5. Creates a local branch named `upstream` tracking the detected upstream default branch.
6. Deletes all other local branches (requires `--force`).
7. Emits a consolidated summary for success, skipped, dry-run, and failed repos, plus a JSON structure for downstream processing.
8. Does not set up any personal fork or `origin` remote.

## Notes

- This skill interacts with all repos listed in `repo/repo-list` in a single batch.
- Ensure the `repo` directory exists and is writeable.
- The workspace repository does not need an `upstream` remote configured; the script will continue with a warning if it is missing.
- Recommended as the first step when initializing a new workspace.
