# Longhorn Workspace Router

## Scope and precedence

- This file applies to the entire workspace. Follow the actual harness hierarchy: higher-priority instructions govern lower-priority ones, and the user's task overrides ordinary skill guidance only within higher-priority constraints. A more specific `AGENTS.md` governs its subtree; this file governs otherwise.
- For any engineering, build, dependency, or other `repo/*` or `worktree/*` work, read `repo/AGENTS.md` before acting.
- For `ticket/*`, support-bundle, or failure-analysis work without a runnable reproduction, read `ticket/AGENTS.md` before acting; that work ends in analysis. Use `skill://diagnosing-bugs` only for a bug you can reproduce in `repo/*` or `worktree/*`.
- The hard guardrails below override every skill. Within them, skills decide process and artifact format, and `docs/agents/*.md` adapts the skills to this workspace.
- In local reports and handoffs, refer to files with workspace-relative paths, such as `repo/longhorn-manager/controller/...`.

## Bounded autonomy

Complete authorized work within the task's path and command allowlists, preserving safeguards. A delegation prompt states both allowlists for its worker; materially expanded scope returns to the parent for authorization. If blocked, cite the exact blocking rule and finish all reachable work; do not invent a skill approval.

## Hard guardrails

- Keep every file, log, commit message, and pull request title ASCII-only. Use `skill://ascii-scanner` before committing `repo/*` or `worktree/*` changes or finalizing a commit message or pull request title, after generating `ticket/*` analysis reports, and after multi-file refactors. Its checker also rejects invisible and BiDi characters (Trojan Source).
- YAML files changed: before completion, run `bash scripts/yaml-duplicate-key-check.sh <yaml-file> [yaml-file...]` on every changed YAML file (`--dry-run` only previews checks).
- Add tests as new `*_test.go` files or new test cases. Modify or delete an existing test case only when the user explicitly requests that specific test case.
- Never force-push without explicit user approval for the exact branch; when approved, use only `--force-with-lease`.
- The user creates and merges pull requests. Agents must not create or merge them.
- For GitHub comments, reviews, and review threads, provide draft text for the user to post. Never post, reply, edit, delete, resolve, or otherwise mutate them.
- Treat published commits as immutable. Create child changes from clean published parents; never amend, squash, rebase, abandon, or otherwise rewrite them without explicit user approval for that exact history rewrite.
- Local commits may include edits to the workspace-root `AGENTS.md` and repo-level or nested `AGENTS.md` files. Never push any such policy change.
- Treat `agent-skills/` and `scripts/` as authoritative project sources. Treat `.claude/skills/` and `.agents/skills/` as installed or generated caches; never edit them as the source of a policy or skill change.
- In public documentation, issues, pull request text, and design proposals, name repositories as `longhorn/<repository>` and use public GitHub links. Never expose workspace-local paths such as `repo/longhorn-manager/...` in externally consumed content.
- If `skill://<name>` is unavailable and `agent-skills/<name>/SKILL.md` exists, read that project-owned source entrypoint for the current task and report `npx skills add ./agent-skills --skill <name>`. For missing `jj-vcs`, use `~/dev/rfns/agent-skills/skills/jj-vcs/SKILL.md` when present and report `npx skills add ~/dev/rfns/agent-skills --skill jj-vcs --global --agent pi`. Do not substitute an unrelated skill when its required source is unavailable.

## Conditional skills

- Go files under `repo/*` or `worktree/*` modified: read `skill://go-import-check` and run its gate before completion.
- Actual VCS work in a repository using Jujutsu: read `skill://jj-vcs`.

## Agent skills

### Issue tracker

Hybrid: read upstream `longhorn/*` GitHub issues with `gh` (read-only); write specs, tickets, and triage state locally under `ticket/<org>-<id>-<desc>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five roles, recorded as `Status:` lines in local ticket files. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` plus `docs/adr/`, created lazily. See `docs/agents/domain.md`.
