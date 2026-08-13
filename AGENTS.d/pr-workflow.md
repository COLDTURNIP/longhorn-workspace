# PR Workflow (Detailed)

## Authoritative Guidance

- If `.jj/` exists at the workspace root, use `skill://jj-vcs` for VCS
  commands and jj/Git equivalents. Git commands are fallback guidance for
  Git-only repositories.
- Use `skill://commit-message` for issue verification, message format, and
  DCO handling. Repository-specific guidance decides whether signoff is
  required.

## Longhorn PR Guardrails

1. Base the feature branch or bookmark on the upstream default branch. Fetch
   upstream before rebasing, and fail if its default branch cannot be
   identified.
2. Rebase onto the upstream default branch before the first push and after an
   upstream update. Resolve conflicts upstream-first unless the change
   intentionally overrides upstream behavior.
3. Use normal working branches or bookmarks inside `repo/*`. Do not create a
   Git worktree or jj workspace there unless the repository-specific guide
   explicitly permits it and its build flow is not path-sensitive.
4. Push feature branches or bookmarks only to the `origin` remote, never to
   `upstream`. Name the remote explicitly, including
   `jj git push --remote origin --bookmark <bookmark>`.
5. Rewritten Git history may be pushed only with explicit user approval and
   only as `git push --force-with-lease origin <branch>`. For jj, obtain the
   same approval before moving an existing remote bookmark; jj's push safety
   check is lease-like, and the command must still name `--remote origin`.
6. The user creates and merges the PR.

## Verification

Verification is read-only inspection:

- Inspect the complete local status, diff, commit graph, and commit message
  with the commands documented by `skill://jj-vcs`.
- Apply the message and signoff checks from `skill://commit-message`.
- Confirm the branch or bookmark is based on the intended upstream default
  branch and that the eventual push command names `origin`.
- Run the repository-specific build, test, validation, and ASCII checks.

A rebase is a workflow action, not a verification probe. Do not create a
temporary commit, reset history, or contact a remote with a dry-run push to
verify local state.
