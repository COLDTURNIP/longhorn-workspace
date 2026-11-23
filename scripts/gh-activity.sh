#!/usr/bin/env bash
# Print what changed on GitHub issues and pull requests since a point in time.
# Read-only: every request is `gh api --method GET`.
set -euo pipefail

SCRIPT_NAME=${0##*/}
EXIT_FAIL=1
EXIT_ARG=2
EXIT_ENV=3

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [--since <time>] [--status <STATUS.md>] [--width <n>] [<target>...]

Print what changed on GitHub issues and pull requests since <time>, one line per
item, oldest first: comments, reviews, inline review comments, commits, and
timeline events (closed, merged, labeled, cross-referenced, ...). Each target
starts with a header that shows its current state. Read-only.

Targets: owner/repo#number, or a github.com issue or pull request URL.

Options:
  --since <time>      ISO 8601 time (2026-11-13T08:00:00Z), a date (2026-11-13),
                      or an age (36h, 7d). Default: the "Last upstream check:"
                      line of --status, otherwise 7d.
  --status <file>     Read targets from the "Tracked:" line and the default
                      --since from the "Last upstream check:" line of a ticket
                      STATUS.md. Targets given as arguments are added.
  --width <n>         Truncate each line's text to n characters (default 200).
  -h, --help          Show this help.

Exit codes: 0 success, 1 a target failed, 2 usage error, 3 missing tool.
USAGE
}

die_usage() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$1" >&2
  usage >&2
  exit "$EXIT_ARG"
}

for tool in gh jq date; do
  command -v "$tool" >/dev/null 2>&1 || { printf '%s: %s not found\n' "$SCRIPT_NAME" "$tool" >&2; exit "$EXIT_ENV"; }
done

SINCE_ARG=""
STATUS_FILE=""
WIDTH=200
TARGETS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since) [ "$#" -ge 2 ] || die_usage "--since needs a value"; SINCE_ARG=$2; shift 2 ;;
    --status) [ "$#" -ge 2 ] || die_usage "--status needs a file"; STATUS_FILE=$2; shift 2 ;;
    --width) [ "$#" -ge 2 ] || die_usage "--width needs a value"; WIDTH=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; TARGETS+=("$@"); break ;;
    -*) die_usage "unknown option: $1" ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done
case "$WIDTH" in ""|*[!0-9]*|0) die_usage "--width must be a positive integer" ;; esac

if [ -n "$STATUS_FILE" ]; then
  [ -r "$STATUS_FILE" ] || die_usage "cannot read $STATUS_FILE"
  tracked_line=$(grep -m1 -E '^Tracked:' "$STATUS_FILE" || true)
  if [ -n "$tracked_line" ]; then
    read -r -a status_targets <<<"$(printf '%s' "${tracked_line#Tracked:}" | tr ',' ' ')"
    TARGETS=("${status_targets[@]}" "${TARGETS[@]}")
  fi
  if [ -z "$SINCE_ARG" ]; then
    check_line=$(grep -m1 -E '^Last upstream check:' "$STATUS_FILE" || true)
    SINCE_ARG=$(printf '%s' "${check_line#Last upstream check:}" | tr -d '[:space:]')
  fi
fi
[ "${#TARGETS[@]}" -gt 0 ] || die_usage "no targets"
[ -n "$SINCE_ARG" ] || SINCE_ARG=7d

normalize_since() {
  local value=$1 spec
  case "$value" in
    *[!0-9hd]*) spec=$value ;;
    *h) spec="-${value%h} hours" ;;
    *d) spec="-${value%d} days" ;;
    *) spec=$value ;;
  esac
  case "$value" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) spec="${value}T00:00:00Z" ;;
  esac
  date -u -d "$spec" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
SINCE=$(normalize_since "$SINCE_ARG") || die_usage "invalid --since: $SINCE_ARG"

ERR_FILE=$(mktemp)
trap 'rm -f -- "$ERR_FILE"' EXIT

# gh 2.105+ appends multi-line "hint: ... gh event listen" text to stderr on PR
# reads; drop it and keep real errors.
ghget() {
  if gh api --method GET "$@" 2>"$ERR_FILE"; then
    return 0
  fi
  grep -v -E '^(hint: |  - |    gh event listen)' "$ERR_FILE" >&2 || true
  return 1
}

# Shared jq helpers: one-line text and truncation.
# shellcheck disable=SC2016 # jq program text, not shell expansions
JQ_DEFS='
def oneline: (. // "") | tostring | gsub("[\r\n\t ]+"; " ") | gsub("<!--.*?-->"; "") | gsub("^ +| +$"; "");
def clip($w): if length > $w then .[0:$w] + "..." else . end;
'

parse_target() {
  local target=$1
  if [[ $target =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
    OWNER=${BASH_REMATCH[1]} REPO=${BASH_REMATCH[2]} NUMBER=${BASH_REMATCH[3]}
  elif [[ $target =~ ^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+) ]]; then
    OWNER=${BASH_REMATCH[1]} REPO=${BASH_REMATCH[2]} NUMBER=${BASH_REMATCH[4]}
  else
    return 1
  fi
}

report_target() {
  local target=$1 issue pr_json="" header timeline inline=""
  parse_target "$target" || { printf '== %s: not owner/repo#number or a GitHub URL\n' "$target" >&2; return 1; }
  local path="repos/$OWNER/$REPO"

  issue=$(ghget "$path/issues/$NUMBER") || { printf '== %s: failed to read\n' "$target" >&2; return 1; }
  if jq -e 'has("pull_request") and .pull_request != null' <<<"$issue" >/dev/null; then
    pr_json=$(ghget "$path/pulls/$NUMBER") || { printf '== %s: failed to read pull request\n' "$target" >&2; return 1; }
  fi

  header=$(jq -r --arg t "$OWNER/$REPO#$NUMBER" --argjson pr "${pr_json:-null}" "$JQ_DEFS"'
    if $pr != null then
      "== \($t) PR \(if $pr.merged_at then "MERGED \($pr.merged_at)" else ($pr.state | ascii_upcase) end)"
      + (if $pr.draft then " draft" else "" end)
      + " head \($pr.head.sha[0:8]) \"\(.title | oneline)\""
    else
      "== \($t) ISSUE \(.state | ascii_upcase)"
      + (if .state_reason then " (\(.state_reason))" else "" end)
      + " \"\(.title | oneline)\""
    end' <<<"$issue")
  printf '%s\n' "$header"

  timeline=$(ghget --paginate "$path/issues/$NUMBER/timeline?per_page=100") || { printf '   failed to read the timeline\n' >&2; return 1; }
  if [ -n "$pr_json" ]; then
    inline=$(ghget --paginate "$path/pulls/$NUMBER/comments?per_page=100&since=$SINCE") || { printf '   failed to read review comments\n' >&2; return 1; }
  fi

  local lines
  lines=$(
    {
      jq -r --arg since "$SINCE" --argjson w "$WIDTH" "$JQ_DEFS"'
        .[] | select(.event != null)
        | select(.event | IN("subscribed","unsubscribed","mentioned","line-commented") | not)
        | (.created_at // .submitted_at // .committer.date // .author.date // "") as $time
        | select($time >= $since)
        | (.actor.login // .user.login // .author.name // "-") as $who
        | (if .event == "commented" then "\(.body | oneline)"
           elif .event == "reviewed" then "\(.state)\(if (.body | oneline) != "" then ": " + (.body | oneline) else "" end)"
           elif .event == "committed" then "\(.sha[0:8]) \(.message | oneline)"
           elif .event == "cross-referenced" then
             "from \(.source.issue.repository.full_name // "?")#\(.source.issue.number // "?") \(.source.issue.title | oneline)"
           elif .event == "labeled" or .event == "unlabeled" then .label.name
           elif .event == "assigned" or .event == "unassigned" then .assignee.login
           elif .event == "review_requested" or .event == "review_request_removed" then
             (.requested_reviewer.login // .requested_team.name // "?")
           elif .event == "renamed" then "\(.rename.from | oneline) -> \(.rename.to | oneline)"
           elif .event == "referenced" then "commit \(.commit_id // "?" | .[0:8])"
           else "" end) as $text
        | [$time, .event, $who, ($text | clip($w))] | @tsv
      ' <<<"$timeline"
      if [ -n "$inline" ]; then
        jq -r --arg since "$SINCE" --argjson w "$WIDTH" "$JQ_DEFS"'
          .[] | select(.created_at >= $since)
          | [.created_at, (if .in_reply_to_id then "review-reply" else "review-comment" end), .user.login,
             ("\(.path):\(.line // .original_line // "?") \(.body | oneline)" | clip($w))] | @tsv
        ' <<<"$inline"
      fi
    } | LC_ALL=C sort -s -t "$(printf '\t')" -k1,1
  )
  if [ -z "$lines" ]; then
    printf '   (no activity since %s)\n' "$SINCE"
  else
    printf '%s\n' "$lines" | awk -F '\t' '{ printf "%s %s %s", $1, $2, $3; if ($4 != "") printf ": %s", $4; printf "\n" }'
  fi
}

printf 'Activity since %s\n' "$SINCE"
rc=0
for target in "${TARGETS[@]}"; do
  report_target "$target" || rc=$EXIT_FAIL
done
exit "$rc"
