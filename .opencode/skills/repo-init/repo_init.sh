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

detect_upstream_default_branch() {
    local repo_label=$1 branch=""

    branch=$(git symbolic-ref -q refs/remotes/upstream/HEAD 2>/dev/null || true)
    if [ -n "$branch" ]; then
        echo "${branch##*/}"
        return 0
    fi

    warn "Unable to read upstream HEAD via 'git remote show'; trying git remote set-head --auto" >&2
    if git remote set-head upstream --auto >/dev/null 2>&1; then
        branch=$(git symbolic-ref -q refs/remotes/upstream/HEAD 2>/dev/null || true)
        if [ -n "$branch" ]; then
            echo "${branch##*/}"
            return 0
        fi
    fi

    while IFS= read -r marker refname target; do
        if [ "$marker" = "ref:" ] && [ -n "$refname" ]; then
            branch=${refname#refs/heads/}
            echo "$branch"
            return 0
        fi
    done < <(git ls-remote --symref upstream HEAD 2>/dev/null || true)

    error "Unable to determine upstream default branch for ${repo_label:-repository}; set it manually with 'git remote set-head upstream --auto'"
    return 1
}

if [ ! -f "$REPO_LIST" ]; then
    die "$REPO_LIST not found. Run repo-init from workspace root."
fi

info "Dry-run mode: $DRY_RUN"
info "Force mode: $FORCE"

RESULT_DIR=$(mktemp -d)
cleanup_results() {
    rm -rf "$RESULT_DIR"
}
trap cleanup_results EXIT

write_result() {
    local result_file=$1 status=$2 entry=$3 message=$4
    printf '%s|%s|%s\n' "$status" "$entry" "$message" > "$result_file"
}

trim_line() {
    local value=$1
    value="${value#"${value%%[!$' \t']*}"}"
    value="${value%"${value##*[!$' \t']}"}"
    printf '%s' "$value"
}

json_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

run_cmd() {
    local cmd=$1 rc
    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] $cmd"
        return 0
    fi
    info "[EXEC] $cmd"
    set +e
    eval "$cmd"
    rc=$?
    set -e
    return "$rc"
}

init_repo() {
    local entry=$1 account=$2 reponame=$3 target_path=$4 result_file=$5
    local upstream_url main_branch

    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Preparing to clone $entry from upstream"
        info "[DRY-RUN] git clone \"https://github.com/${account}/${reponame}.git\" \"$target_path\" --origin upstream"
        info "[DRY-RUN] cd \"$target_path\" && detect upstream default branch"
        info "[DRY-RUN] cd \"$target_path\" && git switch -c upstream upstream/<branch>"
        info "[DRY-RUN] cd \"$target_path\" && delete non-upstream branches (requires --force during execute)"
        write_result "$result_file" "dry-run" "$entry" "planned"
        return 0
    fi

    upstream_url="https://github.com/${account}/${reponame}.git"
    if ! run_cmd "git clone \"$upstream_url\" \"$target_path\" --origin upstream"; then
        write_result "$result_file" "failed" "$entry" "git clone failed"
        return 1
    fi

    if ! (
        cd "$target_path"
        main_branch=$(detect_upstream_default_branch "$entry") || exit 2
        info "Detected upstream default branch: $main_branch"
        git remote set-head upstream "$main_branch" >/dev/null 2>&1 || warn "Unable to set upstream HEAD explicitly for $entry"
        if ! run_cmd "git switch -c upstream \"upstream/$main_branch\""; then
            exit 3
        fi

        if [ "$FORCE" = false ]; then
            exit 4
        fi

        while IFS= read -r branch; do
            branch=${branch##*/}
            if [ "$branch" != "upstream" ]; then
                if ! run_cmd "git branch -D \"$branch\""; then
                    exit 5
                fi
            fi
        done < <(git branch --format='%(refname:short)')
    ); then
        case $? in
            2) write_result "$result_file" "failed" "$entry" "unable to detect upstream default branch" ;;
            3) write_result "$result_file" "failed" "$entry" "unable to create upstream branch" ;;
            4) write_result "$result_file" "failed" "$entry" "refusing to delete branches without --force" ;;
            5) write_result "$result_file" "failed" "$entry" "failed to delete extra branches" ;;
            *) write_result "$result_file" "failed" "$entry" "unexpected failure" ;;
        esac
        return 1
    fi

    write_result "$result_file" "success" "$entry" "initialized"
    return 0
}

PIDS=()
RESULT_FILES=()
INDEX=0

while IFS= read -r ENTRY || [ -n "$ENTRY" ]; do
    ENTRY="$(trim_line "$ENTRY")"
    [[ -z "$ENTRY" || "$ENTRY" =~ ^# ]] && continue

    if [[ ! "$ENTRY" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
        warn "Skip invalid format: '$ENTRY' (expect account/repo_name)"
        continue
    fi

    account="${ENTRY%%/*}"
    reponame="${ENTRY##*/}"
    TARGET_PATH="${REPO_DIR}/${reponame}"
    RESULT_FILE="${RESULT_DIR}/result_${INDEX}.txt"
    INDEX=$((INDEX + 1))
    RESULT_FILES+=("$RESULT_FILE")
    if [ -d "$TARGET_PATH/.git" ]; then
        warn "[SKIP] $ENTRY already exists at $TARGET_PATH"
        write_result "$RESULT_FILE" "skipped" "$ENTRY" "already exists"
        continue
    fi

    init_repo "$ENTRY" "$account" "$reponame" "$TARGET_PATH" "$RESULT_FILE" &
    PIDS+=("$!")
done < "$REPO_LIST"

WAIT_FAIL_COUNT=0
for pid in "${PIDS[@]}"; do
    if ! wait "$pid"; then
        WAIT_FAIL_COUNT=$((WAIT_FAIL_COUNT + 1))
    fi
done

info "=== Repository initialization summary ==="
SUCCESS_COUNT=0
SKIP_COUNT=0
DRY_COUNT=0
FAIL_COUNT=0
JSON_ITEMS=""
JSON_SEP=""
for result_file in "${RESULT_FILES[@]}"; do
    if [ ! -f "$result_file" ]; then
        status="failed"
        entry="<unknown>"
        message="missing result file"
    else
        IFS='|' read -r status entry message < "$result_file"
    fi
    case "$status" in
        success) SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) ;;
        skipped) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        dry-run) DRY_COUNT=$((DRY_COUNT + 1)) ;;
        failed) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        *) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
    if [ "$status" = "failed" ]; then
        warn "[RESULT] $entry: $status ($message)"
    else
        info "[RESULT] $entry: $status ($message)"
    fi
    json_entry=$(json_escape "$entry")
    json_status=$(json_escape "$status")
    json_message=$(json_escape "$message")
    JSON_ITEMS="${JSON_ITEMS}${JSON_SEP}{\"repo\":\"$json_entry\",\"status\":\"$json_status\",\"message\":\"$json_message\"}"
    JSON_SEP=","
done

info "=== Summary counts: success=$SUCCESS_COUNT skipped=$SKIP_COUNT dry-run=$DRY_COUNT failed=$FAIL_COUNT ==="
if [ "$WAIT_FAIL_COUNT" -gt 0 ]; then
    warn "Subprocess wait failures detected: $WAIT_FAIL_COUNT"
fi

printf '{"summary":{"success":%s,"skipped":%s,"dry_run":%s,"failed":%s},"results":[%s]}\n' \
    "$SUCCESS_COUNT" "$SKIP_COUNT" "$DRY_COUNT" "$FAIL_COUNT" "$JSON_ITEMS"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit "$EXIT_ENV"
fi

info "=== All repositories processed ==="
