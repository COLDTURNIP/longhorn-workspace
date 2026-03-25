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

Clone all repositories listed in repo/repo-list.json.
Each key is the target relative path under repo/, and each value defines:
  - upstream: required full git URL
  - origin: optional full git URL personal fork

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

REPO_LIST="repo/repo-list.json"
REPO_DIR="repo"

detect_upstream_trunk_branch() {
    local has_main=false has_master=false
    local ls_remote_output line ref

    if git show-ref --verify --quiet refs/remotes/upstream/main; then
        has_main=true
    fi
    if git show-ref --verify --quiet refs/remotes/upstream/master; then
        has_master=true
    fi

    if [ "$has_main" = true ]; then
        printf 'main\n'
        return 0
    fi
    if [ "$has_master" = true ]; then
        printf 'master\n'
        return 0
    fi

    ls_remote_output=$(git ls-remote --heads upstream main master 2>/dev/null || true)
    if [ -n "$ls_remote_output" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            ref=${line#*refs/heads/}
            case "$ref" in
                main)
                    has_main=true
                    ;;
                master)
                    has_master=true
                    ;;
            esac
        done <<< "$ls_remote_output"
    fi

    if [ "$has_main" = true ]; then
        printf 'main\n'
        return 0
    fi
    if [ "$has_master" = true ]; then
        printf 'master\n'
        return 0
    fi

    return 1
}

jj_track_bookmark_remote() {
    local bookmark_name=$1 remote_name=$2

    if run_cmd "jj bookmark track \"$bookmark_name\" --remote=\"$remote_name\""; then
        return 0
    fi

    run_cmd "jj bookmark track \"${bookmark_name}@${remote_name}\""
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
    local trunk_branch=${5:-}
    local origin_tracking=${6:-}
    local main_bookmark_state=${7:-}
    printf '%s|%s|%s|%s|%s|%s\n' \
        "$status" "$entry" "$message" "$trunk_branch" "$origin_tracking" "$main_bookmark_state" > "$result_file"
}

trim_line() {
    local value=$1
    value="${value#"${value%%[!$' \t']*}"}"
    value="${value%"${value##*[!$' \t']}"}"
    printf '%s' "$value"
}

parse_repo_list_json() {
    local source_file=$1 output_file=$2
    local tmp_tsv

    if ! command -v jq >/dev/null 2>&1; then
        die "jq is required to parse $source_file"
    fi

    tmp_tsv="${output_file}.tsv"

    if ! jq -er '
      def repo_url_ok:
        test("^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+\\.git$") or
        test("^git@[^[:space:]:]+:[^[:space:]]+\\.git$");
      def path_ok:
        test("^[A-Za-z0-9._/-]+$") and
        (startswith("/") | not) and
        (endswith("/") | not) and
        (. != ".") and
        (. != "..") and
        (test("(^|/)\\.\\.($|/)") | not) and
        (test("//") | not);
      if type != "object" then error("top-level must be an object") else . end
      | to_entries[]
      | .key as $path
      | .value as $cfg
      | if ($cfg|type) != "object" then error("entry '\''\($path)'\'' must be an object") else . end
      | if ($path|path_ok|not) then error("invalid repo path key '\''\($path)'\''") else . end
      | if (($cfg|has("upstream"))|not) then error("missing upstream for '\''\($path)'\''") else . end
      | if (($cfg.upstream|type) != "string") or (($cfg.upstream|repo_url_ok)|not)
        then error("invalid upstream repo URL for '\''\($path)'\'': '\''\($cfg.upstream|tostring)'\''")
        else .
        end
      | if (($cfg|has("origin")) and (((($cfg.origin|type) != "string") or (($cfg.origin|repo_url_ok)|not))))
        then error("invalid origin repo URL for '\''\($path)'\'': '\''\($cfg.origin|tostring)'\''")
        else .
        end
      | [$path, $cfg.upstream, ($cfg.origin // "")]
      | @tsv
    ' "$source_file" > "$tmp_tsv"; then
        die "Invalid repository definition file: $source_file"
    fi

    if [ ! -s "$tmp_tsv" ]; then
        die "$source_file has no valid repository entries"
    fi

    : > "$output_file"
    while IFS=$'\t' read -r repo_path upstream_repo origin_repo || [ -n "$repo_path" ]; do
        printf '%s|%s|%s\n' "$repo_path" "$upstream_repo" "$origin_repo" >> "$output_file"
    done < "$tmp_tsv"

    rm -f "$tmp_tsv"
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
    local entry=$1 upstream_repo_url=$2 origin_repo_url=$3 target_path=$4 result_file=$5 existing_repo=$6
    local upstream_url origin_url upstream_trunk summary_message
    local has_origin_remote=false has_main_bookmark=false
    local dry_origin_tracking dry_main_bookmark_state
    local metadata_file metadata_line
    local result_trunk_branch result_origin_tracking result_main_bookmark_state
    local parent_dir

    upstream_url="$upstream_repo_url"
    origin_url=""
    if [ -n "$origin_repo_url" ]; then
        origin_url="$origin_repo_url"
    fi
    parent_dir=$(dirname "$target_path")

    if [ "$DRY_RUN" = true ]; then
        dry_origin_tracking="not-configured"
        if [ -n "$origin_repo_url" ]; then
            dry_origin_tracking="planned-track-if-origin-trunk-exists"
        fi
        dry_main_bookmark_state="planned-reset-to-trunk"

        if [ "$existing_repo" = true ]; then
            info "[DRY-RUN] Reconciling existing repository $entry at $target_path"
            info "[DRY-RUN] cd \"$target_path\" && git remote add upstream \"$upstream_url\" (or set-url if exists)"
        else
            info "[DRY-RUN] Preparing to clone $entry from upstream $upstream_repo_url"
            info "[DRY-RUN] mkdir -p \"$parent_dir\""
            info "[DRY-RUN] git clone \"$upstream_url\" \"$target_path\" --origin upstream"
        fi
        if [ -n "$origin_repo_url" ]; then
            info "[DRY-RUN] cd \"$target_path\" && git remote add origin \"$origin_url\" (or set-url if exists)"
        else
            info "[DRY-RUN] cd \"$target_path\" && preserve existing origin remote (if present)"
        fi
        if command -v jj >/dev/null 2>&1; then
            info "[DRY-RUN] cd \"$target_path\" && jj git init --colocate ."
            if [ -n "$origin_repo_url" ]; then
                info "[DRY-RUN] cd \"$target_path\" && jj config set --repo git.fetch '[\"upstream\",\"origin\"]'"
                info "[DRY-RUN] cd \"$target_path\" && jj config set --repo git.push origin"
            else
                info "[DRY-RUN] cd \"$target_path\" && jj config set --repo git.fetch '[\"upstream\"]'"
                info "[DRY-RUN] cd \"$target_path\" && jj config unset --repo git.push (if set)"
            fi
            info "[DRY-RUN] cd \"$target_path\" && detect upstream trunk by refs/remotes/upstream/main then master (prefer main)"
            info "[DRY-RUN] cd \"$target_path\" && jj bookmark track <trunk-branch> --remote=upstream"
            info "[DRY-RUN] cd \"$target_path\" && jj bookmark track <trunk-branch> --remote=origin (if origin remote exists)"
            info "[DRY-RUN] cd \"$target_path\" && jj config set --repo 'revset-aliases.\"trunk()\"' <upstream-default-branch>@upstream"
            info "[DRY-RUN] cd \"$target_path\" && jj bookmark set main -r trunk() --allow-backwards"
        fi
        if [ "$existing_repo" = true ]; then
            write_result "$result_file" "dry-run" "$entry" "planned remote reconciliation with main reset" \
                "auto(main>master)" "$dry_origin_tracking" "$dry_main_bookmark_state"
        else
            write_result "$result_file" "dry-run" "$entry" "planned initialization with main reset" \
                "auto(main>master)" "$dry_origin_tracking" "$dry_main_bookmark_state"
        fi
        return 0
    fi

    if [ "$existing_repo" = false ]; then
        if ! run_cmd "mkdir -p \"$parent_dir\""; then
            write_result "$result_file" "failed" "$entry" "unable to create parent directory"
            return 1
        fi

        if ! run_cmd "git clone \"$upstream_url\" \"$target_path\" --origin upstream"; then
            write_result "$result_file" "failed" "$entry" "git clone failed"
            return 1
        fi
    fi

    local subshell_rc
    metadata_file="${result_file}.meta"
    rm -f "$metadata_file"
    (
        cd "$target_path"
        result_trunk_branch=""
        result_origin_tracking="git-only"
        result_main_bookmark_state="git-only"
        if git remote get-url upstream >/dev/null 2>&1; then
            if ! run_cmd "git remote set-url upstream \"$upstream_url\""; then
                exit 13
            fi
        else
            if ! run_cmd "git remote add upstream \"$upstream_url\""; then
                exit 13
            fi
        fi

        if [ -n "$origin_repo_url" ]; then
            if git remote get-url origin >/dev/null 2>&1; then
                if ! run_cmd "git remote set-url origin \"$origin_url\""; then
                    exit 10
                fi
            else
                if ! run_cmd "git remote add origin \"$origin_url\""; then
                    exit 10
                fi
            fi

        else
            if git remote get-url origin >/dev/null 2>&1; then
                warn "[$entry] repo-list.json has no origin URL; preserving existing origin remote"
            fi
        fi

        if git remote get-url origin >/dev/null 2>&1; then
            has_origin_remote=true
        fi

        if command -v jj >/dev/null 2>&1; then
            result_origin_tracking="not-configured"
            result_main_bookmark_state="preserved"

            if [ -e .jj ] && [ ! -d .jj ]; then
                exit 5
            fi

            if [ ! -d .jj ]; then
                if ! run_cmd "jj git init --colocate ."; then
                    exit 6
                fi
            fi

            if [ -n "$origin_repo_url" ]; then
                if ! run_cmd "jj config set --repo git.fetch '[\"upstream\",\"origin\"]'"; then
                    exit 7
                fi
                if ! run_cmd "jj config set --repo git.push origin"; then
                    exit 12
                fi
            else
                if [ "$has_origin_remote" = true ]; then
                    if ! run_cmd "jj config set --repo git.fetch '[\"upstream\",\"origin\"]'"; then
                        exit 7
                    fi
                    if ! run_cmd "jj config set --repo git.push origin"; then
                        exit 12
                    fi
                    result_origin_tracking="pending-origin-trunk-check"
                else
                    if ! run_cmd "jj config set --repo git.fetch '[\"upstream\"]'"; then
                        exit 7
                    fi
                    if ! run_cmd "jj config unset --repo git.push || true"; then
                        exit 7
                    fi
                fi
            fi

            if ! run_cmd "git fetch --prune upstream"; then
                exit 16
            fi
            if [ "$has_origin_remote" = true ]; then
                if ! run_cmd "git fetch --prune origin"; then
                    warn "[$entry] unable to fetch origin; continuing with existing origin refs"
                fi
            fi

            upstream_trunk=$(detect_upstream_trunk_branch || true)
            if [ -z "$upstream_trunk" ]; then
                exit 17
            fi
            result_trunk_branch="$upstream_trunk"

            if ! run_cmd "jj config set --repo 'revset-aliases.\"trunk()\"' \"${upstream_trunk}@upstream\""; then
                exit 9
            fi
            if ! jj_track_bookmark_remote "$upstream_trunk" "upstream"; then
                exit 8
            fi

            if [ "$has_origin_remote" = true ]; then
                if git show-ref --verify --quiet "refs/remotes/origin/${upstream_trunk}"; then
                    if ! jj_track_bookmark_remote "$upstream_trunk" "origin"; then
                        exit 8
                    fi
                    result_origin_tracking="tracked"
                else
                    warn "[$entry] origin/${upstream_trunk} not found; skipping origin tracking for ${upstream_trunk}"
                    result_origin_tracking="missing-origin-${upstream_trunk}"
                fi
            else
                result_origin_tracking="not-configured"
            fi

            if jj log -r 'main' -n 1 >/dev/null 2>&1; then
                has_main_bookmark=true
            fi
            if ! run_cmd "jj bookmark set main -r 'trunk()' --allow-backwards"; then
                exit 19
            fi
            if [ "$has_main_bookmark" = false ]; then
                result_main_bookmark_state="created-and-reset-to-trunk"
            else
                result_main_bookmark_state="reset-to-trunk"
            fi
        else
            result_origin_tracking="jj-unavailable"
            result_main_bookmark_state="jj-unavailable"
        fi

        printf '%s|%s|%s\n' "$result_trunk_branch" "$result_origin_tracking" "$result_main_bookmark_state" > "$metadata_file"
    )
    subshell_rc=$?
    if [ "$subshell_rc" -ne 0 ]; then
        case "$subshell_rc" in
            5) write_result "$result_file" "failed" "$entry" ".jj path exists but is not a directory" ;;
            6) write_result "$result_file" "failed" "$entry" "jj git init failed" ;;
            7) write_result "$result_file" "failed" "$entry" "unable to set jj git.fetch upstream default" ;;
            8) write_result "$result_file" "failed" "$entry" "unable to track upstream default bookmark" ;;
            9) write_result "$result_file" "failed" "$entry" "unable to set jj trunk alias" ;;
            10) write_result "$result_file" "failed" "$entry" "unable to configure origin remote" ;;
            11) write_result "$result_file" "failed" "$entry" "unable to configure origin remote" ;;
            12) write_result "$result_file" "failed" "$entry" "unable to set jj push default remote" ;;
            13) write_result "$result_file" "failed" "$entry" "unable to configure upstream remote" ;;
            14) write_result "$result_file" "failed" "$entry" "unable to configure upstream remote" ;;
            16) write_result "$result_file" "failed" "$entry" "unable to fetch upstream remote" ;;
            17) write_result "$result_file" "failed" "$entry" "unable to detect upstream trunk branch (main/master)" ;;
            19) write_result "$result_file" "failed" "$entry" "unable to reset local jj main bookmark to trunk()" ;;
            *) write_result "$result_file" "failed" "$entry" "unexpected failure" ;;
        esac
        return 1
    fi

    result_trunk_branch=""
    result_origin_tracking=""
    result_main_bookmark_state=""
    if [ -f "$metadata_file" ]; then
        IFS='|' read -r result_trunk_branch result_origin_tracking result_main_bookmark_state < "$metadata_file"
        rm -f "$metadata_file"
    fi

    summary_message="initialized"
    if [ "$existing_repo" = true ]; then
        summary_message="remotes reconciled"
    fi
    summary_message="${summary_message}; main reset to trunk()"

    if [ "$existing_repo" = true ]; then
        write_result "$result_file" "success" "$entry" "$summary_message" \
            "$result_trunk_branch" "$result_origin_tracking" "$result_main_bookmark_state"
    else
        write_result "$result_file" "success" "$entry" "$summary_message" \
            "$result_trunk_branch" "$result_origin_tracking" "$result_main_bookmark_state"
    fi
    return 0
}

PIDS=()
RESULT_FILES=()
INDEX=0
PARSED_REPO_LIST="${RESULT_DIR}/repo-list.parsed"

parse_repo_list_json "$REPO_LIST" "$PARSED_REPO_LIST"

while IFS='|' read -r REPO_PATH UPSTREAM_REPO ORIGIN_REPO || [ -n "$REPO_PATH" ]; do
    ENTRY="$REPO_PATH"
    TARGET_PATH="${REPO_DIR}/${REPO_PATH}"
    RESULT_FILE="${RESULT_DIR}/result_${INDEX}.txt"
    INDEX=$((INDEX + 1))
    RESULT_FILES+=("$RESULT_FILE")

    existing_repo=false
    if [ -d "$TARGET_PATH/.git" ]; then
        existing_repo=true
    fi

    init_repo "$ENTRY" "$UPSTREAM_REPO" "$ORIGIN_REPO" "$TARGET_PATH" "$RESULT_FILE" "$existing_repo" &
    PIDS+=("$!")
done < "$PARSED_REPO_LIST"

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
        trunk_branch=""
        origin_tracking=""
        main_bookmark_state=""
    else
        IFS='|' read -r status entry message trunk_branch origin_tracking main_bookmark_state < "$result_file"
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
    json_object="{\"repo\":\"$json_entry\",\"status\":\"$json_status\",\"message\":\"$json_message\""
    json_trunk_branch=$(json_escape "$trunk_branch")
    json_origin_tracking=$(json_escape "$origin_tracking")
    json_main_bookmark_state=$(json_escape "$main_bookmark_state")
    json_object="${json_object},\"trunk_branch\":\"$json_trunk_branch\""
    json_object="${json_object},\"origin_tracking\":\"$json_origin_tracking\""
    json_object="${json_object},\"main_bookmark_state\":\"$json_main_bookmark_state\""
    json_object="${json_object}}"
    JSON_ITEMS="${JSON_ITEMS}${JSON_SEP}${json_object}"
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
