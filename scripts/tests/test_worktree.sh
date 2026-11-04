#!/usr/bin/env bash
# Offline tests for scripts/worktree.sh. Every repository, remote, and config
# file lives under mktemp; HOME and XDG_CONFIG_HOME are redirected so that jj
# and git never touch the real user configuration.
set -euo pipefail
export LC_ALL=C

SCRIPT=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")/../worktree.sh")
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT

export HOME="$TEMP/home" XDG_CONFIG_HOME="$TEMP/xdg" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME/jj" "$TEMP/bin"
cat >"$HOME/.gitconfig" <<'EOF'
[user]
	name = Test User
	email = test@example.com
[init]
	defaultBranch = master
[advice]
	detachedHead = false
EOF
cat >"$XDG_CONFIG_HOME/jj/config.toml" <<'EOF'
[user]
name = "Test User"
email = "test@example.com"
EOF

# Fake gh: issue titles and one merged PR.
cat >"$TEMP/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "issue view")
    case "$3" in
      14427) echo "[IMPROVEMENT] Make repository build/validate scripts work in Git worktrees and jj workspaces" ;;
      200) echo "[BACKPORT][v1.10.x] [BUG] Engine stuck during node restart" ;;
      *) exit 1 ;;
    esac ;;
  "pr list")
    head=''
    while [ "$#" -gt 0 ]; do [ "$1" = --head ] && head=$2; shift; done
    [ "$head" = poc-beta ] && echo "https://github.com/longhorn/foo/pull/1"
    exit 0 ;;
  *) exit 90 ;;
esac
FAKE_GH
chmod +x "$TEMP/bin/gh"
export PATH="$TEMP/bin:$PATH"

W="$TEMP/ws"
export LONGHORN_WORKSPACE_ROOT="$W"
FAILS=0
PASSES=0
pass() { PASSES=$((PASSES + 1)); echo "PASS $1"; }
fail() { FAILS=$((FAILS + 1)); echo "FAIL $1"; }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
wt() { bash "$SCRIPT" "$@"; }
rc_of() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
jjq() { local r=$1; shift; jj --no-pager --color=never -R "$W/repo/$r" --ignore-working-copy "$@" 2>/dev/null; }
manifest() { jq -r "$2" "$W/worktree/$1/worktree.json"; }

# --- fixture ---------------------------------------------------------------
commit_file() { # dir file content message
  echo "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "$4"
}

make_upstream() { # name trunk
  local name=$1 trunk=$2 seed="$TEMP/seed-$1"
  git init -q --bare "$TEMP/up-$name.git"
  git init -q --bare "$TEMP/fork-$name.git"
  git init -q -b "$trunk" "$seed"
  commit_file "$seed" README "base" "init"
  git -C "$seed" push -q "$TEMP/up-$name.git" "$trunk"
  git -C "$seed" branch -q v1.13.x
  commit_file "$seed" README "trunk2" "feat: trunk moves on"
  git -C "$seed" push -q "$TEMP/up-$name.git" "$trunk" v1.13.x
  git -C "$TEMP/up-$name.git" symbolic-ref HEAD "refs/heads/$trunk"
}

make_jj_repo() { # name trunk
  local name=$1 trunk=$2 dir="$W/repo/$1"
  make_upstream "$name" "$trunk"
  git clone -q --origin upstream "$TEMP/up-$name.git" "$dir"
  git -C "$dir" remote add origin "$TEMP/fork-$name.git"
  (
    cd "$dir"
    jj git init --colocate . >/dev/null 2>&1
    jj config set --repo 'revset-aliases."trunk()"' "$trunk@upstream"
    jj config set --repo git.fetch '["upstream","origin"]'
    jj config set --repo remotes.origin.auto-track-bookmarks '"*"'
    jj bookmark track "$trunk" --remote=upstream >/dev/null 2>&1
  )
}

mkdir -p "$W/repo" "$W/agent-skills" "$W/ticket/lh-110-archive_me"
echo "# test" >"$W/AGENTS.md"
make_jj_repo foo master
make_jj_repo bar main
make_jj_repo longhorn-manager master
make_upstream plain master
git clone -q --origin upstream "$TEMP/up-plain.git" "$W/repo/plain"
git -C "$W/repo/plain" remote add origin "$TEMP/fork-plain.git"
# A trunk commit that references the upstream fix, for the 'repos' hint.
seed="$TEMP/seed-longhorn-manager"
commit_file "$seed" fix.txt fix "fix(build): pass version via build args

longhorn/longhorn#14427"
git -C "$seed" push -q "$TEMP/up-longhorn-manager.git" master
jj -R "$W/repo/longhorn-manager" git fetch --remote upstream >/dev/null 2>&1

# --- keys ------------------------------------------------------------------
for k in 12345-key-title poc-nvme-tcp-frontend 14111-disk-bim-restart-v1.13.x spike-go127-upgrade; do
  check "key accepts $k" test "$(wt key "$k" 2>/dev/null)" = "$k"
done
long=poc-$(printf 'a%.0s' {1..61})
for k in LH-1-x 1-Bad 0001-x 1-a--b 12345 -x 1-x-v1.13.y default "$long"; do
  check "key rejects $k" test "$(rc_of wt key "$k")" = 2
done
check "slug from issue title" test "$(wt key --issue 14427 2>/dev/null)" = 14427-make-repository-build-validate-scripts
check "slug strips stacked tags" test "$(wt key --issue 200 2>/dev/null)" = 200-engine-stuck-during-node-restart
check "explicit slug" test "$(wt key --issue 1 --slug abc 2>/dev/null)" = 1-abc
check "--slug needs --issue" test "$(rc_of wt key poc-a --slug b)" = 2

# --- create ----------------------------------------------------------------
check "create 100-alpha" test "$(rc_of wt create 100-alpha foo bar plain)" = 0
check "manifest members" test "$(manifest 100-alpha '.repos | keys | join(",")')" = bar,foo,plain
check "manifest vcs" test "$(manifest 100-alpha '[.repos.foo.vcs, .repos.plain.vcs] | join(",")')" = jj,git
check "manifest issue" test "$(manifest 100-alpha .issue)" = 100
check "relative gitdir" grep -q '^gitdir: \.\./' "$W/worktree/100-alpha/foo/.git"
check "jj workspace exists" test "$(rc_of jjq foo workspace root --name 100-alpha)" = 0
check "branch created in jj repo" test -n "$(git -C "$W/repo/foo" branch --list 100-alpha)"
check "branch created in git repo" test -n "$(git -C "$W/repo/plain" branch --list 100-alpha)"
check "base commit recorded" test "$(manifest 100-alpha .repos.foo.base_commit)" = "$(git -C "$W/repo/foo" rev-parse upstream/master)"
check "create refuses existing set" test "$(rc_of wt create 100-alpha foo)" = 1
check "add refuses existing member" test "$(rc_of wt add 100-alpha foo)" = 1

check "unsupported repo refused" test "$(rc_of wt create 101-x foo longhorn-manager)" = 1
check "refusal creates nothing" test ! -e "$W/worktree/101-x"
check "refusal leaves no workspace" test "$(rc_of jjq foo workspace root --name 101-x)" = 1
check "unknown repo refused" test "$(rc_of wt create 101-y nope)" = 1
check "dot segment refused" test "$(rc_of wt create 101-z foo/.)" = 1
check "leading dot refused" test "$(rc_of wt create 101-z ./foo)" = 1
check "dot-wrapped unsupported refused" test "$(rc_of wt create 101-z longhorn-manager/.)" = 1
check "two global bases refused" test "$(rc_of wt create 101-z foo --base 'trunk()' --base 'trunk()')" = 2
check "multi-commit base refused" test "$(rc_of wt create 101-z foo --base 'all()')" = 1
check "missing base refused" test "$(rc_of wt create 101-z foo --base nope@upstream)" = 1
check "refused bases create nothing" test ! -e "$W/worktree/101-z"

check "dry-run create" test "$(rc_of wt create 108-dry foo -n)" = 0
check "dry-run creates nothing" test ! -e "$W/worktree/108-dry"

check "second set shares foo" test "$(rc_of wt create poc-beta foo)" = 0
check "two Git worktrees of foo" test "$(git -C "$W/repo/foo" worktree list | grep -c worktree/)" = 2
check "path of member" test "$(wt path poc-beta foo)" = "$W/worktree/poc-beta/foo"
check "path of non-member" test "$(rc_of wt path poc-beta bar)" = 1

# --- status ----------------------------------------------------------------
st() { wt status "$1" --json | jq -r --arg r "$2" ".[] | select(.repo == \$r) | $3"; }
check "fresh status" test "$(st 100-alpha foo '[.commits, .lag, .uncommitted, .unpublished, .merged, .bookmark] | map(tostring) | join(",")')" = "0,0,false,0,no,ok"
M="$W/worktree/100-alpha/foo"
echo work >"$M/work.txt"
check "uncommitted detected" test "$(st 100-alpha foo .uncommitted)" = true
jj --no-pager -R "$M" commit -m "feat: work" >/dev/null 2>&1
check "commit: lag and unpublished" test "$(st 100-alpha foo '[.uncommitted, .commits, .lag, .unpublished] | map(tostring) | join(",")')" = "false,0,1,1"
wt bookmark 100-alpha >/dev/null 2>&1
check "bookmark advances" test "$(st 100-alpha foo '[.commits, .lag] | map(tostring) | join(",")')" = "1,0"
check "list --json" test "$(wt list --json | jq length)" = 2
check "plain status" test "$(st 100-alpha plain '[.commits, .uncommitted, .unpublished] | map(tostring) | join(",")')" = "0,false,0"

# --- remove guards -----------------------------------------------------------
check "remove refuses unpublished" test "$(rc_of wt remove 100-alpha)" = 1
check "refused remove keeps set" test -d "$M"
jj --no-pager -R "$M" git push --remote origin --bookmark 100-alpha >/dev/null 2>&1
check "pushed: nothing unpublished" test "$(st 100-alpha foo .unpublished)" = 0
echo scratch >"$W/worktree/100-alpha/plain/scratch.txt"
check "remove refuses dirty git member" test "$(rc_of wt remove 100-alpha)" = 1
rm "$W/worktree/100-alpha/plain/scratch.txt"
check "remove 100-alpha" test "$(rc_of wt remove 100-alpha --delete-bookmarks)" = 0
check "set directory gone" test ! -e "$W/worktree/100-alpha"
check "foo workspace gone" test "$(rc_of jjq foo workspace root --name 100-alpha)" = 1
check "unmerged bookmark kept" test -n "$(jjq foo bookmark list 100-alpha)"
check "empty bookmark forgotten" test -z "$(jjq bar bookmark list 100-alpha)"
check "empty git branch deleted" test -z "$(git -C "$W/repo/plain" branch --list 100-alpha)"
check "no stray Git worktrees" test "$(git -C "$W/repo/plain" worktree list | wc -l)" = 1

# --- adopt -----------------------------------------------------------------
check "existing branch needs --adopt" test "$(rc_of wt create 100-alpha foo)" = 1
check "adopt local branch" test "$(rc_of wt create 100-alpha foo --adopt)" = 0
check "adopted member on branch" test "$(jjq foo log --no-graph -r '"100-alpha"@-' -T 'description.first_line()')" = "feat: work"
check "adopted status" test "$(st 100-alpha foo '[.commits, .unpublished] | map(tostring) | join(",")')" = "1,0"
check "remove adopted set" test "$(rc_of wt remove 100-alpha)" = 0
jjq foo bookmark forget 100-alpha >/dev/null 2>&1
check "adopt from origin" test "$(rc_of wt create 100-alpha foo --adopt)" = 0
check "local branch tracked again" test -n "$(jjq foo bookmark list 100-alpha)"
check "remove origin-adopted set" test "$(rc_of wt remove 100-alpha)" = 0
check "adopt without branch refused" test "$(rc_of wt create 111-none foo --adopt)" = 1

# --- bases -----------------------------------------------------------------
check "release suffix set" test "$(rc_of wt create 103-fix-v1.13.x foo)" = 0
check "release base" test "$(manifest 103-fix-v1.13.x .repos.foo.base)" = "v1.13.x@upstream"
check "release base commit" test "$(manifest 103-fix-v1.13.x .repos.foo.base_commit)" = "$(git -C "$W/repo/foo" rev-parse upstream/v1.13.x)"
check "per-repo base" test "$(rc_of wt create 104-o foo bar --base bar=v1.13.x@upstream)" = 0
check "per-repo base recorded" test "$(manifest 104-o '[.repos.foo.base, .repos.bar.base] | join(",")')" = "trunk(),v1.13.x@upstream"

# --- drop / add ------------------------------------------------------------
check "drop bar" test "$(rc_of wt drop 104-o bar)" = 0
check "drop updates manifest" test "$(manifest 104-o '.repos | keys | join(",")')" = foo
check "dropped workspace gone" test "$(rc_of jjq bar workspace root --name 104-o)" = 1
check "re-add needs --adopt (branch kept)" test "$(rc_of wt add 104-o bar)" = 1
check "add bar back with --adopt" test "$(rc_of wt add 104-o bar --adopt)" = 0
check "add updates manifest" test "$(manifest 104-o '.repos | keys | join(",")')" = bar,foo

# --- merged detection --------------------------------------------------------
B="$W/worktree/103-fix-v1.13.x/foo"
echo fix >"$B/fix.txt"
jj --no-pager -R "$B" commit -m "fix: backport" >/dev/null 2>&1
wt bookmark 103-fix-v1.13.x >/dev/null 2>&1
git -C "$W/repo/foo" push -q upstream 103-fix-v1.13.x:v1.13.x
jjq foo git fetch --remote upstream >/dev/null 2>&1
check "merge into upstream detected" test "$(st 103-fix-v1.13.x foo '[.merged, .unpublished] | map(tostring) | join(",")')" = "upstream,0"
check "remove merged set" test "$(rc_of wt remove 103-fix-v1.13.x --delete-bookmarks)" = 0
check "merged bookmark forgotten" test -z "$(jjq foo bookmark list 103-fix-v1.13.x)"

PB="$W/worktree/poc-beta/foo"
echo beta >"$PB/beta.txt"
jj --no-pager -R "$PB" commit -m "feat: beta" >/dev/null 2>&1
wt bookmark poc-beta >/dev/null 2>&1
jj --no-pager -R "$PB" git push --remote origin --bookmark poc-beta >/dev/null 2>&1
url=$(git -C "$W/repo/foo" remote get-url upstream)
git -C "$W/repo/foo" remote set-url upstream https://github.com/longhorn/foo.git
check "merged PR via --remote" test "$(wt status poc-beta --remote --json | jq -r '.[0].merged')" = pr
git -C "$W/repo/foo" remote set-url upstream "$url"

# --- prune -----------------------------------------------------------------
check "create 106-p" test "$(rc_of wt create 106-p foo)" = 0
rm -rf "$W/worktree/106-p/foo"
mkdir -p "$W/worktree/junk"
git -C "$W/repo/foo" worktree add -q --detach "$TEMP/outside"
rm -rf "$TEMP/outside"
jj --no-pager -R "$W/repo/foo" workspace add --name stray "$W/worktree/junk/foo" >/dev/null 2>&1
prune_out=$(wt prune 2>&1)
check "prune reports stray workspace" grep -q "workspace 'stray' at worktree/junk/foo is not listed" <<<"$prune_out"
check "prune reports dir without manifest" grep -q "worktree/junk: directory without worktree.json" <<<"$prune_out"
check "prune reports gone member" grep -q "106-p/foo: directory is gone" <<<"$prune_out"
check "prune report keeps manifest" test "$(rc_of wt prune)" = 0
check "prune report changes nothing" test "$(manifest 106-p '.repos | keys | join(",")')" = foo
check "prune --apply" test "$(rc_of wt prune --apply)" = 0
check "prune dropped member" test "$(manifest 106-p '.repos | length')" = 0
check "prune forgot workspace" test "$(rc_of jjq foo workspace root --name 106-p)" = 1
check "prune cleared set entries" test -z "$(git -C "$W/repo/foo" worktree list | grep "$W/worktree" | grep prunable || true)"
check "prune left outside entry alone" test -n "$(git -C "$W/repo/foo" worktree list | grep "$TEMP/outside" | grep prunable || true)"
check "prune kept junk dir" test -d "$W/worktree/junk"
check "prune kept stray workspace" test "$(rc_of jjq foo workspace root --name stray)" = 0
jj --no-pager -R "$W/repo/foo" workspace remove stray >/dev/null 2>&1
rmdir "$W/worktree/junk"
check "remove empty set" test "$(rc_of wt remove 106-p)" = 0

# --- leftovers and archive ----------------------------------------------------
check "create 109-l" test "$(rc_of wt create 109-l foo)" = 0
echo note >"$W/worktree/109-l/notes.txt"
check "remove with leftovers" test "$(rc_of wt remove 109-l)" = 0
check "leftover kept" test -f "$W/worktree/109-l/notes.txt"
check "leftover set has no manifest" test ! -e "$W/worktree/109-l/worktree.json"
rm -r "$W/worktree/109-l"
check "create 110-arch" test "$(rc_of wt create 110-arch foo)" = 0
check "remove --archive" test "$(rc_of wt remove 110-arch --archive)" = 0
check "manifest archived" test -f "$W/ticket/lh-110-archive_me/worktree-110-arch.json"
check "archive keeps members" test "$(jq -r '.repos | keys | join(",")' "$W/ticket/lh-110-archive_me/worktree-110-arch.json")" = foo

# --- dry-run removal -----------------------------------------------------------
check "create 112-dry" test "$(rc_of wt create 112-dry foo bar)" = 0
check "drop -n" test "$(rc_of wt drop 112-dry bar -n)" = 0
check "remove -n" test "$(rc_of wt remove 112-dry -n --delete-bookmarks)" = 0
check "dry-run kept members" test "$(manifest 112-dry '.repos | keys | join(",")')" = bar,foo
check "dry-run kept workspace" test "$(rc_of jjq bar workspace root --name 112-dry)" = 0
check "dry-run kept bookmark" test -n "$(jjq bar bookmark list 112-dry)"
check "drop duplicate refused" test "$(rc_of wt drop 112-dry bar bar)" = 1
check "remove 112-dry" test "$(rc_of wt remove 112-dry --delete-bookmarks)" = 0

# --- forced removal keeps work -------------------------------------------------
check "create 120-force" test "$(rc_of wt create 120-force foo plain)" = 0
echo forced >"$W/worktree/120-force/foo/forced.txt"
echo forced >"$W/worktree/120-force/plain/forced.txt"
check "dirty set refused" test "$(rc_of wt remove 120-force)" = 1
check "forced remove" test "$(rc_of wt remove 120-force --force)" = 0
check "jj kept forced work as a commit" test -n "$(jjq foo log --no-graph -r 'all() & files(root:"forced.txt")' -T 'commit_id')"
check "git stashed forced work" test -n "$(git -C "$W/repo/plain" stash list | grep 'worktree.sh remove 120-force')"

# --- Git-only member: commits, bookmark, drop -----------------------------------
check "create 122-g" test "$(rc_of wt create 122-g plain foo)" = 0
G="$W/worktree/122-g/plain"
commit_file "$G" g.txt g "feat: git work"
check "git member commits" test "$(st 122-g plain '[.commits, .unpublished] | map(tostring) | join(",")')" = "1,1"
check "bookmark skips git member" test "$(rc_of wt bookmark 122-g)" = 0
check "drop unpublished git member refused" test "$(rc_of wt drop 122-g plain --delete-bookmarks)" = 1
check "forced drop of git member" test "$(rc_of wt drop 122-g plain --force --delete-bookmarks)" = 0
check "unmerged git branch kept" test -n "$(git -C "$W/repo/plain" branch --list 122-g)"
git -C "$W/repo/plain" branch -q -D 122-g

# --- lock contention -------------------------------------------------------------
( flock -n 9 && sleep 3 ) 9>"$W/worktree/122-g/.lock" &
locker=$!
sleep 0.5
check "busy set refused" test "$(rc_of wt bookmark 122-g)" = 1
check "busy set refused for remove" test "$(rc_of wt remove 122-g)" = 1
wait "$locker"
check "remove 122-g" test "$(rc_of wt remove 122-g --delete-bookmarks)" = 0

# --- a base that moves onto the work does not count as merged --------------------
jjq foo bookmark create movable -r 'master@upstream' >/dev/null
check "create 124-mv on a local base" test "$(rc_of wt create 124-mv foo --base movable)" = 0
MV="$W/worktree/124-mv/foo"
echo mv >"$MV/mv.txt"
jj --no-pager -R "$MV" commit -m "feat: mv" >/dev/null 2>&1
wt bookmark 124-mv >/dev/null 2>&1
jjq foo bookmark set movable -r 'bookmarks(exact:"124-mv")' >/dev/null
check "moved base: not merged, not at base" test "$(st 124-mv foo '[.merged, .at_base, .commits] | map(tostring) | join(",")')" = "no,false,0"
check "forced remove 124-mv" test "$(rc_of wt remove 124-mv --force --delete-bookmarks)" = 0
check "branch with work kept despite moved base" test -n "$(jjq foo bookmark list 124-mv)"
jjq foo bookmark forget 124-mv movable >/dev/null

# --- repos -----------------------------------------------------------------
check "repos marks unsupported" test "$(wt repos --json | jq -r '.[] | select(.repo == "longhorn-manager") | .supported')" = false
check "repos fix hint" test -n "$(wt repos --json | jq -r '.[] | select(.repo == "longhorn-manager") | .fix_commit_on_trunk // empty')"
check "repos marks supported" test "$(wt repos --json | jq -r '.[] | select(.repo == "foo") | .supported')" = true

# --- final state -------------------------------------------------------------
check "remaining sets" test "$(wt list --json | jq -r 'map(.key) | sort | join(",")')" = "104-o,poc-beta"
check "remove 104-o" test "$(rc_of wt remove 104-o)" = 0
check "remove poc-beta" test "$(rc_of wt remove poc-beta --delete-bookmarks)" = 0
check "only default workspaces left" test "$(jjq foo workspace list -T 'name ++ "\n"')" = default

echo "passed=$PASSES failed=$FAILS"
[ "$FAILS" -eq 0 ]
