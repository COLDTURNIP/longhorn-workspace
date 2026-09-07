#!/usr/bin/env bash
# Remove inactive local tickets only when GitHub confirms the issue is closed.
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<'USAGE'
Usage: ticket_cleanup.sh [options]

Scan immediate entries of the workspace's ticket/ directory. Match the prefix
^(longhorn|lh)[-_]([0-9]+)[-_] and check issues in github.com/longhorn/longhorn.
Files and directories qualify only if the issue is closed and every local
entry in the tree has an mtime strictly older than the cutoff.

Options:
  --older-than AGE    Positive integer plus days, weeks, months, or years.
                     Default: '90 days' (GNU date UTC calendar arithmetic).
  --ticket-root DIR   Explicit ticket directory, whose basename must be ticket.
                     Default: discover the workspace from the current directory.
  --delete            Permanently delete qualifying entries (no prompt).
  -n, --dry-run       Preview only (default); conflicts with --delete.
  -h, --help          Show help.

Examples (from the workspace root):
  bash agent-skills/ticket-cleanup/ticket_cleanup.sh
  bash agent-skills/ticket-cleanup/ticket_cleanup.sh --older-than '90 days'
  bash agent-skills/ticket-cleanup/ticket_cleanup.sh --older-than '90 days' --delete

Requires Bash 4+, gh with GitHub access, and GNU coreutils/findutils plus awk.
Open issues, pull requests, failed lookups, symlink entries, and entries with
unreadable or different-device subtrees are retained. No symlinks are followed.
Run while ticket writers and mounts are inactive; checks are not atomic with rm.
Exit: 0 completed; 1 lookup/scan/deletion errors (possibly partial cleanup);
      2 invalid arguments; 3 missing prerequisites or unsafe ticket root.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$2" >&2
    exit "$1"
}

report() {
    printf '%s issue=%s path=%q %s\n' "$1" "$issue" "$entry" "$2"
}

older_than='90 days'
ticket_root=''
delete=false
explicit_dry_run=false
while (($#)); do
    case "$1" in
        --older-than|--ticket-root)
            (($# >= 2)) && [[ -n $2 ]] || fail 2 "Missing value for $1"
            case "$1" in
                --older-than) older_than=$2 ;;
                --ticket-root) ticket_root=$2 ;;
            esac
            shift 2
            ;;
        --delete) delete=true; shift ;;
        -n|--dry-run) explicit_dry_run=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail 2 'Unknown argument; use --help' ;;
    esac
done
[[ $delete != true || $explicit_dry_run != true ]] || fail 2 '--delete conflicts with --dry-run'
[[ $older_than =~ ^([1-9][0-9]*)[[:space:]]+(days?|weeks?|months?|years?)$ ]] ||
    fail 2 "Invalid age; use a positive integer and days, weeks, months, or years"
older_than="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
((BASH_VERSINFO[0] >= 4)) || fail 3 'Bash 4 or newer is required'
for command in gh date find awk realpath stat rm; do
    command -v "$command" >/dev/null 2>&1 || fail 3 "Missing command: $command"
done
date --version >/dev/null 2>&1 && find --version >/dev/null 2>&1 &&
    stat --version >/dev/null 2>&1 && rm --version >/dev/null 2>&1 ||
    fail 3 'GNU coreutils and findutils are required'

if [[ -z $ticket_root ]]; then
    workspace=$PWD
    while [[ ! -f $workspace/AGENTS.md || ! -d $workspace/agent-skills || ! -d $workspace/ticket ]]; do
        [[ $workspace != / ]] || fail 3 'Workspace not found; specify --ticket-root'
        workspace=$(dirname -- "$workspace")
    done
    ticket_root=$workspace/ticket
fi
while [[ $ticket_root != / && $ticket_root == */ ]]; do ticket_root=${ticket_root%/}; done
[[ -d $ticket_root && ! -L $ticket_root ]] || fail 3 'Ticket root must be a directory, not a symlink'
ticket_root=$(realpath -e -- "$ticket_root") || fail 3 'Cannot resolve ticket root'
[[ ${ticket_root##*/} == ticket && $ticket_root != /ticket ]] ||
    fail 3 'Refusing a root-level directory or a directory not named ticket'
root_identity=$(stat --printf='%d:%i' -- "$ticket_root") || fail 3 'Cannot stat ticket root'

# Freeze one cutoff for the run, including rechecks. Absolute UTC input avoids
# daylight-saving transitions; relative months/years follow GNU date semantics.
now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
cutoff=$(date -u --date="$now $older_than ago" +%s 2>/dev/null) || fail 2 'Age is outside the supported date range'
now_epoch=$(date -u --date="$now" +%s)
[[ $cutoff =~ ^[0-9]+$ ]] && ((cutoff < now_epoch)) || fail 2 'Age must produce a past cutoff after the Unix epoch'
cutoff_label=$(date -u --date="@$cutoff" '+%Y-%m-%dT%H:%M:%SZ')
printf 'Mode=%s repository=longhorn/longhorn older-than=%q cutoff=%s root=%q\n' \
    "$([[ $delete == true ]] && printf delete || printf dry-run)" "$older_than" "$cutoff_label" "$ticket_root"

query_issue() {
    # Pin the host and repository, independent of GH_HOST, GH_REPO, or git remotes.
    # The issues REST endpoint also returns PRs, so explicitly distinguish them.
    GH_PROMPT_DISABLED=1 gh api --hostname github.com --method GET \
        "repos/longhorn/longhorn/issues/$1" \
        --jq 'if .pull_request then "PULL_REQUEST" else .state end' 2>/dev/null
}

latest_mtime() {
    local path=$1 device
    device=$(stat --printf='%d' -- "$path") || return 1
    # NUL-delimited names are unnecessary here: find emits only device/time
    # numbers. Include directories (additions/removals) and symlinks themselves.
    # -xdev still visits the mountpoint, whose device mismatch rejects the tree.
    find -P "$path" -xdev -printf '%D %T@\n' 2>/dev/null |
        awk -v device="$device" '
            $1 != device { bad = 1 }
            !seen || $2 > latest { latest = $2; seen = 1 }
            END {
                if (bad || !seen) exit 1
                printf "%.9f\n", latest
            }'
}

is_old() {
    awk -v latest="$1" -v cutoff="$cutoff" 'BEGIN { exit !(latest < cutoff) }'
}

declare -A states=()
matched=0
eligible=0
deleted=0
retained=0
errors=0
shopt -s nullglob
for entry in "$ticket_root"/*; do
    name=${entry##*/}
    [[ $name =~ ^(longhorn|lh)[-_]([0-9]+)[-_] ]] || continue
    issue=${BASH_REMATCH[2]}
    # Strip leading zeros without arithmetic overflow for unusual names.
    issue=${issue#"${issue%%[!0]*}"}
    issue=${issue:-0}
    matched=$((matched + 1))
    retained=$((retained + 1))
    if [[ -L $entry || ( ! -d $entry && ! -f $entry ) ]]; then
        report KEEP 'symlink or unsupported entry type'
        continue
    fi
    if ! identity=$(stat --printf='%d:%i' -- "$entry"); then
        report ERROR 'cannot stat entry; retained'
        errors=$((errors + 1))
        continue
    fi
    if [[ -z ${states[$issue]+present} ]]; then
        if ! state=$(query_issue "$issue"); then state=ERROR; fi
        states[$issue]=$state
    fi
    state=${states[$issue]}
    case "$state" in
        closed) ;;
        open|PULL_REQUEST) report KEEP "GitHub state=$state"; continue ;;
        *)
            report ERROR 'GitHub lookup failed or returned an unknown state; retained (check gh auth status --hostname github.com)'
            errors=$((errors + 1))
            continue
            ;;
    esac
    if ! latest=$(latest_mtime "$entry"); then
        report ERROR 'cannot scan tree or found a different-device subtree; retained'
        errors=$((errors + 1))
        continue
    fi
    if ! is_old "$latest"; then
        report KEEP 'local modification at or after cutoff'
        continue
    fi
    if [[ $delete != true ]]; then
        report WOULD_DELETE "closed and inactive; latest-mtime=$latest"
        eligible=$((eligible + 1))
        retained=$((retained - 1))
        continue
    fi

    # Never use cached status to authorize removal. A changed/reopened ticket
    # between discovery and deletion must be retained.
    if ! state=$(query_issue "$issue"); then state=ERROR; fi
    case "$state" in
        closed) ;;
        open|PULL_REQUEST) report KEEP "GitHub state changed to $state"; continue ;;
        *) report ERROR 'GitHub recheck failed; retained'; errors=$((errors + 1)); continue ;;
    esac
    if [[ -L $ticket_root || ! -d $ticket_root ]] ||
        [[ $(stat --printf='%d:%i' -- "$ticket_root") != "$root_identity" ]]; then
        fail 3 'Ticket root changed during cleanup; stopping'
    fi
    if [[ -L $entry || ! -e $entry ]] ||
        [[ $(stat --printf='%d:%i' -- "$entry") != "$identity" ]]; then
        report ERROR 'entry changed during cleanup; retained'
        errors=$((errors + 1))
        continue
    fi
    if ! latest=$(latest_mtime "$entry"); then
        report ERROR 'local tree recheck failed; retained'
        errors=$((errors + 1))
        continue
    fi
    if ! is_old "$latest"; then
        report KEEP 'local tree became active during cleanup'
        continue
    fi
    eligible=$((eligible + 1))
    if rm -rf --one-file-system --preserve-root=all -- "$entry"; then
        report DELETED 'closed and inactive'
        deleted=$((deleted + 1))
        retained=$((retained - 1))
    else
        report ERROR 'deletion failed; inspect for partial removal'
        errors=$((errors + 1))
    fi
done
printf 'Summary: matched=%d eligible=%d deleted=%d retained=%d errors=%d\n' \
    "$matched" "$eligible" "$deleted" "$retained" "$errors"
((errors == 0))
