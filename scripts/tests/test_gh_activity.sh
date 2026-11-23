#!/usr/bin/env bash
# Offline tests for scripts/gh-activity.sh. A fake gh on PATH serves fixture
# JSON and records every call, so no request reaches GitHub.
set -euo pipefail
export LC_ALL=C

SCRIPT=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")/../gh-activity.sh")
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT
mkdir -p "$TEMP/bin"
export GH_FAKE_LOG="$TEMP/gh.log"

cat >"$TEMP/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$GH_FAKE_LOG"
path=${!#}
case "$path" in
  repos/o/r/issues/1)
    echo '{"number":1,"title":"Issue one","state":"open","state_reason":null}' ;;
  repos/o/r/issues/1/timeline*)
    echo '[{"event":"commented","created_at":"2026-11-10T00:00:00Z","actor":{"login":"old"},"body":"too old"},'
    echo ' {"event":"subscribed","created_at":"2026-11-14T00:00:00Z","actor":{"login":"noise"}},'
    echo ' {"event":"labeled","created_at":"2026-11-15T00:00:00Z","actor":{"login":"bot"},"label":{"name":"Stale"}},'
    echo ' {"event":"commented","created_at":"2026-11-13T08:33:49Z","actor":{"login":"alice"},"body":"<!-- x -->Line one\nline two"}]'
    echo '[{"event":"cross-referenced","created_at":"2026-11-18T08:55:47Z","actor":{"login":"bob"},"source":{"issue":{"number":9,"title":"Other","repository":{"full_name":"o/r"}}}}]' ;;
  repos/o/r/issues/2)
    echo '{"number":2,"title":"PR two","state":"closed","pull_request":{"url":"x"}}' ;;
  repos/o/r/pulls/2)
    echo '{"number":2,"state":"closed","merged_at":"2026-11-17T03:32:12Z","draft":false,"head":{"sha":"15aba4230000"}}' ;;
  repos/o/r/issues/2/timeline*)
    echo '[{"event":"reviewed","submitted_at":"2026-11-16T16:31:00Z","user":{"login":"copilot"},"state":"commented","body":"Changes recommended"},'
    echo ' {"event":"committed","committer":{"date":"2026-11-16T10:00:00Z"},"author":{"name":"Dev"},"sha":"abcdef123456","message":"feat: x\n\nbody"},'
    echo ' {"event":"line-commented","created_at":"2026-11-16T16:31:00Z","actor":{"login":"dup"}},'
    echo ' {"event":"merged","created_at":"2026-11-17T03:32:12Z","actor":{"login":"carol"}}]' ;;
  repos/o/r/pulls/2/comments*)
    echo '[{"created_at":"2026-11-16T16:31:01Z","user":{"login":"copilot"},"path":"a.c","line":12,"body":"race here"},'
    echo ' {"created_at":"2026-11-16T16:42:00Z","in_reply_to_id":5,"user":{"login":"carol"},"path":"a.c","line":12,"body":"Fixed."}]' ;;
  repos/o/r/issues/3)
    printf 'hint: if you need to wait for this pull request to be reviewed\n  - It prints the first event\n    gh event listen --resource x\ngh: Not Found (HTTP 404)\n' >&2
    exit 1 ;;
  *) echo "fake gh: unexpected path $path" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$TEMP/bin/gh"
export PATH="$TEMP/bin:$PATH"

FAILURES=0
check() {
  local name=$1; shift
  if "$@"; then printf 'ok   %s\n' "$name"; else printf 'FAIL %s\n' "$name"; FAILURES=$((FAILURES + 1)); fi
}
has_line() { grep -q -F -x -- "$2" "$1"; }
lacks() { ! grep -q -F -- "$2" "$1"; }

run() {
  local rc=0
  "$SCRIPT" "$@" >"$TEMP/out" 2>"$TEMP/err" || rc=$?
  printf '%s' "$rc" >"$TEMP/rc"
}
rc_is() { [ "$(cat "$TEMP/rc")" = "$1" ]; }

# Issue and pull request activity since a time, oldest first.
: >"$GH_FAKE_LOG"
run --since 2026-11-13T00:00:00Z o/r#1 https://github.com/o/r/pull/2
check "exit 0" rc_is 0
check "since line" has_line "$TEMP/out" "Activity since 2026-11-13T00:00:00Z"
check "issue header" has_line "$TEMP/out" '== o/r#1 ISSUE OPEN "Issue one"'
check "comment flattened, html comment stripped" has_line "$TEMP/out" "2026-11-13T08:33:49Z commented alice: Line one line two"
check "label event" has_line "$TEMP/out" "2026-11-15T00:00:00Z labeled bot: Stale"
check "second timeline page" has_line "$TEMP/out" "2026-11-18T08:55:47Z cross-referenced bob: from o/r#9 Other"
check "old item filtered" lacks "$TEMP/out" "too old"
check "noise event filtered" lacks "$TEMP/out" "subscribed"
check "pr header" has_line "$TEMP/out" '== o/r#2 PR MERGED 2026-11-17T03:32:12Z head 15aba423 "PR two"'
check "commit line" has_line "$TEMP/out" "2026-11-16T10:00:00Z committed Dev: abcdef12 feat: x body"
check "review line" has_line "$TEMP/out" "2026-11-16T16:31:00Z reviewed copilot: commented: Changes recommended"
check "inline review comment" has_line "$TEMP/out" "2026-11-16T16:31:01Z review-comment copilot: a.c:12 race here"
check "inline reply" has_line "$TEMP/out" "2026-11-16T16:42:00Z review-reply carol: a.c:12 Fixed."
check "line-commented not duplicated" lacks "$TEMP/out" "line-commented"
check "pr items sorted" bash -c "sed -n '/o\/r#2/,\$p' '$TEMP/out' | tail -n +2 | cut -d' ' -f1 | sort -c"
check "only GET requests" bash -c "! grep -v -E '^api --method GET ' '$GH_FAKE_LOG'"

# STATUS.md supplies targets and the default --since.
cat >"$TEMP/STATUS.md" <<'EOF'
# Status

Last upstream check: 2026-11-16T12:00:00Z
Tracked: o/r#1, o/r#2
EOF
run --status "$TEMP/STATUS.md"
check "status exit 0" rc_is 0
check "status since" has_line "$TEMP/out" "Activity since 2026-11-16T12:00:00Z"
check "status filters by its time" lacks "$TEMP/out" "alice"
check "status second target" has_line "$TEMP/out" "2026-11-17T03:32:12Z merged carol"

# A failing target reports a real error without gh hint text, and the rest still run.
run --since 7d o/r#3 o/r#1
check "failed target exits 1" rc_is 1
check "real error kept" grep -q -F "gh: Not Found (HTTP 404)" "$TEMP/err"
check "hint dropped" lacks "$TEMP/err" "gh event listen"
check "later target still reported" has_line "$TEMP/out" '== o/r#1 ISSUE OPEN "Issue one"'

# Quiet target and argument errors.
run --since 2026-11-30 o/r#1
check "no activity line" has_line "$TEMP/out" "   (no activity since 2026-11-30T00:00:00Z)"
run --since yesterday-ish o/r#1
check "invalid since exits 2" rc_is 2
run --since 7d
check "no targets exits 2" rc_is 2
run --since 7d not-a-target
check "bad target exits 1" rc_is 1

if [ "$FAILURES" -ne 0 ]; then
  printf '%d check(s) failed\n' "$FAILURES"
  exit 1
fi
printf 'all checks passed\n'
