#!/usr/bin/env bash
# Manage worktree sets: one directory worktree/<key>/ per ticket or POC, holding
# one jj workspace (a Git worktree) per member repository, all on branch <key>.

set -euo pipefail

resolve_script_dir() {
  local source_path=${BASH_SOURCE[0]} source_dir target
  while [ -h "$source_path" ]; do
    source_dir=$(CDPATH='' cd -- "$(dirname -- "$source_path")" && pwd -P)
    target=$(readlink "$source_path")
    case "$target" in
      /*) source_path=$target ;;
      *) source_path="$source_dir/$target" ;;
    esac
  done
  CDPATH='' cd -- "$(dirname -- "$source_path")" && pwd -P
}

SCRIPT_DIR=$(resolve_script_dir)
SCRIPT_NAME=worktree.sh
DRY_RUN=false
# shellcheck source-path=SCRIPTDIR source=lib/defensive_prelude.sh
source "$SCRIPT_DIR/lib/defensive_prelude.sh"

# Logs go to stderr so that stdout carries only results (path, key, JSON).
info() { log_line INFO "$1" >&2; }
warn() { log_line WARN "$1" >&2; }
EXIT_REFUSED=1
refuse() { error "$1"; exit "$EXIT_REFUSED"; }
usage_error() { error "$1"; echo "Run '$SCRIPT_NAME --help' for usage." >&2; exit "$EXIT_ARG"; }

KEY_RE='^([1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*|[a-z][a-z0-9]*(-[a-z0-9]+)*)(-v[0-9]+\.[0-9]+\.x)?$'
KEY_MAX=64
SLUG_MAX=40
REPO_NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$'
ISSUE_REPO=longhorn/longhorn
FIX_ISSUE_REF=longhorn/longhorn#14427
JJ=(jj --color=never --no-pager)

# Repositories whose Makefile builds fail or pass silently from a worktree
# (longhorn/longhorn#14427). Remove an entry once its fix is merged upstream
# and verified from a worktree.
declare -A UNSUPPORTED=(
  [longhorn-manager]="make build/ci abort in scripts/version; make validate falsely reports stale crds.yaml"
  [longhorn-engine]="make build/ci abort in scripts/version; make sync-grpc-py passes silently"
  [longhorn-instance-manager]="make build/ci abort in scripts/version"
  [longhorn-share-manager]="make build/ci abort in scripts/version"
  [backing-image-manager]="make build/ci abort in scripts/version"
  [cli]="make build/ci abort in scripts/version"
  [sparse-tools]="Dapper ci aborts in scripts/version"
  [types]="make validate/ci pass silently (scripts/checkdiff)"
)

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME <subcommand> [args]

Manage worktree sets under worktree/<key>/. Every member repository gets a jj
workspace named <key> (a Git worktree) on the branch <key>.

Keys:
  <issue>-<slug>      ticket-bound, e.g. 12345-key-title (longhorn/longhorn issue)
  <slug>              unbound, starts with a letter, e.g. poc-nvme-tcp-frontend
  ...-v<M>.<m>.x      optional suffix; default base becomes v<M>.<m>.x@upstream
  Slug: lowercase [a-z0-9] words joined by single hyphens; key <= $KEY_MAX chars.

Subcommands:
  key (<key> | --issue <n> [--slug <s>])
        Print the canonical key. --issue without --slug derives the slug from
        the issue title (gh).
  create (<key> | --issue <n> [--slug <s>]) <repo>... [create options]
        Create a new set with the given member repositories.
  add <key> <repo>... [create options]
        Add member repositories to an existing set.
  drop <key> <repo>... [--force] [--delete-bookmarks] [-n|--dry-run]
        Remove member repositories from a set.
  remove <key> [--force] [--delete-bookmarks] [--archive] [-n|--dry-run]
        Remove the whole set.
  list [--json]
        List sets with their members and bases.
  status [<key>] [--remote] [--json]
        Per member: stale, uncommitted, commits, lag, unpublished, merged.
        --remote also asks GitHub for a merged PR from branch <key>.
  bookmark <key> [<repo>...]
        Run 'jj bookmark advance <key> --to @-' in each jj member.
  path <key> [<repo>]
        Print the absolute path of the set or of one member.
  prune [--apply]
        Report (and with --apply fix) drift between manifests, jj workspaces,
        and Git worktrees.
  repos [--json]
        List repositories with worktree support status.

Create options:
  --base <revset>          base for every member (default: trunk(), or the
                           release branch from a -v<M>.<m>.x key suffix)
  --base <repo>=<revset>   base for one member (repeatable)
  --adopt                  start from an existing <key> branch (local or on
                           origin) instead of creating it
  -n, --dry-run            print planned actions only

Remove options:
  --force                  remove even with uncommitted or unpublished work;
                           jj members keep it as a commit in the repository,
                           Git-only members get a 'git stash push -u' first.
                           Ignored files (build output, .env) are deleted.
  --delete-bookmarks       forget the local <key> branch when it still points at
                           its base commit or its commits are on an upstream
                           branch; remote branches are never touched
  --archive                copy the manifest into the matching ticket/ folder

Dry-run (-n) never creates, removes, or forgets anything, but computing member
state still snapshots each member like any jj command.

Exit codes: 0 ok, 1 refused by a guard or check, 2 usage error, 3 environment error.
USAGE
}

find_workspace_root() {
  local dir
  if [ -n "${LONGHORN_WORKSPACE_ROOT:-}" ]; then
    CDPATH='' cd -- "$LONGHORN_WORKSPACE_ROOT" && pwd -P
    return
  fi
  dir=$SCRIPT_DIR
  while [ ! -f "$dir/AGENTS.md" ] || [ ! -d "$dir/agent-skills" ] || [ ! -d "$dir/repo" ]; do
    if [ "$(dirname "$dir")" = "$dir" ]; then
      return 1
    fi
    dir=$(dirname "$dir")
  done
  printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# Command helpers

run() {
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] $*"
    return 0
  fi
  info "[EXEC] $*"
  "$@" >&2
}

jjq() {
  local repo=$1
  shift
  "${JJ[@]}" -R "$repo" --ignore-working-copy "$@"
}

jj_count() {
  local repo=$1 revset=$2 out
  out=$(jjq "$repo" log --no-graph -r "$revset" -T '"x\n"') || return 1
  printf '%s' "$out" | grep -c x || true
}

jj_commit() {
  local repo=$1 revset=$2
  jjq "$repo" log --no-graph -r "$revset" -T 'commit_id ++ "\n"'
}

jj_workspace_exists() {
  jjq "$1" workspace root --name "$2" >/dev/null 2>&1
}

json_or_null() {
  if [ -n "$1" ]; then printf '%s' "$1"; else printf 'null'; fi
}

# ---------------------------------------------------------------------------
# Keys

derive_slug() {
  local title=$1 cleaned word out='' next
  cleaned=$(printf '%s' "$title" |
    LC_ALL=C sed -E 's/^[[:space:]]*(\[[^]]*\][[:space:]]*)+//' |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  local IFS=-
  for word in $cleaned; do
    next=${out:+$out-}$word
    [ "${#next}" -le "$SLUG_MAX" ] || break
    out=$next
  done
  printf '%s\n' "$out"
}

validate_key() {
  local key=$1
  if [ "${#key}" -gt "$KEY_MAX" ]; then
    usage_error "key '$key' is longer than $KEY_MAX characters"
  fi
  if ! [[ $key =~ $KEY_RE ]]; then
    usage_error "invalid key '$key': use <issue>-<slug> (e.g. 12345-key-title) or a <slug> starting with a letter; lowercase [a-z0-9] words joined by single hyphens"
  fi
  if ! git check-ref-format --branch "$key" >/dev/null 2>&1; then
    usage_error "key '$key' is not a valid branch name"
  fi
  if [ "$key" = default ]; then
    usage_error "key 'default' is reserved for the canonical jj workspace"
  fi
}

issue_of_key() {
  if [[ $1 =~ ^([1-9][0-9]*)- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

release_of_key() {
  if [[ $1 =~ -(v[0-9]+\.[0-9]+\.x)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

# resolve_key <positional-key> <issue> <slug>
resolve_key() {
  local key=$1 issue=$2 slug=$3 title
  if [ -n "$issue" ]; then
    [ -z "$key" ] || usage_error "give either a key or --issue, not both"
    [[ $issue =~ ^[1-9][0-9]*$ ]] || usage_error "invalid issue number '$issue'"
    if [ -z "$slug" ]; then
      command -v gh >/dev/null 2>&1 || die "gh is required to derive the slug; pass --slug"
      title=$(gh issue view "$issue" -R "$ISSUE_REPO" --json title -q .title) ||
        die "unable to read the title of $ISSUE_REPO#$issue; pass --slug"
      slug=$(derive_slug "$title")
      [ -n "$slug" ] || die "issue title '$title' gives an empty slug; pass --slug"
      info "Slug from '$title': $slug"
    fi
    key="$issue-$slug"
  else
    [ -z "$slug" ] || usage_error "--slug requires --issue"
    [ -n "$key" ] || usage_error "missing key"
  fi
  validate_key "$key"
  printf '%s\n' "$key"
}

# ---------------------------------------------------------------------------
# Repositories and manifests

repo_dir() { printf 'repo/%s\n' "$1"; }
set_dir() { printf 'worktree/%s\n' "$1"; }
member_dir() { printf 'worktree/%s/%s\n' "$1" "$2"; }
manifest_path() { printf 'worktree/%s/worktree.json\n' "$1"; }

repo_vcs() {
  if [ -d "$(repo_dir "$1")/.jj" ]; then printf 'jj\n'; else printf 'git\n'; fi
}

upstream_slug() {
  local url
  url=$(git -C "$(repo_dir "$1")" remote get-url upstream 2>/dev/null) || return 1
  if [[ $url =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]%.git}"
  else
    return 1
  fi
}

git_trunk_ref() {
  local repo
  repo=$(repo_dir "$1")
  if git -C "$repo" show-ref --verify --quiet refs/remotes/upstream/main; then
    printf 'upstream/main\n'
  elif git -C "$repo" show-ref --verify --quiet refs/remotes/upstream/master; then
    printf 'upstream/master\n'
  else
    return 1
  fi
}

# Translate a jj-style base into a Git revision for Git-only repositories.
git_base() {
  local repo=$1 base=$2
  case "$base" in
    'trunk()') git_trunk_ref "$repo" ;;
    *@*) printf '%s/%s\n' "${base#*@}" "${base%@*}" ;;
    *) printf '%s\n' "$base" ;;
  esac
}

manifest_require() {
  [ -f "$(manifest_path "$1")" ] || refuse "no worktree set '$1' (missing $(manifest_path "$1"))"
}

manifest_write() {
  local path=$1 tmp
  tmp=$(mktemp "$path.XXXX")
  cat >"$tmp"
  mv "$tmp" "$path"
}

manifest_init() {
  local key=$1 issue
  issue=$(issue_of_key "$key")
  jq -n --arg key "$key" --argjson issue "$(json_or_null "$issue")" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{version: 1, key: $key, issue: $issue, created: $created, repos: {}}' |
    manifest_write "$(manifest_path "$key")"
}

manifest_set_member() {
  local key=$1 repo=$2 vcs=$3 base=$4 base_commit=$5 path
  path=$(manifest_path "$key")
  jq --arg r "$repo" --arg vcs "$vcs" --arg base "$base" --arg bc "$base_commit" \
    '.repos[$r] = {vcs: $vcs, base: $base, base_commit: $bc}' "$path" | manifest_write "$path"
}

manifest_del_member() {
  local key=$1 repo=$2 path
  path=$(manifest_path "$key")
  jq --arg r "$repo" 'del(.repos[$r])' "$path" | manifest_write "$path"
}

manifest_members() {
  jq -r '.repos | keys[]' "$(manifest_path "$1")"
}

manifest_get() {
  jq -r --arg r "$2" --arg f "$3" '.repos[$r][$f] // empty' "$(manifest_path "$1")"
}

lock_set() {
  try_lock_set "$1" || refuse "another $SCRIPT_NAME run holds worktree set '$1'"
}

try_lock_set() {
  exec 9>"$(set_dir "$1")/.lock"
  flock -n 9
}

# Remove Git worktree metadata whose member directory under worktree/ is gone.
# Unlike 'git worktree prune' this leaves entries outside worktree/ alone.
prune_set_worktree_entries() {
  local repo=$1 common meta target found=0
  common=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null) || return 0
  case "$common" in /*) ;; *) common="$repo/$common" ;; esac
  for meta in "$common"/worktrees/*/; do
    [ -f "${meta}gitdir" ] || continue
    [ ! -e "${meta}locked" ] || continue
    target=$(cat "${meta}gitdir")
    case "$target" in /*) ;; *) target=$(realpath -m "${meta}$target") ;; esac
    case "$target" in "$ROOT/worktree/"*) ;; *) continue ;; esac
    [ ! -e "$target" ] || continue
    found=$((found + 1))
    run rm -rf -- "${meta%/}" || warn "unable to remove ${meta%/}"
  done
  PRUNED_ENTRIES=$found
}

# All repositories under repo/ (one or two levels deep).
all_repos() {
  local d
  for d in repo/*/; do
    d=${d%/}
    if [ -e "$d/.git" ]; then
      printf '%s\n' "${d#repo/}"
      continue
    fi
    local sub
    for sub in "$d"/*/; do
      sub=${sub%/}
      [ -e "$sub/.git" ] && printf '%s\n' "${sub#repo/}"
    done
  done
}

# ---------------------------------------------------------------------------
# key

cmd_key() {
  local key='' issue='' slug=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --issue) issue=${2:?--issue needs a value}; shift ;;
      --slug) slug=${2:?--slug needs a value}; shift ;;
      -*) usage_error "unknown option $1" ;;
      *) [ -z "$key" ] || usage_error "unexpected argument $1"; key=$1 ;;
    esac
    shift
  done
  resolve_key "$key" "$issue" "$slug"
}

# ---------------------------------------------------------------------------
# create / add

cmd_create_or_add() {
  local mode=$1
  shift
  local key='' issue='' slug='' adopt=false
  local -a repos=() base_args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --issue) [ "$mode" = create ] || usage_error "--issue is only valid for create"
        issue=${2:?--issue needs a value}; shift ;;
      --slug) [ "$mode" = create ] || usage_error "--slug is only valid for create"
        slug=${2:?--slug needs a value}; shift ;;
      --base) base_args+=("${2:?--base needs a value}"); shift ;;
      --adopt) adopt=true ;;
      -n|--dry-run) DRY_RUN=true ;;
      -*) usage_error "unknown option $1" ;;
      *) repos+=("$1") ;;
    esac
    shift
  done

  if [ -z "$issue" ]; then
    [ "${#repos[@]}" -gt 0 ] || usage_error "missing key"
    key=${repos[0]}
    repos=("${repos[@]:1}")
  fi
  key=$(resolve_key "$key" "$issue" "$slug")
  [ "${#repos[@]}" -gt 0 ] || usage_error "name at least one member repository"

  # Bases: global default, then per-repo overrides.
  local default_base='trunk()' release arg r global_base=''
  release=$(release_of_key "$key")
  [ -z "$release" ] || default_base="$release@upstream"
  declare -A base_of=() in_repos=()
  for r in "${repos[@]}"; do in_repos[$r]=1; done
  for arg in "${base_args[@]}"; do
    r=${arg%%=*}
    if [ "$r" != "$arg" ] && [ -n "${in_repos[$r]:-}" ]; then
      base_of[$r]=${arg#*=}
    else
      [ -z "$global_base" ] || usage_error "give at most one --base without a <repo>= prefix"
      global_base=$arg
    fi
  done
  [ -z "$global_base" ] || default_base=$global_base

  # Static checks on every member before any network or mutation.
  local -a errors=()
  declare -A seen=()
  local set_path dest repo vcs
  set_path=$(set_dir "$key")
  if [ "$mode" = create ]; then
    [ ! -e "$set_path" ] || refuse "worktree set '$key' already exists; use 'add' to add members"
  else
    manifest_require "$key"
    [ "$DRY_RUN" = true ] || lock_set "$key"
  fi
  for r in "${repos[@]}"; do
    if ! [[ $r =~ $REPO_NAME_RE ]]; then
      errors+=("$r: invalid repository name"); continue
    fi
    if [ -n "${seen[$r]:-}" ]; then errors+=("$r: listed twice"); continue; fi
    seen[$r]=1
    repo=$(repo_dir "$r")
    dest=$(member_dir "$key" "$r")
    if [ ! -e "$repo/.git" ]; then errors+=("$r: $repo is not a Git repository"); continue; fi
    if [ -n "${UNSUPPORTED[$r]:-}" ]; then
      errors+=("$r: not supported in worktree sets yet (${UNSUPPORTED[$r]}; $FIX_ISSUE_REF). Work in $repo on a branch named $key instead.")
      continue
    fi
    if [ "$mode" = add ] && [ -n "$(manifest_get "$key" "$r" vcs)" ]; then
      errors+=("$r: already a member of '$key'"); continue
    fi
    [ ! -e "$dest" ] || { errors+=("$r: $dest already exists"); continue; }
    vcs=$(repo_vcs "$r")
    if [ "$vcs" = jj ]; then
      command -v jj >/dev/null 2>&1 || die "jj is required for $repo"
      if jj_workspace_exists "$repo" "$key"; then
        errors+=("$r: jj workspace '$key' already exists (see '$SCRIPT_NAME prune')"); continue
      fi
    else
      local wt_list
      wt_list=$(git -C "$repo" worktree list --porcelain)
      if [[ $'\n'$wt_list$'\n' == *$'\n'"branch refs/heads/$key"$'\n'* ]]; then
        errors+=("$r: branch '$key' is checked out in another worktree"); continue
      fi
    fi
  done
  if [ "${#errors[@]}" -gt 0 ]; then
    printf '  %s\n' "${errors[@]}" >&2
    refuse "nothing was created"
  fi

  # Fetch, then branch and base checks.
  declare -A start_of=() commit_of=() vcs_of=() track_of=()
  local base commit local_exists remote_exists gb
  for r in "${repos[@]}"; do
    repo=$(repo_dir "$r")
    vcs=$(repo_vcs "$r")
    vcs_of[$r]=$vcs
    base=${base_of[$r]:-$default_base}
    base_of[$r]=$base
    if [ "$DRY_RUN" = false ]; then
      if [ "$vcs" = jj ]; then
        run "${JJ[@]}" -R "$repo" --ignore-working-copy git fetch --remote upstream ||
          { errors+=("$r: fetching upstream failed"); continue; }
        if [ "$adopt" = true ] && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
          run "${JJ[@]}" -R "$repo" --ignore-working-copy git fetch --remote origin ||
            { errors+=("$r: fetching origin failed"); continue; }
        fi
      else
        run git -C "$repo" fetch upstream || { errors+=("$r: fetching upstream failed"); continue; }
        if [ "$adopt" = true ] && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
          run git -C "$repo" fetch origin || { errors+=("$r: fetching origin failed"); continue; }
        fi
      fi
    fi

    if [ "$vcs" = jj ]; then
      local_exists=$(jj_count "$repo" "bookmarks(exact:\"$key\")") || { errors+=("$r: unable to query bookmarks"); continue; }
      remote_exists=$(jj_count "$repo" "remote_bookmarks(exact:\"$key\", exact:\"origin\")") || remote_exists=0
      commit=$(jj_commit "$repo" "$base" 2>/dev/null) || { errors+=("$r: base '$base' is not a valid revision"); continue; }
    else
      local_exists=0; remote_exists=0
      git -C "$repo" show-ref --verify --quiet "refs/heads/$key" && local_exists=1
      git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$key" && remote_exists=1
      gb=$(git_base "$r" "$base") || { errors+=("$r: unable to resolve base '$base'"); continue; }
      commit=$(git -C "$repo" rev-parse --verify --quiet "$gb^{commit}") || { errors+=("$r: base '$base' ($gb) is not a valid revision"); continue; }
    fi
    if [ "$(printf '%s\n' "$commit" | grep -c .)" -ne 1 ]; then
      errors+=("$r: base '$base' must resolve to exactly one commit"); continue
    fi
    commit_of[$r]=$commit

    if [ "$adopt" = true ]; then
      if [ "$local_exists" -gt 0 ]; then
        start_of[$r]=existing
      elif [ "$remote_exists" -gt 0 ]; then
        start_of[$r]=existing; track_of[$r]=1
      else
        errors+=("$r: --adopt needs a branch '$key' locally or on origin"); continue
      fi
    else
      if [ "$local_exists" -gt 0 ] || [ "$remote_exists" -gt 0 ]; then
        errors+=("$r: branch '$key' already exists (locally or on origin); use --adopt to continue it"); continue
      fi
      start_of[$r]=base
    fi
  done
  if [ "${#errors[@]}" -gt 0 ]; then
    printf '  %s\n' "${errors[@]}" >&2
    refuse "nothing was created"
  fi

  if [ "$DRY_RUN" = false ]; then
    if [ "$mode" = create ]; then
      mkdir -p worktree
      mkdir "$set_path" || refuse "worktree set '$key' already exists"
      lock_set "$key"
      manifest_init "$key"
    fi
  elif [ "$mode" = create ]; then
    info "[DRY-RUN] create $set_path and its manifest"
  else
    info "[DRY-RUN] add members to $(manifest_path "$key")"
  fi

  local abs_dest start
  for r in "${repos[@]}"; do
    repo=$(repo_dir "$r")
    dest=$(member_dir "$key" "$r")
    abs_dest="$ROOT/$dest"
    base=${base_of[$r]}
    if [ "$DRY_RUN" = false ]; then mkdir -p "$(dirname "$abs_dest")"; fi
    if [ "${vcs_of[$r]}" = jj ]; then
      start=$base
      if [ "${start_of[$r]}" = existing ]; then
        if [ -n "${track_of[$r]:-}" ]; then
          run "${JJ[@]}" -R "$repo" bookmark track "$key" --remote=origin ||
            run "${JJ[@]}" -R "$repo" bookmark track "$key@origin" ||
            die "$r: unable to track $key@origin"
        fi
        start="bookmarks(exact:\"$key\")"
      fi
      if ! run "${JJ[@]}" -R "$repo" workspace add --name "$key" -r "$start" "$abs_dest"; then
        if jj_workspace_exists "$repo" "$key"; then
          manifest_set_member "$key" "$r" jj "$base" "${commit_of[$r]}"
          die "$r: 'jj workspace add' failed after creating the workspace; inspect it, then run '$SCRIPT_NAME drop $key $r --force'"
        fi
        die "$r: 'jj workspace add' failed; members created so far stay in $(manifest_path "$key")"
      fi
      if [ "${start_of[$r]}" = base ]; then
        run "${JJ[@]}" -R "$abs_dest" bookmark create "$key" -r @- ||
          warn "$r: unable to create bookmark $key; create it with 'jj bookmark create $key -r @-' inside $dest"
      fi
    else
      gb=$(git_base "$r" "$base")
      if [ "${start_of[$r]}" = existing ]; then
        if [ -n "${track_of[$r]:-}" ]; then
          run git -C "$repo" worktree add --relative-paths -b "$key" "$abs_dest" "origin/$key" ||
            die "$r: 'git worktree add' failed"
        else
          run git -C "$repo" worktree add --relative-paths "$abs_dest" "$key" || die "$r: 'git worktree add' failed"
        fi
      else
        run git -C "$repo" worktree add --relative-paths --no-track -b "$key" "$abs_dest" "$gb" ||
          die "$r: 'git worktree add' failed"
      fi
    fi
    if [ "$DRY_RUN" = false ]; then
      manifest_set_member "$key" "$r" "${vcs_of[$r]}" "$base" "${commit_of[$r]}"
    fi
    info "$r: $dest on branch $key (base $base)"
  done
  if [ "$DRY_RUN" = false ]; then
    info "Worktree set ready: $set_path. Work inside each member directory; push with 'jj git push --remote origin --bookmark $key'."
  fi
}

# ---------------------------------------------------------------------------
# Member state

# Sets S_* globals for one member. Branch facts (bookmark, commits, merged)
# come from the repository and are computed even when the member directory is
# gone; working-copy facts need the workspace. Every failed query sets S_ERROR
# so that guards fail closed.
member_state() {
  local key=$1 r=$2 remote=${3:-false}
  local repo dest out rc gb bm_commit pr
  repo=$(repo_dir "$r")
  dest=$(member_dir "$key" "$r")
  S_VCS=$(manifest_get "$key" "$r" vcs)
  S_BASE=$(manifest_get "$key" "$r" base)
  S_BASE_COMMIT=$(manifest_get "$key" "$r" base_commit)
  S_PRESENT=yes; S_WORKSPACE=yes; S_STALE=no; S_UNCOMMITTED=no; S_COMMITS=0; S_LAG=0
  S_UNPUBLISHED=0; S_MERGED=no; S_BOOKMARK=ok; S_AT_BASE=no; S_PR=''; S_ERROR=''
  S_UNSUPPORTED=${UNSUPPORTED[$r]:-}

  [ -d "$dest" ] || S_PRESENT=no
  if [ ! -e "$repo/.git" ]; then
    S_WORKSPACE=no
    S_ERROR="$repo is missing"
    return 0
  fi

  if [ "$S_VCS" = jj ]; then
    jj_workspace_exists "$repo" "$key" || S_WORKSPACE=no
    # Snapshot the member so that queries from the repository see its files.
    if [ "$S_PRESENT" = yes ] && [ "$S_WORKSPACE" = yes ]; then
      rc=0
      out=$("${JJ[@]}" -R "$dest" log --no-graph -r @ -T 'empty' 2>&1) || rc=$?
      if [ "$rc" -ne 0 ]; then
        if [[ ${out,,} == *stale* ]]; then
          S_STALE=yes
        else
          S_ERROR=${out%%$'\n'*}
          return 0
        fi
      fi
    fi
    out=$(jj_count "$repo" "bookmarks(exact:\"$key\")") || { S_ERROR="unable to query bookmark $key"; return 0; }
    if [ "$out" -eq 0 ]; then
      S_BOOKMARK=missing
    else
      S_COMMITS=$(jj_count "$repo" "($S_BASE)..bookmarks(exact:\"$key\")") ||
        { S_ERROR="base '$S_BASE' no longer resolves"; return 0; }
      bm_commit=$(jj_commit "$repo" "bookmarks(exact:\"$key\")") ||
        { S_ERROR="unable to resolve bookmark $key"; return 0; }
      if [ "$bm_commit" = "$S_BASE_COMMIT" ]; then
        S_AT_BASE=yes
      else
        out=$(jj_count "$repo" "bookmarks(exact:\"$key\") & ::remote_bookmarks(remote=exact:\"upstream\")") ||
          { S_ERROR="unable to compare $key with upstream"; return 0; }
        [ "$out" -eq 0 ] || S_MERGED=upstream
      fi
    fi
    if [ "$S_WORKSPACE" = yes ]; then
      out=$(jjq "$repo" log --no-graph -r "\"$key\"@" -T 'empty') ||
        { S_ERROR="unable to read the working-copy commit of $key"; return 0; }
      [ "$out" != false ] || S_UNCOMMITTED=yes
      if [ "$S_BOOKMARK" = ok ]; then
        S_LAG=$(jj_count "$repo" "bookmarks(exact:\"$key\")..\"$key\"@-") ||
          { S_ERROR="unable to compare $key with the working copy"; return 0; }
      fi
      S_UNPUBLISHED=$(jj_count "$repo" "(($S_BASE)..\"$key\"@) ~ empty() ~ ::remote_bookmarks(exact:\"$key\", exact:\"origin\")") ||
        { S_ERROR="unable to count unpublished commits"; return 0; }
    fi
  else
    gb=$(git_base "$r" "$S_BASE") || { S_ERROR="unable to resolve base $S_BASE"; return 0; }
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$key"; then
      S_COMMITS=$(git -C "$repo" rev-list --count "$gb..refs/heads/$key" 2>/dev/null) ||
        { S_ERROR="base '$S_BASE' no longer resolves"; return 0; }
      bm_commit=$(git -C "$repo" rev-parse "refs/heads/$key")
      if [ "$bm_commit" = "$S_BASE_COMMIT" ]; then
        S_AT_BASE=yes
      else
        out=$(git -C "$repo" for-each-ref --contains "$bm_commit" --format='%(refname)' refs/remotes/upstream/) ||
          { S_ERROR="unable to compare $key with upstream"; return 0; }
        [ -z "$out" ] || S_MERGED=upstream
      fi
    else
      S_BOOKMARK=missing
    fi
    if [ "$S_PRESENT" = yes ]; then
      out=$(git -C "$dest" status --porcelain) || { S_ERROR="git status failed in $dest"; return 0; }
      [ -z "$out" ] || S_UNCOMMITTED=yes
      if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$key"; then
        S_UNPUBLISHED=$(git -C "$dest" rev-list --count HEAD "^$gb" "^refs/remotes/origin/$key") ||
          { S_ERROR="unable to count unpublished commits"; return 0; }
      else
        S_UNPUBLISHED=$(git -C "$dest" rev-list --count "$gb..HEAD") ||
          { S_ERROR="unable to count unpublished commits"; return 0; }
      fi
    else
      S_WORKSPACE=no
    fi
  fi

  if [ "$remote" = true ] && [ "$S_MERGED" = no ] && [ "$S_AT_BASE" = no ]; then
    local slug
    if slug=$(upstream_slug "$r") && command -v gh >/dev/null 2>&1; then
      pr=$(gh pr list -R "$slug" --head "$key" --author @me --state merged --json url -q '.[0].url' 2>/dev/null) || pr=''
      if [ -n "$pr" ]; then S_MERGED='pr'; S_PR=$pr; fi
    fi
  fi
}

member_state_json() {
  jq -n --arg key "$1" --arg repo "$2" --arg vcs "$S_VCS" --arg base "$S_BASE" \
    --arg present "$S_PRESENT" --arg workspace "$S_WORKSPACE" --arg stale "$S_STALE" \
    --arg uncommitted "$S_UNCOMMITTED" --argjson commits "$S_COMMITS" --argjson lag "$S_LAG" \
    --argjson unpublished "$S_UNPUBLISHED" --arg merged "$S_MERGED" --arg pr "$S_PR" \
    --arg bookmark "$S_BOOKMARK" --arg at_base "$S_AT_BASE" --arg unsupported "$S_UNSUPPORTED" --arg error "$S_ERROR" \
    '{key: $key, repo: $repo, vcs: $vcs, base: $base, present: ($present == "yes"),
      workspace: ($workspace == "yes"), stale: ($stale == "yes"),
      uncommitted: ($uncommitted == "yes"), commits: $commits, lag: $lag,
      unpublished: $unpublished, merged: $merged, pr: (if $pr == "" then null else $pr end),
      bookmark: $bookmark, at_base: ($at_base == "yes"),
      unsupported: (if $unsupported == "" then null else $unsupported end),
      error: (if $error == "" then null else $error end)}'
}

member_state_line() {
  local line="$1/$2: "
  if [ -n "$S_ERROR" ]; then
    printf '%serror: %s\n' "$line" "$S_ERROR"
    return
  fi
  if [ "$S_PRESENT" = no ]; then
    printf '%smissing directory (workspace %s); run '\''%s prune'\''\n' "$line" "$S_WORKSPACE" "$SCRIPT_NAME"
    return
  fi
  line+="commits=$S_COMMITS lag=$S_LAG uncommitted=$S_UNCOMMITTED unpublished=$S_UNPUBLISHED merged=$S_MERGED bookmark=$S_BOOKMARK"
  [ "$S_STALE" = no ] || line+=" STALE"
  [ -z "$S_PR" ] || line+=" pr=$S_PR"
  [ -z "$S_UNSUPPORTED" ] || line+=" UNSUPPORTED($S_UNSUPPORTED)"
  printf '%s\n' "$line"
}

all_keys() {
  local m
  for m in worktree/*/worktree.json; do
    [ -f "$m" ] || continue
    m=${m#worktree/}
    m=${m%/worktree.json}
    if [[ $m =~ $KEY_RE ]]; then printf '%s\n' "$m"; fi
  done
}

cmd_status() {
  local key='' remote=false json=false k r
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --remote) remote=true ;;
      --json) json=true ;;
      -*) usage_error "unknown option $1" ;;
      *) [ -z "$key" ] || usage_error "unexpected argument $1"; key=$1 ;;
    esac
    shift
  done
  local -a keys=()
  if [ -n "$key" ]; then
    validate_key "$key"
    manifest_require "$key"
    keys=("$key")
  else
    mapfile -t keys < <(all_keys)
  fi
  local -a objs=()
  for k in "${keys[@]}"; do
    while IFS= read -r r; do
      member_state "$k" "$r" "$remote"
      if [ "$json" = true ]; then
        objs+=("$(member_state_json "$k" "$r")")
      else
        member_state_line "$k" "$r"
      fi
    done < <(manifest_members "$k")
  done
  if [ "$json" = true ]; then
    if [ "${#objs[@]}" -eq 0 ]; then echo '[]'; else printf '%s\n' "${objs[@]}" | jq -s .; fi
  fi
}

# ---------------------------------------------------------------------------
# drop / remove

# remove_members <key> <force> <delete_bookmarks> <repo>...
remove_members() {
  local key=$1 force=$2 delete_bookmarks=$3
  shift 3
  local r repo dest
  local -a offenders=() errors=()
  declare -A at_base_of=() merged_of=() present_of=() ws_of=() error_of=() dirty_of=() seen=()

  for r in "$@"; do
    if [ -n "${seen[$r]:-}" ]; then errors+=("$r: listed twice"); continue; fi
    seen[$r]=1
    [ -n "$(manifest_get "$key" "$r" vcs)" ] || errors+=("$r: not a member of '$key'")
  done
  if [ "${#errors[@]}" -gt 0 ]; then
    printf '  %s\n' "${errors[@]}" >&2
    refuse "nothing was removed"
  fi

  for r in "$@"; do
    member_state "$key" "$r"
    if [ "$S_STALE" = yes ]; then
      dest=$(member_dir "$key" "$r")
      run "${JJ[@]}" -R "$dest" workspace update-stale || warn "$r: update-stale failed"
      [ "$DRY_RUN" = true ] || member_state "$key" "$r"
    fi
    [ -z "$S_ERROR" ] || errors+=("$r: $S_ERROR")
    error_of[$r]=$S_ERROR
    present_of[$r]=$S_PRESENT
    ws_of[$r]=$S_WORKSPACE
    at_base_of[$r]=$S_AT_BASE
    merged_of[$r]=$S_MERGED
    dirty_of[$r]=$S_UNCOMMITTED
    if [ "$S_PRESENT" = yes ] && { [ "$S_UNCOMMITTED" = yes ] || [ "$S_UNPUBLISHED" -gt 0 ]; }; then
      offenders+=("$r: uncommitted=$S_UNCOMMITTED unpublished=$S_UNPUBLISHED")
    fi
  done
  if [ "${#errors[@]}" -gt 0 ] && [ "$force" = false ]; then
    printf '  %s\n' "${errors[@]}" >&2
    refuse "unable to inspect every member; fix the errors or use --force"
  fi
  if [ "${#offenders[@]}" -gt 0 ] && [ "$force" = false ]; then
    printf '  %s\n' "${offenders[@]}" >&2
    refuse "work would be left behind; commit and push it, or pass --force (jj keeps it as a commit, Git-only members stash it)"
  fi

  for r in "$@"; do
    repo=$(repo_dir "$r")
    dest=$(member_dir "$key" "$r")
    if [ "$(manifest_get "$key" "$r" vcs)" = jj ]; then
      if [ "${present_of[$r]}" = yes ] && [ "${ws_of[$r]}" = yes ]; then
        run "${JJ[@]}" -R "$repo" workspace remove "$key" || die "$r: 'jj workspace remove' failed"
      elif [ "${ws_of[$r]}" = yes ]; then
        run "${JJ[@]}" -R "$repo" workspace forget "$key" || die "$r: 'jj workspace forget' failed"
      elif [ "${present_of[$r]}" = yes ]; then
        warn "$r: $dest exists but jj has no workspace '$key'; leaving the directory in place"
      fi
    else
      if [ "${present_of[$r]}" = yes ]; then
        if [ "${dirty_of[$r]}" = yes ]; then
          # Only reachable with --force: keep the work in the shared stash.
          run git -C "$dest" stash push --include-untracked -m "$SCRIPT_NAME remove $key" ||
            die "$r: unable to stash uncommitted work; nothing removed for this member"
          info "$r: uncommitted work stashed; see 'git -C $repo stash list'"
        fi
        run git -C "$repo" worktree remove --force "$ROOT/$dest" || die "$r: 'git worktree remove' failed"
      fi
    fi
    prune_set_worktree_entries "$repo"

    if [ "$delete_bookmarks" = true ]; then
      if [ -n "${error_of[$r]}" ]; then
        warn "$r: keeping branch $key because its state is unknown (${error_of[$r]})"
      elif [ "${at_base_of[$r]}" = yes ] || [ "${merged_of[$r]}" != no ]; then
        if [ "$(manifest_get "$key" "$r" vcs)" = jj ]; then
          if [ "$(jj_count "$repo" "bookmarks(exact:\"$key\")")" -gt 0 ]; then
            run "${JJ[@]}" -R "$repo" --ignore-working-copy bookmark forget "exact:$key" ||
              warn "$r: unable to forget bookmark $key"
          fi
        elif git -C "$repo" show-ref --verify --quiet "refs/heads/$key"; then
          run git -C "$repo" branch -D "$key" || warn "$r: unable to delete branch $key"
        fi
      else
        warn "$r: keeping branch $key: it has commits that no upstream branch contains (a rebase or squash merge looks like this too; check the PR, then 'jj bookmark forget $key' in $repo)"
      fi
    fi
    if [ "$DRY_RUN" = false ]; then manifest_del_member "$key" "$r"; fi
    info "$r: removed from $key"
  done
}

parse_remove_opts() {
  R_FORCE=false; R_DELETE_BOOKMARKS=false; R_ARCHIVE=false; R_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force) R_FORCE=true ;;
      --delete-bookmarks) R_DELETE_BOOKMARKS=true ;;
      --archive) R_ARCHIVE=true ;;
      -n|--dry-run) DRY_RUN=true ;;
      -*) usage_error "unknown option $1" ;;
      *) R_ARGS+=("$1") ;;
    esac
    shift
  done
}

cmd_drop() {
  parse_remove_opts "$@"
  [ "$R_ARCHIVE" = false ] || usage_error "--archive is only valid for remove"
  [ "${#R_ARGS[@]}" -ge 2 ] || usage_error "usage: drop <key> <repo>..."
  local key=${R_ARGS[0]}
  validate_key "$key"
  manifest_require "$key"
  [ "$DRY_RUN" = true ] || lock_set "$key"
  remove_members "$key" "$R_FORCE" "$R_DELETE_BOOKMARKS" "${R_ARGS[@]:1}"
}

cmd_remove() {
  parse_remove_opts "$@"
  [ "${#R_ARGS[@]}" -eq 1 ] || usage_error "usage: remove <key>"
  local key=${R_ARGS[0]} set_path issue
  local -a members=()
  validate_key "$key"
  manifest_require "$key"
  set_path=$(set_dir "$key")
  [ "$DRY_RUN" = true ] || lock_set "$key"
  local snapshot=''
  if [ "$R_ARCHIVE" = true ] && [ "$DRY_RUN" = false ]; then
    snapshot=$(mktemp)
    cp "$(manifest_path "$key")" "$snapshot"
  fi
  mapfile -t members < <(manifest_members "$key")
  if [ "${#members[@]}" -gt 0 ]; then
    remove_members "$key" "$R_FORCE" "$R_DELETE_BOOKMARKS" "${members[@]}"
  fi
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] remove $(manifest_path "$key") and $set_path"
    return 0
  fi
  if [ "$R_ARCHIVE" = true ]; then
    issue=$(issue_of_key "$key")
    if [ -n "$issue" ]; then
      local -a matches=()
      shopt -s nullglob
      matches=(ticket/*-"$issue"-*/)
      shopt -u nullglob
      if [ "${#matches[@]}" -eq 1 ]; then
        cp "$snapshot" "${matches[0]}worktree-$key.json"
        info "Archived manifest to ${matches[0]}worktree-$key.json"
      else
        warn "archive skipped: ${#matches[@]} ticket directories match issue $issue"
      fi
    else
      warn "archive skipped: '$key' is not bound to an issue"
    fi
    rm -f "$snapshot"
  fi
  rm -f "$(manifest_path "$key")" "$set_path/.lock"
  if rmdir "$set_path" 2>/dev/null; then
    info "Removed worktree set $key"
  else
    warn "$set_path still holds files that belong to no member; show them to the user before deleting them by hand:"
    ls -A "$set_path" >&2
  fi
}

# ---------------------------------------------------------------------------
# list / path / bookmark

cmd_list() {
  local json=false k
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=true ;;
      *) usage_error "unexpected argument $1" ;;
    esac
    shift
  done
  local -a manifests=()
  for k in $(all_keys); do manifests+=("$(manifest_path "$k")"); done
  if [ "$json" = true ]; then
    if [ "${#manifests[@]}" -eq 0 ]; then echo '[]'; else jq -s . "${manifests[@]}"; fi
    return 0
  fi
  for k in "${manifests[@]}"; do
    jq -r '"\(.key)\tissue=\(.issue // "-")\t" + ([.repos | to_entries[] | "\(.key)(\(.value.base))"] | join(" "))' "$k"
  done
}

cmd_path() {
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage_error "usage: path <key> [<repo>]"
  validate_key "$1"
  manifest_require "$1"
  if [ "$#" -eq 2 ]; then
    [ -n "$(manifest_get "$1" "$2" vcs)" ] || refuse "$2 is not a member of '$1'"
    printf '%s/%s\n' "$ROOT" "$(member_dir "$1" "$2")"
  else
    printf '%s/%s\n' "$ROOT" "$(set_dir "$1")"
  fi
}

cmd_bookmark() {
  [ "$#" -ge 1 ] || usage_error "usage: bookmark <key> [<repo>...]"
  local key=$1 r rc=0
  shift
  validate_key "$key"
  manifest_require "$key"
  lock_set "$key"
  local -a members=("$@")
  [ "${#members[@]}" -gt 0 ] || mapfile -t members < <(manifest_members "$key")
  for r in "${members[@]}"; do
    case "$(manifest_get "$key" "$r" vcs)" in
      jj) run "${JJ[@]}" -R "$(member_dir "$key" "$r")" bookmark advance "$key" --to @- || {
            warn "$r: unable to advance $key"; rc=$EXIT_REFUSED; } ;;
      git) info "$r: Git branches follow commits; nothing to do" ;;
      *) warn "$r: not a member of '$key'"; rc=$EXIT_REFUSED ;;
    esac
  done
  return "$rc"
}

# ---------------------------------------------------------------------------
# prune

cmd_prune() {
  local apply=false issues=0 r repo name root rel k member key_part out
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply) apply=true ;;
      *) usage_error "unexpected argument $1" ;;
    esac
    shift
  done
  [ "$apply" = true ] || DRY_RUN=true

  # Manifest members whose directory is gone. Each set is locked while it is
  # repaired; a busy set is skipped.
  for k in $(all_keys); do
    if [ "$apply" = true ] && ! try_lock_set "$k"; then
      warn "$k: busy (another $SCRIPT_NAME run holds it); skipped"
      issues=$((issues + 1))
      continue
    fi
    while IFS= read -r member; do
      repo=$(repo_dir "$member")
      local present=yes ws=yes vcs
      vcs=$(manifest_get "$k" "$member" vcs)
      [ -d "$(member_dir "$k" "$member")" ] || present=no
      if [ ! -e "$repo/.git" ]; then
        ws=no
      elif [ "$vcs" = jj ]; then
        jj_workspace_exists "$repo" "$k" || ws=no
      fi
      if [ "$present" = no ]; then
        issues=$((issues + 1))
        warn "$k/$member: directory is gone (workspace: $ws)"
        if [ "$vcs" = jj ] && [ "$ws" = yes ]; then
          run "${JJ[@]}" -R "$repo" --ignore-working-copy workspace forget "$k" ||
            { warn "$k/$member: 'jj workspace forget' failed; member kept"; continue; }
        fi
        if [ -e "$repo/.git" ]; then prune_set_worktree_entries "$repo"; fi
        if [ "$apply" = true ]; then
          manifest_del_member "$k" "$member"
          info "$k/$member: dropped from manifest"
        fi
      elif [ "$vcs" = jj ] && [ "$ws" = no ]; then
        issues=$((issues + 1))
        warn "$k/$member: directory exists but the repository has no workspace '$k'; show it to the user"
      fi
    done < <(manifest_members "$k")
  done

  # Directories under worktree/ without a manifest.
  for root in worktree/*/; do
    [ -d "$root" ] || continue
    if [ ! -f "${root}worktree.json" ]; then
      issues=$((issues + 1))
      warn "${root%/}: directory without worktree.json; show it to the user"
    fi
  done

  # jj workspaces rooted under worktree/ that no manifest lists, and Git
  # worktree metadata for member directories under worktree/ that are gone.
  while IFS= read -r r; do
    repo=$(repo_dir "$r")
    if [ -d "$repo/.jj" ] && command -v jj >/dev/null 2>&1; then
      if ! out=$(jjq "$repo" workspace list -T 'name ++ "\t" ++ root ++ "\n"' 2>&1); then
        issues=$((issues + 1))
        warn "$r: unable to list jj workspaces: ${out%%$'\n'*}"
      else
        while IFS=$'\t' read -r name root; do
          case "$root" in
            "$ROOT/worktree/"*) ;;
            *) continue ;;
          esac
          rel=${root#"$ROOT/worktree/"}
          key_part=${rel%%/*}
          member=${rel#*/}
          if [ ! -f "$(manifest_path "$key_part")" ] ||
            [ -z "$(manifest_get "$key_part" "$member" vcs)" ] || [ "$name" != "$key_part" ]; then
            issues=$((issues + 1))
            warn "$r: jj workspace '$name' at worktree/$rel is not listed in any manifest; show it to the user"
          fi
        done <<<"$out"
      fi
    fi
    PRUNED_ENTRIES=0
    prune_set_worktree_entries "$repo"
    if [ "$PRUNED_ENTRIES" -gt 0 ]; then
      issues=$((issues + 1))
      warn "$r: $PRUNED_ENTRIES Git worktree entr(y/ies) under worktree/ point to missing directories"
    fi
  done < <(all_repos)

  if [ "$issues" -eq 0 ]; then
    info "No drift found"
  elif [ "$apply" = false ]; then
    info "$issues issue(s) found; rerun with --apply to fix the fixable ones"
  fi
}

# ---------------------------------------------------------------------------
# repos

fix_hint() {
  local r=$1 repo trunk
  repo=$(repo_dir "$r")
  if [ -d "$repo/.jj" ] && command -v jj >/dev/null 2>&1; then
    jjq "$repo" log --no-graph --limit 1 -r "::trunk() & description(substring:\"$FIX_ISSUE_REF\")" \
      -T 'commit_id.short()' 2>/dev/null || true
  elif trunk=$(git_trunk_ref "$r"); then
    git -C "$repo" log -1 --format=%h --grep "$FIX_ISSUE_REF" --fixed-strings "$trunk" 2>/dev/null || true
  fi
}

cmd_repos() {
  local json=false r reason hint
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=true ;;
      *) usage_error "unexpected argument $1" ;;
    esac
    shift
  done
  local -a objs=()
  while IFS= read -r r; do
    reason=${UNSUPPORTED[$r]:-}
    hint=''
    [ -z "$reason" ] || hint=$(fix_hint "$r")
    if [ "$json" = true ]; then
      objs+=("$(jq -n --arg repo "$r" --arg reason "$reason" --arg hint "$hint" \
        '{repo: $repo, supported: ($reason == ""), reason: (if $reason == "" then null else $reason end),
          fix_commit_on_trunk: (if $hint == "" then null else $hint end)}')")
    elif [ -z "$reason" ]; then
      printf '%s\tsupported\n' "$r"
    else
      printf '%s\tunsupported\t%s' "$r" "$reason"
      [ -z "$hint" ] || printf '\t(trunk has %s referencing %s; verify and update the table in %s)' "$hint" "$FIX_ISSUE_REF" "scripts/$SCRIPT_NAME"
      printf '\n'
    fi
  done < <(all_repos)
  if [ "$json" = true ]; then
    if [ "${#objs[@]}" -eq 0 ]; then echo '[]'; else printf '%s\n' "${objs[@]}" | jq -s .; fi
  fi
}

# ---------------------------------------------------------------------------

main() {
  [ "$#" -gt 0 ] || { usage; exit "$EXIT_ARG"; }
  local sub=$1
  shift
  case "$sub" in
    -h|--help|help) usage; exit "$EXIT_OK" ;;
  esac
  local tool
  for tool in git jq flock; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
  done
  ROOT=$(find_workspace_root) || die "Longhorn workspace root not found"
  cd "$ROOT"
  case "$sub" in
    key) cmd_key "$@" ;;
    create) cmd_create_or_add create "$@" ;;
    add) cmd_create_or_add add "$@" ;;
    drop) cmd_drop "$@" ;;
    remove) cmd_remove "$@" ;;
    list) cmd_list "$@" ;;
    status) cmd_status "$@" ;;
    bookmark) cmd_bookmark "$@" ;;
    path) cmd_path "$@" ;;
    prune) cmd_prune "$@" ;;
    repos) cmd_repos "$@" ;;
    *) usage_error "unknown subcommand '$sub'" ;;
  esac
}

main "$@"
