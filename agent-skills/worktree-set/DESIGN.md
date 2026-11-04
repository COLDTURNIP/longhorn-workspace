# Design: worktree sets

Status: implemented 2026-11-04 in `scripts/worktree.sh`, tested by
`scripts/tests/test_worktree.sh`. Related upstream work: longhorn/longhorn#14427
(make repository builds work in Git worktrees and jj workspaces).

## 1. Problem and constraints

- A story ticket usually touches 2-5 of the ~25 repositories under `repo/`,
  several tickets run at once, and coding agents often work in parallel.
  Switching the canonical checkouts `repo/<name>` between branches
  serializes that work.
- Worktrees must live in a gitignored subfolder of the workspace root.
- Every repository is a jj-colocated Git clone made by `scripts/repo-init.sh`
  (`trunk()` aliased to the upstream default branch). Host tools when this
  was designed: git 2.56, jj 0.46.0, mise.
- The workspace root is itself a jj repository. A jj command run in a
  directory without its own `.jj` acts on the root repository.

## 2. Facts the design relies on

Verified in scratch repositories with jj 0.46.0 and git 2.56:

- In a colocated repo, `jj workspace add` creates a real Git worktree. Its
  `.git` file holds a relative `gitdir:` path, jj enables
  `extensions.relativeworktrees`, and the secondary `.jj/repo` pointer is
  relative too. Moving the whole workspace root keeps everything working.
- Git names worktree metadata after the destination basename and
  de-duplicates it, so two sets can each hold a member of the same repo.
- jj keeps Git `HEAD` detached in every workspace, so two workspaces can sit
  on the same bookmark without Git's "branch already used by worktree" error.
- `jj workspace add` and `jj workspace remove` refuse
  `--ignore-working-copy`; they snapshot the canonical checkout like any jj
  command. A refused `add` still leaves a half-created workspace on the root
  commit, so all checks run before the first `add`. `jj git fetch` and read
  queries accept `--ignore-working-copy`.
- `jj workspace add` needs the destination's parent directory to exist, and
  it happily populates an existing empty directory.
- `jj workspace remove` snapshots a dirty member into a commit before
  deleting the directory, so jj does not lose that work.
- `jj workspace forget` leaves the directory; a directory deleted before
  `forget` leaves a prunable Git worktree entry.
- `jj log` from the canonical repo does not snapshot another workspace;
  state checks first run a jj command inside the member.
- `jj bookmark advance <key> --to @-` moves only the named bookmark, leaves
  the trunk bookmark on the same base commit alone, and refuses to move
  backwards or sideways. Without a name it would also move the trunk
  bookmark.
- A `git stash push --include-untracked` taken inside a Git worktree lands in
  the shared stash of the repository.
- jj's own `workspace remove` and `forget` run a repository-wide
  `git worktree prune`, which also prunes stale entries outside `worktree/`.
- Revsets quote keys: `bookmarks(exact:"<key>")` for the branch and
  `"<key>"@` for the workspace's working-copy commit, because keys may start
  with digits.
- jj stores `--repo` config under `$XDG_CONFIG_HOME/jj/repos/`, so tests
  redirect `HOME` and `XDG_CONFIG_HOME`.

From the survey of multi-repo tooling (2024-2026):

- Tools that model "ticket = worktrees across repos" (gion, multree, clawk,
  repoweave, teatree) use an external `<root>/<dir>/<ticket>/<repo>` layout
  plus a manifest, because `git worktree list` is per repository. General
  multi-repo runners (mani, gita, git-workspace, tsrc, myrepos) do not model
  this.
- Agent harnesses (Claude Code `.claude/worktrees/`, Cursor, Codex) nest
  worktrees in the repo or the home directory. Nested worktrees pollute
  Docker build contexts and file watchers, and JetBrains warns against them.
- Container builds that run git inside `COPY . .` fail from any worktree;
  relative worktree paths do not help because the build context is the
  worktree alone. That is longhorn/longhorn#14427.

## 3. Layout

```
worktree/                 gitignored except worktree/AGENTS.md
  AGENTS.md               rules for agents working inside members
  <key>/
    worktree.json         manifest
    .lock                 flock target
    <repo>/               jj workspace <key> of repo/<repo>
```

`worktree/` sits at the root because `ticket/` entries are deleted by
ticket-cleanup, `repo/<name>/` is a Docker build context and a jj working
copy, and a root subfolder inherits the root `mise.toml` (Go, Node,
`KUBECONFIG`) without another trust step.

## 4. Key

One key names the set directory, the jj workspace in each member, the local
branch, and the pushed branch.

- Ticket-bound `<issue>-<slug>` (longhorn/longhorn issue, no leading zeros);
  unbound `<slug>` starting with a letter for POCs and spikes.
- Slug: lowercase `[a-z0-9]` words joined by single hyphens; key at most 64
  characters; optional `-v<major>.<minor>.x` suffix selecting the release
  branch as default base.
- Regex:
  `^([1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*|[a-z][a-z0-9]*(-[a-z0-9]+)*)(-v[0-9]+\.[0-9]+\.x)?$`
  plus `git check-ref-format --branch`; `default` is reserved for the
  canonical jj workspace.
- Slug from an issue title: drop leading `[...]` tags, lowercase, collapse
  non-`[a-z0-9]` runs into `-`, keep whole words up to 40 characters.
- One key owns one branch per repo. `create` refuses an existing `<key>`
  branch, local or on `origin`, unless `--adopt` continues it. After a PR
  from `<key>` merges, follow-up work takes a new key.
- `ticket/` keeps its `lh-<issue>-<snake_case>` names; the issue number links
  the two.

## 5. Manifest

```json
{
  "version": 1,
  "key": "12345-key-title",
  "issue": 12345,
  "created": "2026-11-04T09:00:00Z",
  "repos": {
    "go-common-libs": { "vcs": "jj", "base": "trunk()", "base_commit": "<sha>" }
  }
}
```

`issue` is null for unbound keys. `vcs` is `git` for repositories without
`.jj` (plain `git worktree add --relative-paths -b <key>`). `base` is the
revset that commits are counted against; `base_commit` is its value at
creation. A branch still at `base_commit` has no work of its own, whatever the
base revset resolves to later. The
manifest groups members; jj and Git stay the source of truth, and `prune`
reconciles them.

## 6. Behavior

- Repository names are paths under `repo/` whose segments start with a
  letter or digit, so `foo/.` cannot alias `foo` or slip past the
  unsupported list. At most one global `--base` is accepted.
- `create`/`add` validate every member first (repository exists, not
  unsupported, destination free, no workspace or branch named `<key>`),
  fetch `upstream` (and `origin` with `--adopt`), resolve each base to one
  commit, and only then create workspaces and the `<key>` bookmark at `@-`.
  On a mid-way failure the manifest lists exactly the members that exist.
- `status` fields: `uncommitted` (`"<key>"@` non-empty), `commits`
  (`base..<key>`), `lag` (`<key>.."<key>"@-`), `unpublished`
  (`(base.."<key>"@) ~ empty() ~ ::remote_bookmarks(exact:"<key>", exact:"origin")`),
  `at_base` (bookmark still at `base_commit`), `merged` (`upstream` when an
  upstream remote branch contains the bookmark, independent of the base
  revset; `pr` from `gh pr list --head <key> --author @me --state merged`
  with `--remote`), `bookmark`, `stale`, and `unsupported`. A failed query
  becomes an `error` so that guards fail closed.
- `drop`/`remove` inspect every member first, run `update-stale` on stale
  members (jj 0.46 `workspace remove` refuses stale workspaces,
  jj-vcs/jj#10276), refuse uncommitted or unpublished work unless `--force`,
  then `jj workspace remove` (or `forget` when the directory is gone). A
  forced Git-only member is stashed with `git stash push --include-untracked`
  before `git worktree remove --force`. Afterwards only Git worktree metadata
  for missing directories under `worktree/` is removed; `git worktree prune`
  is never run. `--delete-bookmarks` runs `jj bookmark forget exact:<key>`
  (local only) or `git branch -D` when the branch is at `base_commit` or
  `merged` is not `no`. `remove --archive` archives a copy of the manifest
  taken before any member is removed. `remove` deletes only the manifest and
  lock, then `rmdir`s the set; leftover files are reported.
- `prune` reports members whose directory is gone, directories without a
  manifest, workspaces under `worktree/` that no manifest lists, and
  Git worktree metadata pointing to missing directories under `worktree/`;
  `--apply` forgets dead workspaces, removes that metadata, and drops dead
  members, holding each set's lock and skipping busy sets. It never deletes a
  directory and ignores workspaces and worktrees outside `worktree/`.
- Invariants: files change only under `worktree/<key>/`, repository
  metadata, and `ticket/*/worktree-<key>.json` for `--archive`; the only
  bookmark touched is `<key>`; network access is fetches and read-only `gh`;
  `add`, `drop`, `remove`, `bookmark`, and `prune --apply` hold `flock` on the
  set's lock before their checks (`create` right after creating the set).

## 7. Unsupported repositories

Repositories whose Makefile builds fail or pass silently from a worktree
cannot join a set; their part of a ticket stays in `repo/<name>` on a branch
named `<key>`. The list lives in `UNSUPPORTED` in `scripts/worktree.sh`, and
`worktree.sh repos` shows it with a hint when trunk already contains a commit
referencing longhorn/longhorn#14427. Initial entries, from an evaluation of
upstream main/master:

| Repo | Reason |
|---|---|
| longhorn-manager | make build/ci abort in scripts/version; make validate falsely reports stale crds.yaml |
| longhorn-engine | make build/ci abort in scripts/version; make sync-grpc-py passes silently |
| longhorn-instance-manager | make build/ci abort in scripts/version |
| longhorn-share-manager | make build/ci abort in scripts/version |
| backing-image-manager | make build/ci abort in scripts/version |
| cli | make build/ci abort in scripts/version |
| sparse-tools | Dapper ci aborts in scripts/version |
| types | make validate/ci pass silently (scripts/checkdiff) |

Remove an entry once its fix is merged and `make ci` passes from a member.

## 8. Alternatives considered

- Worktrees under `ticket/<key>/`: ticket-cleanup deletes inactive entries
  recursively.
- Worktrees under `repo/<name>/.worktrees/`: nested in the build context and
  the canonical jj working copy.
- A central `~/worktrees/`: loses the root `mise.toml` and `.venv`, and the
  relative links would cross the workspace boundary.
- Plain `git worktree add` in colocated repos: the worktree has no `.jj`, so
  jj inside it would act on the workspace-root repository.
- gion, multree, clawk, worktrunk: none understands jj workspaces except the
  young grove and renri; the logic is small and must follow this workspace's
  guardrails anyway.
- `git clone --local` per ticket: works with today's builds but duplicates
  refs and is unnecessary once #14427 lands.

## 9. Known limitations

- Deferred until every repository supports worktrees: the VCS is chosen per
  repository from the presence of `.jj`, not from whether jj is installed.
  Without jj, `create` stops on colocated repositories instead of falling
  back to Git; with jj, a repository without `.jj` becomes a Git-only member.
  The agent documents describe only the jj commands. The intended rule is to
  choose jj when it is installed and the repository is colocated, Git
  otherwise, record the choice per member, and let that record decide the
  tools later, because jj inside a Git-only member acts on the workspace-root
  repository.
- jj's `workspace remove`/`forget` prune stale Git worktree entries
  repository-wide, including entries outside `worktree/`.
- Removal deletes ignored files in the member (build output, `.env`); the
  guards do not report them.
- Stale-workspace handling and a failure in the middle of `create` are not
  covered by the offline tests.
- The sync-crd-helm and interaction-mapper skill scripts always use
  `repo/longhorn-manager`, `repo/longhorn`, and `repo/types`.
- `gh pr list --head` matches by branch name; `--author @me` narrows it.
- Fixed container image and container names in some Makefiles (for example
  `go-iscsi-helper-test`, `longhorn-spdk-engine-test`, and the
  `backupstore-test` container) collide when two sets run `make test` for the
  same repository at once.

## 10. Sources

- https://git-scm.com/docs/git-worktree
- https://docs.jj-vcs.dev/latest/working-copy/
- https://docs.jj-vcs.dev/latest/changelog/
- https://github.com/jj-vcs/jj/issues/10276
- https://github.com/tasuku43/gion
- https://github.com/gileze33/multree
- https://github.com/longhorn/longhorn/issues/14427
