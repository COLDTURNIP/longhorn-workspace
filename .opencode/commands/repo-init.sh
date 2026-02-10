#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Default to execute mode unless explicitly overridden
DRY_RUN=${DRY_RUN:-false}
JSON_OUTPUT=${JSON_OUTPUT:-false}

source "$SCRIPT_DIR/../skills/lib/defensive_prelude.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Clone all repositories listed in repo/repo-list from upstream and keep only a local 'upstream' branch.

Options:
  --json              Emit JSON summary to stdout only (silences human logs on stdout)
  --json-log          Deprecated alias for --json
  --execute           Perform network and filesystem actions (default)
  --no-color          Disable color output (not used in this script)
  -n, --dry-run       Dry-run mode (no changes)
  -h, --help          Show this help
USAGE
}

# Pre-process custom flags before invoking defensive parser
JSON_STDOUT_FD=1
LEGACY_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json|--json-log)
      JSON_OUTPUT=true
      ;;
    *)
      LEGACY_ARGS+=("$1")
      ;;
  esac
  shift || true
done
set -- "${LEGACY_ARGS[@]}"

defensive_parse_args "$@"

if [ "$JSON_OUTPUT" = true ]; then
  JSON_LOG=true
  exec 3>&1
  exec 1>&2
  JSON_STDOUT_FD=3
fi

if [ "$DRY_RUN" = false ]; then
  defensive_record_safety_ref
fi

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "repo-init does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

REPO_LIST="repo/repo-list"
REPO_DIR="repo"

if ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
    warn "refs/remotes/upstream/HEAD not found; continuing without upstream tracking"
fi

detect_local_default_branch() {
    local repo_label=$1 branch=""

    branch=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)
    if [ -n "$branch" ]; then
        echo "$branch"
        return 0
    fi

    branch=$(git branch --show-current 2>/dev/null || true)
    if [ -n "$branch" ]; then
        echo "$branch"
        return 0
    fi

    error "Unable to determine local default branch for ${repo_label:-repository}"
    return 1
}

if [ ! -f "$REPO_LIST" ]; then
    die "$REPO_LIST not found. Run repo-init from workspace root."
fi

info "Dry-run mode: $DRY_RUN"

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
    local dq='"'
    local dq_escaped='\"'
    value=${value//\/\\}
    value=${value//${dq}/${dq_escaped}}
    value=${value//$'\n'/\n}
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
    local upstream_url default_branch

    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Preparing to clone $entry from upstream"
        info "[DRY-RUN] git clone \"https://github.com/${account}/${reponame}.git\" \"$target_path\" --origin upstream"
        info "[DRY-RUN] cd \"$target_path\" && detect local default branch"
        info "[DRY-RUN] cd \"$target_path\" && git branch -m <default-branch> upstream"
        write_result "$result_file" "dry-run" "$entry" "planned"
        return 0
    fi

    upstream_url="https://github.com/${account}/${reponame}.git"
    if ! run_cmd "git clone \"$upstream_url\" \"$target_path\" --origin upstream"; then
        write_result "$result_file" "failed" "$entry" "git clone failed"
        return 1
    fi

    local subshell_rc
    (
        cd "$target_path"
        default_branch=$(detect_local_default_branch "$entry") || exit 2
        info "Detected local default branch: $default_branch"
        if [ "$default_branch" != "upstream" ]; then
            if ! run_cmd "git branch -m \"$default_branch\" upstream"; then
                exit 3
            fi
        fi

        if ! git show-ref --verify --quiet refs/heads/upstream; then
            exit 4
        fi
    )
    subshell_rc=$?
    if [ "$subshell_rc" -ne 0 ]; then
        case "$subshell_rc" in
            2) write_result "$result_file" "failed" "$entry" "unable to detect local default branch" ;;
            3) write_result "$result_file" "failed" "$entry" "unable to rename default branch to upstream" ;;
            4) write_result "$result_file" "failed" "$entry" "upstream branch missing after rename" ;;
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
    JSON_SEP=','
done

human_summary() {
    printf 'Summary counts: success=%s skipped=%s dry-run=%s failed=%s\n' \
        "$SUCCESS_COUNT" "$SKIP_COUNT" "$DRY_COUNT" "$FAIL_COUNT"
    if [ "$WAIT_FAIL_COUNT" -gt 0 ]; then
        printf 'Subprocess wait failures detected: %s\n' "$WAIT_FAIL_COUNT"
    fi
}

if [ "$JSON_OUTPUT" = true ]; then
    printf '{"summary":{"success":%s,"skipped":%s,"dry_run":%s,"failed":%s},"results":[%s],"wait_failures":%s}\n' \
        "$SUCCESS_COUNT" "$SKIP_COUNT" "$DRY_COUNT" "$FAIL_COUNT" "$JSON_ITEMS" "$WAIT_FAIL_COUNT" >&"$JSON_STDOUT_FD"
else
    human_summary
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit "$EXIT_ENV"
fi

info "=== All repositories processed ==="
