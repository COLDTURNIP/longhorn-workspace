# Skill: repo-init

## Purpose

This skill initializes all Longhorn-related repositories found in `repo/repo-list`, cloning only the official upstream repo for each and creating a local branch that tracks the default upstream branch.
No personal fork (origin remote) is configured.

## Usage

```bash
bash .opencode/skill/repo-init/repo_init.sh
```

## Process Details

1. Reads `repo/repo-list` and processes each repository name (skipping empty lines or comments).
2. Clones each official upstream repository into the `repo/` directory.
3. Detects the default branch of the upstream repository.
4. Creates a local branch named `upstream` tracking the upstream default branch.
5. Deletes the local `master` branch if present (leaving only `upstream`).
6. Does not set up any personal fork or `origin` remote.

## Notes

- This skill interacts with all repos listed in `repo/repo-list` in a single batch.
- Ensure the `repo` directory exists and is writeable.
- Recommended as the first step when initializing a new workspace.
