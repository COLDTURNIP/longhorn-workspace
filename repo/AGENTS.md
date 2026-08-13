# Repository Engineering Override

This file applies to all work under `repo/` and adds only Longhorn repository-specific constraints to the workspace rules.

## Engineering constraints

- Treat each repository's local `Makefile` and related configuration as the authoritative build, test, validation, and packaging interface. Host `go build` or `go test` may aid diagnosis, but they are not final verification. Read `skill://longhorn-build-system` when selecting, adding, or debugging those workflows.
- Keep changes to upstream-derived CSI sidecars and `livenessprobe` narrowly targeted. Avoid unrelated refactoring, formatting sweeps, or convention changes.
- Before changing shared libraries, API types, dependency versions, or lower-layer components, analyze affected downstream repositories and required module/version updates. Until this guidance is relocated, read `AGENTS.d/impact-analysis.md` for the temporary impact map and checklist.
- For manager API type, CRD, generated manifest, or Helm synchronization work, read `skill://sync-crd-helm`.

## Workflow pointers

- After modifying Go files, read and run `skill://go-import-check` before completion.
- After large or automated diffs, and before merge review, use `skill://check-test-diff`.
- For every `repo/*` commit message or commit operation, use `skill://commit-message` and verify the required DCO signoff; never infer or fabricate signer identity.
- When `.jj/` exists, Jujutsu is requested, or local version-control work is needed, read `skill://jj-vcs`.
- Prefer normal working branches or bookmarks. Avoid worktrees where repository build paths, generated artifacts, or container bind mounts are path-sensitive.
