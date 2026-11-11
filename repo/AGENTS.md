# Repository Engineering Override

This file applies to all work under `repo/` and to every worktree set member under `worktree/<key>/`, and adds only Longhorn repository-specific constraints to the workspace rules.

## Engineering constraints

- Treat each repository's local `Makefile` and related configuration as the authoritative build, test, validation, and packaging interface. Host `go build` or `go test` may aid diagnosis, but they are not final verification.
- Keep changes to upstream-derived CSI sidecars and `livenessprobe` narrowly targeted. Avoid unrelated refactoring, formatting sweeps, or convention changes.
- Before changing shared libraries, API types, dependency versions, or lower-layer components, analyze affected downstream repositories and required module/version updates.

## Repository workflow

- For every `repo/*` or `worktree/*` commit message or commit operation, verify the required DCO signoff; never infer or fabricate signer identity.
- Create Git worktrees and jj workspaces only as worktree set members under `worktree/<key>/` through `skill://worktree-set`; keep `repo/*` free of them. Work in `repo/<name>` when `bash scripts/worktree.sh repos` reports the repository as unsupported (on a new branch or bookmark named after the key), or when the work is already in progress there. Run one ticket at a time in a `repo/<name>` checkout.
- Before starting, select and record the base: the upstream default branch, or an explicitly chosen stacked parent. Fetch upstream before relying on its state.
- Keep history linear, without merge commits. Before the first push, fold the branch into a single commit unless the user says otherwise; after it, fixes are child commits.
- Push a feature branch or bookmark only to `origin`, naming the remote: `jj git push --remote origin --bookmark <key>`.
- Verify local state by read-only inspection, never with a temporary commit, a history reset, or a dry-run push.
- Implement one ticket at a time with `implement`. `implement-spec` is unsupported until every repository builds from a worktree (longhorn/longhorn#14427).

## Review and pull request text

- Before `skill://code-review`, commit the work so the jj working copy `@` is empty: the skill diffs against `HEAD`, which is `@-` under jj. Its fixed point defaults to the recorded base, and the repository's own `AGENTS.md` is a standards source.
- Reviewing an upstream pull request: use the review workflow and output format in that repository's `AGENTS.md`.
- Pull request body: start from the repository's PR template and write the draft to `ticket/<folder>/drafts/`. From `skill://pr`, take only the before/after evidence, placed in the template's testing section.
