# PR Workflow (Detailed)

## Authoritative Guidance

- For actual VCS work in a repository using jj, use `skill://jj-vcs` for VCS
  commands and jj/Git equivalents. Git commands are fallback guidance for
  Git-only repositories.
- Use `skill://commit-message` for issue verification, message format, and
  DCO handling. Repository-specific guidance decides whether signoff is
  required.

## Longhorn PR Guardrails

1. Select and record the intended base before starting: use the upstream default branch for ordinary work, or an explicitly selected stacked parent branch or bookmark for stacked work. Fetch upstream before using its state, and fail if its default branch cannot be identified.
2. Rebase unpublished work when needed to complete the authorized task. Published work requires approval for the exact history rewrite before rebasing. Fetch the selected remote base when a rebase depends on its current state, and resolve conflicts upstream-first unless the change intentionally overrides upstream behavior.
3. Use normal working branches or bookmarks inside `repo/*`. Do not create a Git worktree or jj workspace there unless the repository-specific guide explicitly permits it and its build flow is not path-sensitive. Keep branch and bookmark history linear; do not create automatic merge commits.
4. Push feature branches or bookmarks only to the `origin` remote, never to `upstream`. Name the remote explicitly, including `jj git push --remote origin --bookmark <bookmark>`.
5. Rewriting published history requires explicit user approval for the exact branch or bookmark and rewrite. Approval must also cover the intended remote update before pushing rewritten history. For Git, use only `git push --force-with-lease origin <branch>`. For jj, retain its lease-like push safety checks and name `--remote origin --bookmark <bookmark>`. Ordinary fast-forward updates and local bookmark changes within the authorized task do not require rewrite approval.
6. The user creates and merges the PR.

## Verification

Verification is read-only inspection:

- Inspect the complete local status, diff, commit graph, and commit message
  with the commands documented by `skill://jj-vcs`.
- Apply the message and signoff checks from `skill://commit-message`.
- Confirm the branch or bookmark is based on the explicitly selected base,
  including any stacked parent, and that the eventual push command names
  `origin`.
- Run the repository-specific build, test, validation, and ASCII checks for the
  relevant changed state. Do not repeat a build check when neither the state
  nor the inputs changed, unless an unresolved issue requires it.

A rebase is a workflow action, not a verification probe. Do not create a
temporary commit, reset history, or contact a remote with a dry-run push to
verify local state.
