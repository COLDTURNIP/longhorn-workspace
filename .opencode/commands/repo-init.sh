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
  - upstream: required org/repo
  - origin: optional org/repo personal fork

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

detect_upstream_default_branch() {
    local ref=""

    ref=$(git symbolic-ref refs/remotes/upstream/HEAD 2>/dev/null || true)
    if [ -z "$ref" ]; then
        return 1
    fi

    case "$ref" in
        refs/remotes/upstream/*)
            printf '%s\n' "${ref#refs/remotes/upstream/}"
            return 0
            ;;
    esac

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

parse_repo_list_json() {
    local source_file=$1 output_file=$2
    local tmp_tsv

    if ! command -v jq >/dev/null 2>&1; then
        die "jq is required to parse $source_file"
    fi

    tmp_tsv="${output_file}.tsv"

    if ! jq -er '
      def repo_ref_ok: test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$");
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
      | if (($cfg.upstream|type) != "string") or (($cfg.upstream|repo_ref_ok)|not)
        then error("invalid upstream repo ref for '\''\($path)'\'': '\''\($cfg.upstream|tostring)'\''")
        else .
        end
      | if (($cfg|has("origin")) and (((($cfg.origin|type) != "string") or (($cfg.origin|repo_ref_ok)|not))))
        then error("invalid origin repo ref for '\''\($path)'\'': '\''\($cfg.origin|tostring)'\''")
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
    local entry=$1 upstream_repo=$2 origin_repo=$3 target_path=$4 result_file=$5
    local upstream_url origin_url default_branch upstream_trunk
    local parent_dir

    upstream_url="https://github.com/${upstream_repo}.git"
    origin_url=""
    if [ -n "$origin_repo" ]; then
        origin_url="https://github.com/${origin_repo}.git"
    fi
    parent_dir=$(dirname "$target_path")

    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Preparing to clone $entry from upstream $upstream_repo"
        info "[DRY-RUN] mkdir -p \"$parent_dir\""
        info "[DRY-RUN] git clone \"$upstream_url\" \"$target_path\" --origin upstream"
        info "[DRY-RUN] cd \"$target_path\" && detect local default branch"
        info "[DRY-RUN] cd \"$target_path\" && git branch -m <default-branch> upstream"
        if [ -n "$origin_repo" ]; then
            info "[DRY-RUN] cd \"$target_path\" && git remote add origin \"$origin_url\" (or set-url if exists)"
            info "[DRY-RUN] cd \"$target_path\" && git fetch origin"
        fi
        if command -v jj >/dev/null 2>&1; then
            info "[DRY-RUN] cd \"$target_path\" && jj git init --colocate ."
            if [ -n "$origin_repo" ]; then
                info "[DRY-RUN] cd \"$target_path\" && jj config set --repo git.fetch '[\"upstream\",\"origin\"]'"
                info "[DRY-RUN] cd \"$target_path\" && jj config set --repo git.push origin"
                info "[DRY-RUN] cd \"$target_path\" && jj bookmark track <upstream-default-branch>@upstream <upstream-default-branch>@origin"
            else
                info "[DRY-RUN] cd \"$target_path\" && jj config set --repo git.fetch '[\"upstream\"]'"
                info "[DRY-RUN] cd \"$target_path\" && jj bookmark track <upstream-default-branch>@upstream"
            fi
            info "[DRY-RUN] cd \"$target_path\" && jj config set --repo 'revset-aliases.\"trunk()\"' <upstream-default-branch>@upstream"
        fi
        write_result "$result_file" "dry-run" "$entry" "planned"
        return 0
    fi

    if ! run_cmd "mkdir -p \"$parent_dir\""; then
        write_result "$result_file" "failed" "$entry" "unable to create parent directory"
        return 1
    fi

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

        if [ -n "$origin_repo" ]; then
            if git remote get-url origin >/dev/null 2>&1; then
                if ! run_cmd "git remote set-url origin \"$origin_url\""; then
                    exit 10
                fi
            else
                if ! run_cmd "git remote add origin \"$origin_url\""; then
                    exit 10
                fi
            fi

            if ! run_cmd "git fetch origin"; then
                exit 11
            fi
        fi

        if command -v jj >/dev/null 2>&1; then
            if [ -e .jj ] && [ ! -d .jj ]; then
                exit 5
            fi

            if [ ! -d .jj ]; then
                if ! run_cmd "jj git init --colocate ."; then
                    exit 6
                fi
            fi

            if [ -n "$origin_repo" ]; then
                if ! run_cmd "jj config set --repo git.fetch '[\"upstream\",\"origin\"]'"; then
                    exit 7
                fi
                if ! run_cmd "jj config set --repo git.push origin"; then
                    exit 12
                fi
            else
                if ! run_cmd "jj config set --repo git.fetch '[\"upstream\"]'"; then
                    exit 7
                fi
            fi

            upstream_trunk=$(detect_upstream_default_branch || true)
            if [ -n "$upstream_trunk" ]; then
                if [ -n "$origin_repo" ] && git show-ref --verify --quiet "refs/remotes/origin/${upstream_trunk}"; then
                    if ! run_cmd "jj bookmark track \"${upstream_trunk}@upstream\" \"${upstream_trunk}@origin\""; then
                        exit 8
                    fi
                else
                    if ! run_cmd "jj bookmark track \"${upstream_trunk}@upstream\""; then
                        exit 8
                    fi
                fi
                if ! run_cmd "jj config set --repo 'revset-aliases.\"trunk()\"' \"${upstream_trunk}@upstream\""; then
                    exit 9
                fi
            fi
        fi
    )
    subshell_rc=$?
    if [ "$subshell_rc" -ne 0 ]; then
        case "$subshell_rc" in
            2) write_result "$result_file" "failed" "$entry" "unable to detect local default branch" ;;
            3) write_result "$result_file" "failed" "$entry" "unable to rename default branch to upstream" ;;
            4) write_result "$result_file" "failed" "$entry" "upstream branch missing after rename" ;;
            5) write_result "$result_file" "failed" "$entry" ".jj path exists but is not a directory" ;;
            6) write_result "$result_file" "failed" "$entry" "jj git init failed" ;;
            7) write_result "$result_file" "failed" "$entry" "unable to set jj git.fetch upstream default" ;;
            8) write_result "$result_file" "failed" "$entry" "unable to track upstream default bookmark" ;;
            9) write_result "$result_file" "failed" "$entry" "unable to set jj trunk alias" ;;
            10) write_result "$result_file" "failed" "$entry" "unable to configure origin remote" ;;
            11) write_result "$result_file" "failed" "$entry" "unable to fetch origin remote" ;;
            12) write_result "$result_file" "failed" "$entry" "unable to set jj push default remote" ;;
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
PARSED_REPO_LIST="${RESULT_DIR}/repo-list.parsed"

parse_repo_list_json "$REPO_LIST" "$PARSED_REPO_LIST"

while IFS='|' read -r REPO_PATH UPSTREAM_REPO ORIGIN_REPO || [ -n "$REPO_PATH" ]; do
    ENTRY="$REPO_PATH"
    TARGET_PATH="${REPO_DIR}/${REPO_PATH}"
    RESULT_FILE="${RESULT_DIR}/result_${INDEX}.txt"
    INDEX=$((INDEX + 1))
    RESULT_FILES+=("$RESULT_FILE")

    if [ -d "$TARGET_PATH/.git" ]; then
        warn "[SKIP] $ENTRY already exists at $TARGET_PATH"
        write_result "$RESULT_FILE" "skipped" "$ENTRY" "already exists"
        continue
    fi

    init_repo "$ENTRY" "$UPSTREAM_REPO" "$ORIGIN_REPO" "$TARGET_PATH" "$RESULT_FILE" &
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
