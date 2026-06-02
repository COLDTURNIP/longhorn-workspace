# PR Workflow (Detailed)

## Version Control: jj-first

If `.jj/` is present in the workspace root, prefer jj commands. The git commands in
this file are the fallback for git-only environments. See the `jj-vcs` skill for a
full jj command reference including the PR workflow equivalents.

| Step | git (fallback) | jj (preferred) |
|------|---------------|----------------|
| Check clean | `git status --porcelain` | `jj diff --summary` (empty = clean) |
| Fetch upstream | `git fetch upstream` | `jj git fetch` |
| New branch | `git switch -c <id> upstream/<branch>` | `jj new <remote>/<branch>` then `jj bookmark create <id> -r @` |
| Rebase | `git rebase upstream/<branch>` | `jj rebase -d <remote>/<branch>` |
| Squash | `git rebase -i upstream/<branch>` | `jj squash` |
| Signoff | `git commit -s -m "..."` | `jj describe -m "...\n\nSigned-off-by: Name <email>"` |
| Push | `git push -u origin HEAD` | `jj git push --bookmark <name>` |
| Force push | `git push --force-with-lease origin HEAD` | `jj git push --force-bookmark <name>` |

Note: avoid `jj workspace add` inside `repo/*` subrepos by default. The
workspace workflow is branch/bookmark oriented, and some subrepos still have
path-sensitive container build flows. Use `jj new` + `jj bookmark` instead.

## Worktree Guidance for `repo/*` Subrepos

**Do NOT use `git worktree` inside any `repo/*` subrepo by default.**

Most Longhorn subrepo workflows are written for normal working branches, and some legacy container build paths are still path-sensitive. Worktrees are allowed only when the repo-specific guide explicitly permits them and the local Makefile has been checked for path-sensitive build assumptions.

**Use working branches instead:**
```sh
# Create and switch to a feature branch (inside the subrepo directory)
git switch -c <storyid>-brief upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')
```

This restriction does NOT apply to the workspace root or repos whose local guidance explicitly allows worktrees.

## Preparation
- Clean working tree: `git status --porcelain && git diff --exit-code && git diff --cached --exit-code`
- Fetch upstream: `git fetch upstream`
- Detect upstream default: `git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@'`
- Fail fast if `refs/remotes/upstream/HEAD` missing (fix remote before proceeding).

## Rebase and Safety
- Optional safety branch: `git branch backup/$(date +%Y%m%d%H%M%S)`
- Rebase: `git rebase upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')`
- Conflict policy: prefer upstream unless intentional deviation; use `git rebase --continue` after resolves.

## Squash and Signoff
- Squash to single commit (e.g., `git rebase -i upstream/<default>`)
- Signoff (repo-scoped exception when required): `git commit -s -m "<storyid>-brief: summary"`

## Push Policy
- Push only to origin/feature: `git push -u origin HEAD`
- Default forbid force; if updating PR after squash, use `git push --force-with-lease origin HEAD` with explicit approval.

## Verification Commands (non-destructive)
```sh
git status --porcelain && git diff --exit-code && git diff --cached --exit-code
git fetch upstream
git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@'
git rebase --stat --dry-run upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')
git commit -s --allow-empty -m "verify-signoff" && git reset HEAD~
git push --dry-run origin HEAD
```
Remove the temporary empty commit after verification.

## Force/Signoff Rules
- Force push is forbidden by default; only `--force-with-lease` when explicitly needed for PR update.
- Signoff automation is prohibited unless the repo-specific guide (e.g., repo/AGENTS.md) mandates `-s`.

## Checklist (copyable)
- [ ] Clean working tree
- [ ] Fetched upstream
- [ ] Upstream default detected via symbolic-ref
- [ ] Rebased on upstream default, conflicts resolved
- [ ] Single commit with required signoff (if repo demands it)
- [ ] Pushed to origin (never upstream)
- [ ] If force needed, used `--force-with-lease` with approval
