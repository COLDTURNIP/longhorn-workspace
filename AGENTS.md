# Longhorn Workspace Router

## Scope and precedence

- This file applies to the entire workspace. System and user instructions take precedence; a more specific `AGENTS.md` governs its subtree; this file governs otherwise.
- For any engineering, build, dependency, or other `repo/*` work, read `repo/AGENTS.md` before acting.
- For `ticket/*`, support-bundle, or failure-analysis work, read `ticket/AGENTS.md` before acting.
- Before acting on a plan or delegation, orchestrators, planners, and plan reviewers must read `AGENTS.d/plan-and-delegation.md`.
- Refer to every file with a workspace-relative path, such as `repo/longhorn-manager/controller/...`.

## Hard guardrails

- Keep every file, log, and commit message ASCII-only. Use `skill://ascii-scanner` before committing `repo/*` changes, after generating `ticket/*` analysis reports, and after multi-file refactors.
- YAML files changed: before completion, run `bash scripts/yaml-duplicate-key-check.sh <yaml-file> [yaml-file...]` on every changed YAML file (`--dry-run` only previews checks).
- Do not edit an existing `*_test.go` test case or file unless the user explicitly requests that specific test case or file.
- Never force-push without explicit user approval for the exact branch; when approved, use only `--force-with-lease`.
- The user creates and merges pull requests. Agents must not create or merge them.
- For GitHub comments, reviews, and review threads, provide draft text for the user to post. Never post, reply, edit, delete, resolve, or otherwise mutate them.
- Treat published commits as immutable. Create child changes from clean published parents; never amend, squash, rebase, abandon, or otherwise rewrite them without explicit user approval for that exact history rewrite.
- Treat `agent-skills/` and `scripts/` as authoritative project sources. Treat `.claude/skills/` and `.agents/skills/` as installed or generated caches; never edit them as the source of a policy or skill change.
- In public documentation, issues, pull request text, and design proposals, name repositories as `longhorn/<repository>` and use public GitHub links. Never expose workspace-local paths such as `repo/longhorn-manager/...` in externally consumed content.
- Local commits may include edits to the workspace-root `AGENTS.md`, repo-level or nested `AGENTS.md` files, and `AGENTS.d/*` policy files. Never push any such policy change.

- If `skill://<name>` is unavailable and `agent-skills/<name>/SKILL.md` exists, read that project-owned source entrypoint for the current task and tell the user to install it with `npx skills add ./agent-skills --skill <name>`. Do not apply this fallback to external skills absent from `agent-skills/`.

## Conditional skills

- Go files under `repo/*` modified: read `skill://go-import-check` and run its gate before completion.
- Large or automated diff, or pre-merge review: use `skill://check-test-diff`.
- `.jj/` exists, the user mentions Jujutsu, or local version-control work is needed: use `skill://jj-vcs`.
- Drafting, reviewing, amending, or creating a Longhorn commit message: use `skill://commit-message`.
- Manager API types changed, CRDs are out of sync, or release manifests need regeneration: use `skill://sync-crd-helm`.
- Adding, debugging, or selecting Longhorn build, test, validation, packaging, Buildx, or Dapper flows: use `skill://longhorn-build-system`.
- After workspace initialization, before development, when toolchain/remotes may be misconfigured, or before a multi-step implementation plan: use `skill://verify-setup`.
