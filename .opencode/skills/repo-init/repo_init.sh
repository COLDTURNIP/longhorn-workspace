#!/usr/bin/env bash
# Usage: ./repo_init.sh [--execute] [--force] [--json-log] [--no-color]
# Batch clone and initialize all repos from repo/repo-list, supporting 'account/repo_name' format, only keep local 'upstream' branch

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Clone all repositories listed in repo/repo-list from upstream and keep only a local 'upstream' branch.

Options:
  --execute           Perform network and filesystem actions (default dry-run)
  --force             Permit destructive cleanup (branch deletions)
  --json-log          Emit JSON log lines
  --no-color          Disable color output (not used in this script)
  -n, --dry-run       Dry-run mode (default)
  -h, --help          Show this help
USAGE
}

defensive_parse_args "$@"

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "repo-init does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

REPO_LIST="repo/repo-list"
REPO_DIR="repo"

defensive_require_clean_tree
if ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
    warn "refs/remotes/upstream/HEAD not found; continuing without upstream tracking"
fi
defensive_record_safety_ref

if [ ! -f "$REPO_LIST" ]; then
    die "$REPO_LIST not found. Run repo-init from workspace root."
fi

info "Dry-run mode: $DRY_RUN"
info "Force mode: $FORCE"

while IFS= read -r ENTRY || [ -n "$ENTRY" ]; do
    ENTRY="$(echo "$ENTRY" | xargs)"
    [[ -z "$ENTRY" || "$ENTRY" =~ ^# ]] && continue

    if [[ ! "$ENTRY" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
        warn "Skip invalid format: '$ENTRY' (expect account/repo_name)"
        continue
    fi

    account="${ENTRY%%/*}"
    reponame="${ENTRY##*/}"
    TARGET_PATH="${REPO_DIR}/${reponame}"

    if [ -d "$TARGET_PATH/.git" ]; then
        warn "[SKIP] $ENTRY already exists at $TARGET_PATH"
        continue
    fi

    info "[ACTION] Preparing to clone $ENTRY from upstream"
    UPSTREAM_URL="https://github.com/${account}/${reponame}.git"
    defensive_run_cmd "git clone \"$UPSTREAM_URL\" \"$TARGET_PATH\" --origin upstream"

    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] cd \"$TARGET_PATH\" && detect upstream default branch"
        info "[DRY-RUN] cd \"$TARGET_PATH\" && git switch -c upstream upstream/<branch>"
        info "[DRY-RUN] cd \"$TARGET_PATH\" && delete non-upstream branches (requires --force during execute)"
    else
        (
            cd "$TARGET_PATH"
            MAIN_BRANCH=$(git remote show upstream | grep 'HEAD branch' | awk '{print $5}')
            info "Detected upstream default branch: $MAIN_BRANCH"
            defensive_run_cmd "git switch -c upstream \"upstream/$MAIN_BRANCH\""

            defensive_require_force "delete extra local branches in $TARGET_PATH"
            for branch in $(git branch --format='%(refname:short)'); do
                if [ "$branch" != "upstream" ]; then
                    defensive_run_cmd "git branch -D \"$branch\""
                fi
            done
        )
    fi

    info "[DONE] $ENTRY processed"
done < "$REPO_LIST"

info "=== All repositories processed ==="
