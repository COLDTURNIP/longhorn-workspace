---
name: worktree-set
description: Use when starting a ticket or POC that needs its own checkout of repo/* repositories, running tickets in parallel, or inspecting, syncing, or removing a worktree set under worktree/.
---

# Worktree sets

A worktree set is `worktree/<key>/`: one jj workspace (a Git worktree) per
member repository, all on the branch `<key>`, plus a `worktree.json`
manifest. `scripts/worktree.sh` is the implementation and
`bash scripts/worktree.sh --help` is the source of truth for its flags.
`worktree/AGENTS.md` holds the rules for working inside a member.
[DESIGN.md](DESIGN.md) records the rationale and the full behavior; read it
only when changing this workflow.

Use this workflow instead of harness worktree features (for example Claude
Code `--worktree`), which nest worktrees inside `repo/*`.

## 1. Choose the key

- Ticket work: `bash scripts/worktree.sh key --issue <n>` proposes
  `<n>-<slug>` from the longhorn/longhorn issue title. Add `--slug <s>` for a
  shorter slug.
- Work without an issue (personal POC, spike): a slug that starts with a
  letter, for example `poc-nvme-tcp-frontend`.
- Backport: append `-v<major>.<minor>.x`; the base becomes that release
  branch.

Done when `key` prints the key you will use. The key is also the branch name
in every member, so pick it before creating anything.

## 2. Check which repositories can join

Run `bash scripts/worktree.sh repos`. Repositories marked `unsupported` still
break their Makefile builds from a worktree (longhorn/longhorn#14427) and
cannot join a set. Do their part of the ticket in `repo/<name>` on a branch
named `<key>`, with the normal PR workflow.

When `repos` reports a fix commit on trunk for an unsupported repository,
tell the user the table in `scripts/worktree.sh` may be outdated; the user
decides whether to change it.

## 3. Create the set

```bash
bash scripts/worktree.sh create <key> <repo>... [-n]
bash scripts/worktree.sh create --issue <n> [--slug <s>] <repo>...
```

- `--adopt` continues an existing `<key>` branch (local or on `origin`);
  `create` refuses an existing branch without it.
- `--base <revset>` or `--base <repo>=<revset>` overrides the base.
- `add <key> <repo>...` adds members later; `drop <key> <repo>...` removes
  some.

`create` fetches `upstream` and, like any jj command, snapshots each
canonical checkout. Done when it exits 0 and `status <key>` lists every
member with `bookmark=ok`.

## 4. Work in the members

Follow `worktree/AGENTS.md`. After each `jj commit`, run
`bash scripts/worktree.sh bookmark <key>` so the branch points at the new
work. Push a member with `jj git push --remote origin --bookmark <key>` once
the PR workflow's checks pass.

## 5. Inspect

`bash scripts/worktree.sh status [<key>] [--remote] [--json]` reports per
member:

| Field | Meaning | Action |
|---|---|---|
| `uncommitted` | the working-copy commit has changes | commit them |
| `lag` | commits the branch does not point to yet | `worktree.sh bookmark <key>` |
| `commits` | commits on the branch beyond its base | none |
| `unpublished` | non-empty commits not on `origin/<key>` | push, or decide with the user |
| `at_base` | the branch still points at the commit it started from | none |
| `merged` | `upstream` (an upstream branch contains the commits), `pr` (merged PR, needs `--remote`), `no` | remove the set when the ticket is done |
| `STALE` | another workspace rewrote this one's commit | `jj workspace update-stale` inside the member |

Use `--remote` before deciding that work is merged: GitHub rebase and squash
merges rewrite commits, so only the PR lookup sees them.

## 6. Remove the set

Remove a set when the user asks or the ticket's PRs are merged. Run
`status <key> --remote` first, then:

```bash
bash scripts/worktree.sh remove <key> [--delete-bookmarks] [--archive]
```

- `remove` refuses while any member has uncommitted or unpublished work and
  names each one. `--force` overrides that guard; use it only with the
  user's approval for that set. jj members keep the work as a commit and
  Git-only members stash it, but ignored files (build output, `.env`) are
  deleted in both.
- `--delete-bookmarks` forgets a local `<key>` branch only when it still
  points at its starting commit or an upstream branch contains its commits;
  remote branches stay. A rebase- or squash-merged branch is kept: after
  confirming the merged PR, forget it with `jj bookmark forget <key>` in
  `repo/<name>`.
- `--archive` copies the manifest into the matching `ticket/*-<issue>-*/`
  folder.

Done when `list` no longer shows the key and `prune` reports no drift.

## Repair

`bash scripts/worktree.sh prune` reports drift between manifests, jj
workspaces, and Git worktrees; `prune --apply` fixes what it can. Retire
members only through `drop`, `remove`, or `prune`: deleting a member
directory by hand leaves its jj workspace and Git worktree registered.
