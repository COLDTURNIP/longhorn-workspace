# Worktree Set Router

This file applies to everything under `worktree/`. Each `worktree/<key>/`
is a worktree set: one jj workspace (a Git worktree) per member repository,
all on the branch `<key>`. Create, inspect, and remove sets with
`skill://worktree-set` and `scripts/worktree.sh`.

## Working in a member

- Treat `worktree/<key>/<repo>/` exactly like `repo/<repo>/`: read and
  follow `repo/AGENTS.md` and the repository's own `AGENTS.md` before acting.
- Run jj, git, and make with the member as the working directory (`cd` into
  it, or `-R` / `-C` with the member path). `worktree/` and `worktree/<key>/`
  belong to the workspace-root jj repository, so jj commands there act on
  the root repository, not the member.
- One writer per member directory. Give each parallel agent its own set or
  member, never a member or canonical checkout (`repo/<repo>`) that another
  writer holds.
- Commit with jj, then move the branch to the new work with
  `bash scripts/worktree.sh bookmark <key>` (it runs
  `jj bookmark advance <key> --to @-` per member). Push only that branch:
  `jj git push --remote origin --bookmark <key>`.
- Pass the member path to `skill://go-import-check`, for example
  `python3 agent-skills/go-import-check/scripts/check.py worktree/<key>/<repo>`.
- The sync-crd-helm and interaction-mapper skill scripts always read or
  write `repo/longhorn-manager`, `repo/longhorn`, and `repo/types`. From a
  worktree set they act on the canonical checkouts, not the member.

## Finishing

Check `bash scripts/worktree.sh status <key> --remote` before removing a set,
then run `bash scripts/worktree.sh remove <key>`. Retire members only through
that script. Files it reports as leftovers belong to no member; show them to
the user before deleting them by hand.
