# Repository Engineering Override

This file applies to all work under `repo/` and to every worktree set member under `worktree/<key>/`, and adds only Longhorn repository-specific constraints to the workspace rules.

## Engineering constraints

- Treat each repository's local `Makefile` and related configuration as the authoritative build, test, validation, and packaging interface. Host `go build` or `go test` may aid diagnosis, but they are not final verification.
- Keep changes to upstream-derived CSI sidecars and `livenessprobe` narrowly targeted. Avoid unrelated refactoring, formatting sweeps, or convention changes.
- Before changing shared libraries, API types, dependency versions, or lower-layer components, analyze affected downstream repositories and required module/version updates.

## Repository workflow

- For every `repo/*` or `worktree/*` commit message or commit operation, verify the required DCO signoff; never infer or fabricate signer identity.
- Create Git worktrees and jj workspaces only as worktree set members under `worktree/<key>/` through `skill://worktree-set`; keep `repo/*` free of them. Work in `repo/<name>` when `bash scripts/worktree.sh repos` reports the repository as unsupported (on a new branch or bookmark named after the key), or when the work is already in progress there.
