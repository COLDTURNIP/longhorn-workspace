---
Version: 2.1
Last Updated: 2026-01-18
Maintenance: Longhorn Development Team
Purpose: Multi-Repo Workspace Development Guidance for AI Coding Agents
Changelog: Integrated AGENTS.md and AGENTS.new.md with enhanced structure and verification procedures
---

# Longhorn Workspace Agent Summary

## Context Loading (Mandatory)
- Engineering/build tasks (code changes, builds/tests, dependency updates, any `repo/` path) -> read `repo/AGENTS.md` first; it defines build contracts and dependency impacts.
- Issue/ticket/support-bundle work (`ticket/` paths, failure analysis) -> read `ticket/AGENTS.md` first; it defines evidence collection and folder layout.
- Always reference files using workspace-relative paths (e.g., `repo/longhorn-manager/controller/...`), never absolute paths.

## Workspace Scope
- Applies to the entire Longhorn workspace (`.opencode/` at root).
- This summary is authoritative; detailed procedures live in `AGENTS.d/*.md`. If a subdoc conflicts, follow this summary.
- Never commit AGENTS.md files (root or repo-level). Before PR, ensure `git status` and `git diff --cached` show no AGENTS entries.

## Non-Negotiable Policies
- **ASCII-only** for all files/logs/commits. Quick scan: `git diff --name-only | xargs -I {} sh -c 'grep -P -n "[^\x00-\x7F]" "{}" && exit 1 || exit 0'`. Details -> `AGENTS.d/ascii-policy.md`.
- **Force push** forbidden by default; if absolutely required, only `git push --force-with-lease origin <branch>` with explicit user approval. See `AGENTS.d/force-push-policy.md`.
- **Signoff** (`git commit -s`) disabled by default; follow repo-level instructions (e.g., repo/AGENTS Section 5) when mandated.
- **Minimal scope**: change only what the request requires; upstream-derived repos (csi-*, livenessprobe) allow only targeted fixes. See `AGENTS.d/build-contract.md`.
- **Repo setup**: use `repo-init` when `repo/` is empty and refresh `context/indices/*` with `interaction-mapper` after cloning.

## Toolchain Quick Reference
- Native Longhorn repos (manager, engine, instance-manager, share-manager, etc.): run `make build`, `make test`, `make validate` (Dapper). Do **not** run `go build`/`go test` directly.
- longhorn-ui: `npm install && npm run build`; tests via `npm test`.
- longhorn-tests: `pytest` or the repo's runner.
- Non-allowlisted/CSI repos: inspect the repo's Makefile/release tools before running commands; do not assume Dapper support.
- Packaging/Helm work: follow `AGENTS.d/crd-helm.md` for CRD sync + Helm manifest regeneration.

## Git & PR Workflow (Summary)
1. Create feature branch from upstream default: `git switch -c storyid-brief upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')`.
2. Develop locally; push only to `origin/<feature>` (never upstream).
3. Rebase onto upstream default before pushing; resolve conflicts upstream-first unless intentionally overriding.
4. Squash/signoff only if repo documentation requires it. Default: no automated signoff.
5. User handles PR creation/merge. Detailed steps, branch naming, and verification commands -> `AGENTS.d/pr-workflow.md`.

## QA Summary
- Before declaring work done: run ASCII scan, ensure AGENTS.md is not staged, remove local go.mod replaces (`go mod tidy`), run the appropriate build/test/validate commands, and document dependency impacts when touching shared layers.
- Full checklist and troubleshooting -> `AGENTS.d/qa-checklist.md`.

## Subdoc Index
- PR Workflow -> `AGENTS.d/pr-workflow.md`
- QA Checklist -> `AGENTS.d/qa-checklist.md`
- Impact & go.mod policy -> `AGENTS.d/impact-analysis.md`
- CRD/Helm sync -> `AGENTS.d/crd-helm.md`
- Context Hygiene -> `AGENTS.d/context-hygiene.md`
- Build Contracts & repo types -> `AGENTS.d/build-contract.md`
- ASCII Policy -> `AGENTS.d/ascii-policy.md`
- Force Push/Git Safety -> `AGENTS.d/force-push-policy.md`

## Quick Commands
```bash
# Rebase onto upstream default before push

# Build/test native repo inside Dapper
make build validate test

# Build container image inside Dapper
make package

# UI build/test
npm install && npm run build && npm test

# Verify go.mod clean before PR

# Ensure AGENTS.md not tracked
```
