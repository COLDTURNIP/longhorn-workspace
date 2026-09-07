# Repository Engineering Override

This file applies to all work under `repo/` and adds only Longhorn repository-specific constraints to the workspace rules.

## Engineering constraints

- Treat each repository's local `Makefile` and related configuration as the authoritative build, test, validation, and packaging interface. Host `go build` or `go test` may aid diagnosis, but they are not final verification.
- Keep changes to upstream-derived CSI sidecars and `livenessprobe` narrowly targeted. Avoid unrelated refactoring, formatting sweeps, or convention changes.
- Before changing shared libraries, API types, dependency versions, or lower-layer components, analyze affected downstream repositories and required module/version updates.

## Repository workflow

- For every `repo/*` commit message or commit operation, verify the required DCO signoff; never infer or fabricate signer identity.
- Prefer normal working branches or bookmarks. Avoid worktrees where repository build paths, generated artifacts, or container bind mounts are path-sensitive.
