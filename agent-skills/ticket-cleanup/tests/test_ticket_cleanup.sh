#!/usr/bin/env bash
# Offline tests: all cleanup targets and command doubles live under mktemp.
set -euo pipefail
export LC_ALL=C
SCRIPT=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")/../ticket_cleanup.sh")
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT
export REAL_DATE REAL_FIND
REAL_DATE=$(command -v date)
REAL_FIND=$(command -v find)
mkdir -p "$TEMP/bin"
export PATH="$TEMP/bin:$PATH"

cat > "$TEMP/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == api ]] || exit 90
shift
host='' method='' endpoint='' filter=''
while (($#)); do
    case "$1" in
        --hostname) host=$2; shift 2 ;;
        --method) method=$2; shift 2 ;;
        --jq) filter=$2; shift 2 ;;
        repos/*) endpoint=$1; shift ;;
        *) exit 91 ;;
    esac
done
[[ $host == github.com && $method == GET ]] || exit 92
[[ $endpoint =~ ^repos/longhorn/longhorn/issues/[0-9]+$ ]] || exit 93
[[ $filter == 'if .pull_request then "PULL_REQUEST" else .state end' ]] || exit 94
number=${endpoint##*/}
printf '%s\n' "$number" >> "$TEST_CONTROL/requests"
calls=0
if [[ -f $TEST_CONTROL/calls-$number ]]; then read -r calls < "$TEST_CONTROL/calls-$number"; fi
calls=$((calls + 1))
printf '%s\n' "$calls" > "$TEST_CONTROL/calls-$number"
state_file=$TEST_CONTROL/state-$number
if ((calls > 1)); then
    if [[ -f $TEST_CONTROL/next-$number ]]; then state_file=$TEST_CONTROL/next-$number; fi
    if [[ -f $TEST_CONTROL/touch-$number ]]; then
        IFS= read -r target < "$TEST_CONTROL/touch-$number"
        touch -- "$target"
    fi
fi
[[ -f $state_file ]] || exit 1
IFS= read -r state < "$state_file"
[[ $state != ERROR ]] || exit 1
printf '%s\n' "$state"
FAKE_GH

cat > "$TEMP/bin/date" <<'FAKE_DATE'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${TEST_NOW:-} && "$*" == '-u +%Y-%m-%dT%H:%M:%SZ' ]]; then
    printf '%s\n' "$TEST_NOW"
else
    exec "$REAL_DATE" "$@"
fi
FAKE_DATE

cat > "$TEMP/bin/find" <<'FAKE_FIND'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${TEST_FIND_FAIL:-} && "$*" == *"$TEST_FIND_FAIL"* ]]; then
    # Even a partial scan with an old timestamp must fail closed.
    printf '%s 946684800.0\n' "$(stat --printf='%d' -- "$TEST_FIND_FAIL")"
    exit 1
fi
if [[ -n ${TEST_OTHER_DEVICE:-} && "$*" == *"$TEST_OTHER_DEVICE"* ]]; then
    device=$(stat --printf='%d' -- "$TEST_OTHER_DEVICE")
    printf '%s 946684800.0\n%s0 946684800.0\n' "$device" "$device"
    exit 0
fi
exec "$REAL_FIND" "$@"
FAKE_FIND
chmod +x "$TEMP/bin/gh" "$TEMP/bin/date" "$TEMP/bin/find"

fail() { printf 'FAIL: %s\n%s\n' "$1" "${output:-}" >&2; exit 1; }
checks=0
pass() { checks=$((checks + 1)); printf 'ok %d - %s\n' "$checks" "$1"; }
case_number=0
new_case() {
    case_number=$((case_number + 1))
    case_root=$TEMP/case-$case_number
    root=$case_root/ticket
    export TEST_CONTROL=$case_root/control
    mkdir -p "$root" "$TEST_CONTROL"
    unset TEST_NOW TEST_FIND_FAIL TEST_OTHER_DEVICE
    output=''
}
state() { printf '%s\n' "$2" > "$TEST_CONTROL/state-$1"; }
old_tree() { "$REAL_FIND" "$1" -exec touch -h --date='2000-01-01 UTC' -- {} +; }
ticket() {
    mkdir -p "$root/$1/logs/extracted"
    printf 'diagnostics\n' > "$root/$1/logs/extracted/.hidden-log"
    old_tree "$root/$1"
    state "$2" closed
}
run_cleanup() {
    if output=$(bash "$SCRIPT" --ticket-root "$root" "$@" 2>&1); then rc=0; else rc=$?; fi
}
expect_status() { [[ $rc == "$1" ]] || fail "Expected exit $1, got $rc"; }
contains() { [[ $output == *"$1"* ]] || fail "Missing output: $1"; }
exists() { [[ -e $1 || -L $1 ]] || fail "Entry was removed: $1"; }
absent() { [[ ! -e $1 && ! -L $1 ]] || fail "Entry was not removed: $1"; }

new_case
number=0
for prefix in lh longhorn; do
    for first in - _; do
        for second in - _; do
            number=$((number + 1))
            ticket "$prefix$first$number${second}old" "$number"
        done
    done
done
# Execution-related environment variables must not enable deletion.
export DRY_RUN=false FORCE=true GH_HOST=example.invalid GH_REPO=other/repository
run_cleanup
expect_status 0
contains 'Mode=dry-run'
contains 'matched=8 eligible=8 deleted=0'
for path in "$root"/*; do exists "$path"; done
pass 'all prefix/separator combinations qualify; default is dry-run regardless of environment'

new_case
ticket lh-1-old 1
ticket lh-2-open 2; state 2 open
ticket lh-3-fresh-descendant 3; touch "$root/lh-3-fresh-descendant/logs/extracted/.hidden-log"
ticket lh_4_fresh-directory 4; touch "$root/lh_4_fresh-directory/logs"
ticket lh-5-future 5; touch --date='next year' "$root/lh-5-future/logs/extracted/.hidden-log"
ticket longhorn_6_pull-request 6; state 6 PULL_REQUEST
printf 'report\n' > "$root/longhorn_7-file.md"; old_tree "$root/longhorn_7-file.md"; state 7 closed
ticket lh-8-nested-link 8
mkdir -p "$case_root/outside"
printf 'must survive\n' > "$case_root/outside/recent-file"
ln -s "$case_root/outside" "$root/lh-8-nested-link/logs/external"
old_tree "$root/lh-8-nested-link"
ln -s "$case_root/outside" "$root/lh-9-top-link"
ticket community-10-unrelated 10
ticket lh-11-recent-root 11; touch "$root/lh-11-recent-root"
printf 'report\n' > "$root/lh_00012_file.md"; old_tree "$root/lh_00012_file.md"; state 12 closed
ln -s "$case_root/missing" "$root/lh_13_broken-link"
mkdir -p "$root/misc/lh-14-nested" "$root/lh-15"
run_cleanup --delete
expect_status 0
contains 'eligible=4 deleted=4'
for name in lh-1-old longhorn_7-file.md lh-8-nested-link lh_00012_file.md; do absent "$root/$name"; done
for name in lh-2-open lh-3-fresh-descendant lh_4_fresh-directory lh-5-future longhorn_6_pull-request lh-9-top-link community-10-unrelated lh-11-recent-root lh_13_broken-link misc/lh-14-nested lh-15; do exists "$root/$name"; done
exists "$case_root/outside/recent-file"
[[ ! -f $TEST_CONTROL/calls-9 && ! -f $TEST_CONTROL/calls-10 ]] || fail 'Looked up excluded entries'
pass 'deletion requires closed and recursively inactive; files, leading zeros, and symlinks are handled'

new_case
ticket lh-1-forty-five-days 1
"$REAL_FIND" "$root/lh-1-forty-five-days" -exec touch -h --date='45 days ago' -- {} +
run_cleanup; expect_status 0; contains 'eligible=0'
run_cleanup --older-than '30 days'; expect_status 0; contains 'eligible=1'
run_cleanup --older-than '8 weeks'; expect_status 0; contains 'eligible=0'
run_cleanup --older-than '1 year'; expect_status 0; contains 'eligible=0'
pass 'custom days/weeks/years override the 90-day default'

new_case
export TEST_NOW='2026-06-15T12:00:00Z'
cutoff=$("$REAL_DATE" -u --date="$TEST_NOW 90 days ago" +%s)
for number in 1 2 3; do ticket "lh-$number-boundary" "$number"; done
"$REAL_FIND" "$root/lh-1-boundary" -exec touch -h --date="@$((cutoff - 1))" -- {} +
"$REAL_FIND" "$root/lh-2-boundary" -exec touch -h --date="@$cutoff" -- {} +
"$REAL_FIND" "$root/lh-3-boundary" -exec touch -h --date="@$cutoff.5" -- {} +
run_cleanup --delete
expect_status 0
contains 'cutoff=2026-03-17T12:00:00Z'
contains 'eligible=1 deleted=1'
absent "$root/lh-1-boundary"; exists "$root/lh-2-boundary"; exists "$root/lh-3-boundary"
pass '90-day cutoff is strict, including fractional-second timestamps'

new_case
for number in 1 2 3; do ticket "lh-$number-lookup" "$number"; done
state 1 ERROR
state 2 unexpected
run_cleanup --delete
expect_status 1
contains 'errors=2'
exists "$root/lh-1-lookup"; exists "$root/lh-2-lookup"; absent "$root/lh-3-lookup"
pass 'failed and malformed GitHub lookups retain affected entries and return failure'

new_case
for number in 1 2 3; do ticket "lh-$number-recheck" "$number"; done
printf 'open\n' > "$TEST_CONTROL/next-1"
printf 'ERROR\n' > "$TEST_CONTROL/next-2"
printf '%s\n' "$root/lh-3-recheck/logs/extracted/.hidden-log" > "$TEST_CONTROL/touch-3"
run_cleanup --delete
expect_status 1
contains 'GitHub state changed to open'
contains 'GitHub recheck failed'
contains 'local tree became active during cleanup'
contains 'deleted=0'
for number in 1 2 3; do exists "$root/lh-$number-recheck"; done
pass 'fresh GitHub and local checks retain reopened, unavailable, and newly active tickets'

new_case
ticket lh-1-first-copy 1
ticket longhorn_1_second-copy 1
run_cleanup --delete
expect_status 0
contains 'deleted=2'
read -r calls < "$TEST_CONTROL/calls-1"
[[ $calls == 3 ]] || fail 'Expected one cached discovery lookup plus one fresh lookup per deletion'
pass 'duplicate issue numbers cache discovery but recheck every deletion'

new_case
ticket lh-1-scan-error 1
ticket lh-2-device-error 2
export TEST_FIND_FAIL=$root/lh-1-scan-error TEST_OTHER_DEVICE=$root/lh-2-device-error
run_cleanup --delete
expect_status 1
contains 'errors=2'
exists "$root/lh-1-scan-error"; exists "$root/lh-2-device-error"
pass 'partial scans and different-device subtrees fail closed'

new_case
name=$'longhorn-1-space and\nnewline;$(false)'
ticket "$name" 1
run_cleanup --delete
expect_status 0
contains 'deleted=1'
absent "$root/$name"
pass 'whitespace, newlines, and shell metacharacters remain literal path data'

new_case
ticket lh-1-retain 1
for age in '0 days' '-2 months' 'tomorrow' '2' '1 hour' '999999999999999999999 years'; do
    run_cleanup --older-than "$age" --delete; expect_status 2; exists "$root/lh-1-retain"
done
run_cleanup --dry-run --delete; expect_status 2
run_cleanup --delete --dry-run; expect_status 2
run_cleanup --older-than; expect_status 2
run_cleanup --ticket-root; expect_status 2
run_cleanup --unknown; expect_status 2
mkdir -p "$case_root/not-ticket"
run_cleanup --ticket-root "$case_root/not-ticket" --delete; expect_status 3
ln -s "$root" "$case_root/ticket-link"
run_cleanup --ticket-root "$case_root/ticket-link/" --delete; expect_status 3
exists "$root/lh-1-retain"
[[ ! -f $TEST_CONTROL/requests ]] || fail 'Invalid invocation contacted GitHub'
pass 'invalid ages, missing arguments, conflicting modes, and unsafe roots cannot delete'

new_case
mkdir -p "$case_root/agent-skills"
printf '# Fixture workspace\n' > "$case_root/AGENTS.md"
ticket lh-1-default-root 1
if output=$(cd "$root/lh-1-default-root" && bash "$SCRIPT" 2>&1); then rc=0; else rc=$?; fi
expect_status 0
contains 'eligible=1 deleted=0'
exists "$root/lh-1-default-root"
pass 'workspace discovery works from inside a ticket without using the real workspace'

printf 'All %d test groups passed (offline; temporary fixtures only).\n' "$checks"
