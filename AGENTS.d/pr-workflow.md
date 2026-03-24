# PR Workflow (Detailed)

## Worktree Restriction for `repo/*` Subrepos

**Do NOT use `git worktree` inside any `repo/*` subrepo.**

Rancher Dapper mounts the repository root into an isolated build container using the on-disk path. A worktree places the working tree at a different path, which breaks Dapper's bind-mount and Make targets (`make build`, `make test`, `make validate`) will fail or operate on the wrong tree.

**Use working branches instead:**
```sh
# Create and switch to a feature branch (inside the subrepo directory)
git switch -c <storyid>-brief upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')
```

This restriction applies to all Dapper-based repos (longhorn-manager, longhorn-engine, instance-manager, share-manager, etc.). It does NOT apply to the workspace root or non-Dapper repos where worktrees are safe.

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
