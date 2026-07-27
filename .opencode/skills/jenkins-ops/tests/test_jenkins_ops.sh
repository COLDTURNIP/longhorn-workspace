#!/usr/bin/env bash
# Deterministic contract runner for the jenkins-ops skill.
# This file intentionally starts only the loopback Python fixture in fake modes.

set -u
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SKILL_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SKILL_DIR/../../.." && pwd)
FIXTURE="$SCRIPT_DIR/fake_jenkins.py"
EVIDENCE_ROOT=${JENKINS_OPS_EVIDENCE_DIR:-/tmp/jenkins-ops-evidence}
RUN_DIR=""
FIXTURE_PID=""
FIXTURE_PORT=""
FIXTURE_LOG=""
FIXTURE_OUT=""
FAKE_BIN=""
FAKE_SSH_LOG=""
FAKE_SLEEP_LOG=""
RUN_OUTPUT=""
RUN_STATUS=0
ORIGINAL_PATH=${PATH:-/usr/bin:/bin}
EVIDENCE_PATH=""
SSH_PUBLIC_KEY_FILE=""
SSH_PUBLIC_KEY_CONTENT=""

say() {
    printf '%s\n' "$*"
    if [ -n "${EVIDENCE_PATH:-}" ]; then
        printf '%s\n' "$*" >> "$EVIDENCE_PATH"
    fi
}
fail() { say "FAIL: $*" >&2; return 1; }
pass() { say "PASS: $*"; }

check_prerequisites() {
    case ${BASH_VERSINFO[0]:-0} in
        ''|[0-2]) fail "Bash 3.2 or newer is required"; return 3;;
    esac
    for command_name in python curl jq mktemp chmod; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            fail "Required command is unavailable: $command_name"
            return 3
        fi
    done
    if [ ! -d "$EVIDENCE_ROOT" ]; then
        if ! mkdir -m 700 -p "$EVIDENCE_ROOT"; then
            fail "Private temporary output is unavailable"
            return 3
        fi
    fi
    if ! chmod 700 "$EVIDENCE_ROOT"; then
        fail "Private temporary output is unavailable"
        return 3
    fi
    if [ ! -w "$EVIDENCE_ROOT" ]; then
        fail "Private temporary output is unavailable"
        return 3
    fi
    local probe
    probe=$(mktemp -d "$EVIDENCE_ROOT/prereq.XXXXXX") || {
        fail "Private temporary output is unavailable"
        return 3
    }
    chmod 700 "$probe" || {
        rm -rf "$probe"
        fail "Private temporary output is unavailable"
        return 3
    }
    rm -rf "$probe"
    if [ ! -f "$FIXTURE" ]; then
        fail "Missing fake Jenkins fixture: $FIXTURE"
        return 3
    fi
    return 0
}

make_fake_tools() {
    FAKE_BIN=$(mktemp -d "$RUN_DIR/fake-bin.XXXXXX") || return 1
    chmod 700 "$FAKE_BIN" || return 1
    FAKE_SSH_LOG="$RUN_DIR/fake-ssh.log"
    FAKE_SLEEP_LOG="$RUN_DIR/fake-sleep.log"
    : > "$FAKE_SSH_LOG"
    : > "$FAKE_SLEEP_LOG"
    cat > "$FAKE_BIN/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >> "$FAKE_SSH_LOG"
if [ "${FAKE_SSH_EXIT:-0}" -ne 0 ]; then
    exit "$FAKE_SSH_EXIT"
fi
exit 0
FAKE_SSH
    cat > "$FAKE_BIN/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SLEEP_LOG"
# Tests must not spend real time waiting for deterministic queue fixtures.
exit 0
FAKE_SLEEP
    chmod 700 "$FAKE_BIN/ssh" "$FAKE_BIN/sleep" || return 1
    export FAKE_SSH_LOG FAKE_SLEEP_LOG
    export PATH="$FAKE_BIN:$PATH"
    return 0
}

start_fixture() {
    local mode=${1:-normal}
    stop_fixture >/dev/null 2>&1 || true
    FIXTURE_LOG="$RUN_DIR/fixture-${mode}.jsonl"
    FIXTURE_OUT="$RUN_DIR/fixture-${mode}.ready"
    : > "$FIXTURE_LOG"
    : > "$FIXTURE_OUT"
    python "$FIXTURE" --bind 127.0.0.1 --port 0 --ready-file "$FIXTURE_OUT" --request-log "$FIXTURE_LOG" --mode "$mode" >"$RUN_DIR/fixture-${mode}.out" 2>"$RUN_DIR/fixture-${mode}.err" &
    FIXTURE_PID=$!
    local attempt
    FIXTURE_PORT=""
    attempt=0
    while [ "$attempt" -lt 100 ]; do
        if [ -s "$FIXTURE_OUT" ]; then
            FIXTURE_PORT=$(cat "$FIXTURE_OUT")
            if [ -n "$FIXTURE_PORT" ]; then
                break
            fi
        fi
        attempt=$((attempt + 1))
        PATH="$ORIGINAL_PATH" sleep 0.01
    done
    if [ -z "$FIXTURE_PORT" ]; then
        fail "Fake Jenkins fixture did not publish an ephemeral port"
        return 1
    fi
    export JENKINS_URL="http://127.0.0.1:$FIXTURE_PORT"
    export JENKINS_USER="dummy-user"
    export JENKINS_TOKEN="dummy-token"
    unset JENKINS_NOTIFY_SLACK_CHANNEL
    return 0
}

stop_fixture() {
    if [ -n "${FIXTURE_PID:-}" ]; then
        kill "$FIXTURE_PID" >/dev/null 2>&1 || true
        wait "$FIXTURE_PID" >/dev/null 2>&1 || true
        FIXTURE_PID=""
    fi
}

cleanup() {
    stop_fixture
    if [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ]; then
        rm -rf "$RUN_DIR"
    fi
}

require_script() {
    local script_name=$1
    if [ ! -x "$SKILL_DIR/scripts/$script_name" ]; then
        fail "Missing Jenkins operation script: $SKILL_DIR/scripts/$script_name"
        return 99
    fi
    return 0
}

run_capture() {
    RUN_OUTPUT="$RUN_DIR/command-output"
    : > "$RUN_OUTPUT"
    "$@" >"$RUN_OUTPUT" 2>&1
    RUN_STATUS=$?
    if [ -n "${EVIDENCE_PATH:-}" ]; then
        redacted_output >> "$EVIDENCE_PATH"
        printf '\n' >> "$EVIDENCE_PATH"
    fi
    return 0
}

run_capture_env() {
    RUN_OUTPUT="$RUN_DIR/command-output"
    : > "$RUN_OUTPUT"
    env "$@" >"$RUN_OUTPUT" 2>&1
    RUN_STATUS=$?
    if [ -n "${EVIDENCE_PATH:-}" ]; then
        redacted_output >> "$EVIDENCE_PATH"
        printf '\n' >> "$EVIDENCE_PATH"
    fi
    return 0
}

output_text() { cat "$RUN_OUTPUT" 2>/dev/null || true; }
redacted_output() {
    SAFE_OUTPUT=$(output_text)
    SAFE_OUTPUT=${SAFE_OUTPUT//dummy-token/[REDACTED]}
    SAFE_OUTPUT=${SAFE_OUTPUT//dummy-user/[REDACTED]}
    if [ -n "${JENKINS_URL:-}" ]; then
        SAFE_OUTPUT=${SAFE_OUTPUT//${JENKINS_URL}/[REDACTED]}
    fi
    printf '%s' "$SAFE_OUTPUT"
}


assert_status() {
    local expected=$1 label=$2
    if [ "$RUN_STATUS" -ne "$expected" ]; then
        fail "$label (expected exit $expected, got $RUN_STATUS): $(redacted_output)"
        return 1
    fi
    return 0
}

assert_output_absent() {
    local needle=$1 label=$2 text
    text=$(output_text)
    case "$text" in
        *"$needle"*) fail "$label (secret or forbidden value was printed)"; return 1;;
    esac
    return 0
}
assert_file_absent() {
    local file=$1 needle=$2 label=$3 text
    text=$(cat "$file" 2>/dev/null || true)
    case "$text" in
        *"$needle"*) fail "$label (secret or forbidden value was persisted)"; return 1;;
    esac
    return 0
}


read_path_output() {
    local path
    path=$(cat "$RUN_OUTPUT" 2>/dev/null || true)
    case "$path" in
        /*) printf '%s\n' "$path";;
        *) return 1;;
    esac
}

assert_private_path() {
    local label=$1 path mode
    path=$(read_path_output) || {
        fail "$label did not print one absolute path"
        return 1
    }
    if [ ! -f "$path" ]; then
        fail "$label path does not name a file"
        return 1
    fi
    mode=$(python -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$path") || return 1
    if [ "$mode" != "0o600" ]; then
        fail "$label output mode is $mode, expected 0o600"
        return 1
    fi
    printf '%s\n' "$path"
}

assert_private_dir() {
    local path=$1 mode
    [ -d "$path" ] || return 1
    mode=$(python -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$path") || return 1
    [ "$mode" = "0o700" ]
}

assert_json_file() {
    local file=$1 expression=$2 label=$3
    if ! jq -e "$expression" "$file" >/dev/null 2>&1; then
        fail "$label schema assertion failed"
        return 1
    fi
    return 0
}

assert_json_stdout() {
    local expression=$1 label=$2
    if ! jq -e "$expression" "$RUN_OUTPUT" >/dev/null 2>&1; then
        fail "$label schema assertion failed: $(redacted_output)"
        return 1
    fi
    return 0
}

assert_log() {
    local expression=$1 label=$2
    if ! jq -e -s "$expression" "$FIXTURE_LOG" >/dev/null 2>&1; then
        fail "$label request assertion failed"
        return 1
    fi
    return 0
}

assert_no_post() {
    assert_log 'all(.[]; .method != "POST")' "no mutating request"
}

assert_all_get() { assert_no_post; }

clear_log() { : > "$FIXTURE_LOG"; }

setup_run() {
    check_prerequisites || return $?
    RUN_DIR=$(mktemp -d "$EVIDENCE_ROOT/run.XXXXXX") || {
        fail "Private temporary output is unavailable"
        return 3
    }
    chmod 700 "$RUN_DIR" || return 3
    make_fake_tools || return 3
    export JENKINS_USER=dummy-user JENKINS_TOKEN=dummy-token
    return 0
}

catalog_scripts_present() {
    local name
    for name in list_jobs.sh list_builds.sh resolve_build.sh get_job_parameters.sh trigger_job.sh get_build_status.sh wait_for_build.sh wait_for_job_host.sh inspect_build.sh get_artifact.sh ssh_job_host.sh; do
        require_script "$name" || return 1
    done
    return 0
}

read_mode() {
    local script path before count
    require_script list_jobs.sh || return $?
    require_script get_job_parameters.sh || return $?
    start_fixture normal || return 4

    run_capture "$SKILL_DIR/scripts/list_jobs.sh"
    assert_status 0 "list jobs" || return 1
    assert_json_stdout '(. | keys) == ["jobs"] and (.jobs | length) == 3 and [.jobs[].alias] == ["regression","e2e","benchmark"] and all(.jobs[]; (.path|type)=="string" and (.pipeline|type)=="string" and (.testSource|type)=="string" and (.runner|type)=="string") and .jobs[0].path=="private/longhorn-tests-regression" and .jobs[0].pipeline=="repo/longhorn-tests/test_framework/Jenkinsfile" and .jobs[0].testSource=="external image: LONGHORN_TESTS_CUSTOM_IMAGE" and .jobs[0].runner=="PyTest" and .jobs[1].path=="private/longhorn-e2e-test" and .jobs[1].pipeline=="repo/longhorn-tests/pipelines/e2e/Jenkinsfile" and .jobs[1].testSource=="external image: LONGHORN_TESTS_CUSTOM_IMAGE" and .jobs[1].runner=="Robot Framework" and .jobs[2].path=="private/longhorn-benchmark-test" and .jobs[2].pipeline=="repo/longhorn-tests/benchmark_test/Jenkinsfile" and .jobs[2].testSource=="checkout: benchmark_test scripts and manifests" and .jobs[2].runner=="kbench"' "list jobs" || return 1
    assert_output_absent dummy-token "list jobs output" || return 1
    assert_output_absent "$JENKINS_URL" "list jobs output" || return 1
    assert_output_absent longhorn-e2e-test-pull-request-check "excluded job output" || return 1

    for script in regression e2e benchmark; do
        run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" "$script"
        assert_status 0 "get parameters $script" || return 1
        path=$(assert_private_path "get parameters $script") || return 1
        assert_private_dir "$(dirname "$path")" || { fail "parameter directory mode"; return 1; }
        assert_json_file "$path" '(. | keys) == ["buildable","job","parameters"] and (.job|type)=="string" and (.buildable|type)=="boolean" and (.parameters|type)=="array" and ([.parameters[].name] | sort) == [.parameters[].name]' "parameter $script" || return 1
        assert_json_file "$path" 'all(.parameters[]; ((keys|sort)==["choices","default","description","name","type"]) and (.name|type)=="string" and (.type|type)=="string" and (.description|type)=="string" and ((.default|keys|sort)==["present","value"]))' "parameter fields $script" || return 1
        assert_output_absent dummy-token "parameter $script output" || return 1
        assert_output_absent "$JENKINS_URL" "parameter $script output" || return 1
        assert_file_absent "$path" dummy-token "parameter $script file" || return 1
    done
    assert_log 'all(.[]; (.method=="GET") and ((.query|contains("tree=name")) or (.path|endswith("/crumbIssuer/api/json"))))' "read query contract"
    assert_all_get

    clear_log
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" unknown-alias
    assert_status 2 "unknown alias" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "unknown alias contacted fixture"; return 1; }

    export JENKINS_URL="http://127.0.0.1:$FIXTURE_PORT bad"
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    case "$RUN_STATUS" in 2|3|4) ;; *) fail "URL rejection (got $RUN_STATUS)"; return 1;; esac
    [ ! -s "$FIXTURE_LOG" ] || { fail "rejected URL contacted fixture"; return 1; }
    export JENKINS_URL="http://127.0.0.1:$FIXTURE_PORT"

    unset JENKINS_TOKEN
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 3 "missing Jenkins token" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "missing env contacted fixture"; return 1; }
    export JENKINS_TOKEN=dummy-token

    start_fixture get-retry-once || return 4
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 0 "GET retry" || return 1
    count=$(jq -s '[.[] | select(.method=="GET" and (.path|endswith("/api/json")))] | length' "$FIXTURE_LOG")
    [ "$count" -eq 2 ] || { fail "GET retry count was $count"; return 1; }
    assert_all_get

    start_fixture malformed-definitions || return 4
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 4 "malformed parameter definitions" || return 1
    assert_all_get
    start_fixture duplicate-conflict || return 4
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 4 "conflicting duplicate definitions" || return 1
    assert_all_get

    start_fixture raw-types || return 4
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 0 "all recognized raw parameter types" || return 1
    path=$(assert_private_path "raw parameter definitions") || return 1
    assert_json_file "$path" '([.parameters[].type] | index("BooleanParameterDefinition")) != null and ([.parameters[].type] | index("StringParameterDefinition")) != null and ([.parameters[].type] | index("TextParameterDefinition")) != null and ([.parameters[].type] | index("ChoiceParameterDefinition")) != null and ([.parameters[].type] | index("PasswordParameterDefinition")) != null' "recognized raw types" || return 1
    assert_json_file "$path" 'all(.parameters[] | select(.name|test("TOKEN|PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY"; "i")); .default.value=="[REDACTED]")' "sensitive default redaction" || return 1
    assert_output_absent dummy-token "raw parameter definitions" || return 1

    start_fixture duplicate-identical || return 4
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 0 "identical duplicate definitions" || return 1
    path=$(assert_private_path "identical duplicate definitions") || return 1
    assert_json_file "$path" '([.parameters[] | select(.name=="CUSTOM_TEST_OPTIONS")] | length) == 1' "duplicate collapse" || return 1

    start_fixture buildable-false || return 4
    run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 0 "nonbuildable read" || return 1
    path=$(assert_private_path "nonbuildable read") || return 1
    assert_json_file "$path" '.buildable == false' "nonbuildable schema" || return 1

    for read_case in http-401 http-403-read http-404 http-500 get-retry-exhausted; do
        start_fixture "$read_case" || return 4
        run_capture "$SKILL_DIR/scripts/get_job_parameters.sh" regression
        assert_status 4 "read failure $read_case" || return 1
        assert_output_absent dummy-token "read failure $read_case" || return 1
        if [ "$read_case" = "http-500" ] || [ "$read_case" = "get-retry-exhausted" ]; then
            count=$(jq -s '[.[] | select(.method=="GET" and (.path|endswith("/api/json")))] | length' "$FIXTURE_LOG")
            [ "$count" -eq 2 ] || { fail "retry count for $read_case was $count"; return 1; }
        else
            count=$(jq -s '[.[] | select(.method=="GET" and (.path|endswith("/api/json")))] | length' "$FIXTURE_LOG")
            [ "$count" -eq 1 ] || { fail "unexpected retry count for $read_case: $count"; return 1; }
        fi
    done


    start_fixture normal || return 4
    bad_tmp="$RUN_DIR/not-a-directory"
    : > "$bad_tmp"
    run_capture env TMPDIR="$bad_tmp" "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 3 "unwritable temporary output" || return 1
    run_capture_env PATH="$FAKE_BIN" "$BASH" "$SKILL_DIR/scripts/get_job_parameters.sh" regression
    assert_status 3 "missing dependency" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "local prerequisite failures contacted fixture"; return 1; }

    pass "read contracts"
    return 0
}

trigger_mode() {
    local path count notify_alias trigger_alias missing_key_file empty_key_file invalid_key_file tilde_home tilde_key_name tilde_key_file tilde_key_ref tilde_key_content
    require_script trigger_job.sh || return $?
    require_script get_job_parameters.sh || return $?
    start_fixture normal || return 4
    clear_log
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" unknown CUSTOM_TEST_OPTIONS=value
    assert_status 2 "unknown trigger alias" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "unknown trigger alias contacted fixture"; return 1; }
    start_fixture normal || return 4

    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression 'CUSTOM_TEST_OPTIONS=-i negative --exclude cluster'
    assert_status 0 "regression dry-run" || return 1
    path=$(assert_private_path "regression launch plan") || return 1
    assert_private_dir "$(dirname "$path")" || return 1
    assert_json_file "$path" '(. | keys) == ["buildable","job","parameters","warnings"] and .buildable == true and .job == "regression" and (.parameters|type)=="array" and (.warnings|type)=="array" and ([.parameters[].name] | sort) == [.parameters[].name]' "launch plan" || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_TEST_OPTIONS" and .value == "-i negative --exclude cluster" and .source == "override")' "quoted test options" || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_SSH_PUBLIC_KEY" and .value == "fixture-public-key-content" and .source == "override")' "regression managed SSH key injection" || return 1
    assert_json_file "$path" "all(.parameters[]; .name != \"CUSTOM_SSH_PUBLIC_KEY\" or .value != \"$SSH_PUBLIC_KEY_FILE\")" "regression managed SSH key path exclusion" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "regression dry-run SSH key content" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_FILE" "regression dry-run SSH key path" || return 1

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e 'CUSTOM_TEST_OPTIONS=-t "Backup Listing With More Than 1000 Backups" -v PATH:C:\data'
    assert_status 0 "raw quoted CUSTOM_TEST_OPTIONS dry-run" || return 1
    path=$(assert_private_path "raw quoted CUSTOM_TEST_OPTIONS launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_TEST_OPTIONS" and .value == "-t \\\"Backup Listing With More Than 1000 Backups\\\" -v PATH:C:\\\\\\\\data" and .source == "override")' "pipeline-escaped CUSTOM_TEST_OPTIONS" || return 1

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e 'CUSTOM_TEST_OPTIONS=-v PATH:"C:\"'
    assert_status 0 "backslash before quote CUSTOM_TEST_OPTIONS dry-run" || return 1
    path=$(assert_private_path "backslash before quote CUSTOM_TEST_OPTIONS launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_TEST_OPTIONS" and .source == "override" and (.value | startswith("-v PATH:\\\"C:")) and ((.value | explode)[-6:] == [92,92,92,92,92,34]))' "literal backslash before quote transport escaping" || return 1

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e 'CUSTOM_TEST_OPTIONS=-i "negative*"'
    assert_status 0 "quoted pattern CUSTOM_TEST_OPTIONS dry-run" || return 1
    path=$(assert_private_path "quoted pattern CUSTOM_TEST_OPTIONS launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_TEST_OPTIONS" and .value == "-i \\\"negative*\\\"")' "quoted pattern CUSTOM_TEST_OPTIONS escaping" || return 1


    for unsafe_options in \
        'CUSTOM_TEST_OPTIONS=-i negative; touch injected' \
        'CUSTOM_TEST_OPTIONS=-i $(touch injected)' \
        'CUSTOM_TEST_OPTIONS=-i `touch injected`' \
        'CUSTOM_TEST_OPTIONS=-t "unmatched' \
        'CUSTOM_TEST_OPTIONS=-i negative*' \
        'CUSTOM_TEST_OPTIONS=-i negative?' \
        'CUSTOM_TEST_OPTIONS=-i [negative]' \
        'CUSTOM_TEST_OPTIONS=-i {negative,positive}' \
        'CUSTOM_TEST_OPTIONS=-v PATH:~' \
        'CUSTOM_TEST_OPTIONS=-i negative#comment' \
        'CUSTOM_TEST_OPTIONS=-t \"foo bar\" --exclude x' \
        'CUSTOM_TEST_OPTIONS=-t "foo\"bar"'; do
        start_fixture normal || return 4
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e "$unsafe_options"
        assert_status 2 "unsafe CUSTOM_TEST_OPTIONS refusal" || return 1
        count=$(jq -s '[.[] | select(.method=="POST")] | length' "$FIXTURE_LOG")
        [ "$count" -eq 0 ] || { fail "unsafe CUSTOM_TEST_OPTIONS issued POST"; return 1; }
    done

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e $'CUSTOM_TEST_OPTIONS=-i negative\n--exclude cluster'
    assert_status 2 "control character CUSTOM_TEST_OPTIONS refusal" || return 1
    count=$(jq -s '[.[] | select(.method=="POST")] | length' "$FIXTURE_LOG")
    [ "$count" -eq 0 ] || { fail "control character CUSTOM_TEST_OPTIONS issued POST"; return 1; }

    start_fixture post-201 || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute regression 'CUSTOM_TEST_OPTIONS=-t "Backup Listing With More Than 1000 Backups" -v PATH:C:\data'
    assert_status 0 "pipeline-escaped CUSTOM_TEST_OPTIONS execute" || return 1
    assert_log '([.[] | select(.method=="POST")] | length) == 1 and all(.[] | select(.method=="POST"); any(.form[]; .name=="CUSTOM_TEST_OPTIONS" and .value=="-t \\\"Backup Listing With More Than 1000 Backups\\\" -v PATH:C:\\\\\\\\data"))' "pipeline-escaped CUSTOM_TEST_OPTIONS POST" || return 1
    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e
    assert_status 0 "e2e dry-run" || return 1
    path=$(assert_private_path "e2e launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_SSH_PUBLIC_KEY" and .value == "fixture-public-key-content" and .source == "override")' "e2e managed SSH key injection" || return 1
    assert_json_file "$path" "all(.parameters[]; .name != \"CUSTOM_SSH_PUBLIC_KEY\" or .value != \"$SSH_PUBLIC_KEY_FILE\")" "e2e managed SSH key path exclusion" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "e2e dry-run SSH key content" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_FILE" "e2e dry-run SSH key path" || return 1
    assert_file_absent "$path" dummy-token "launch-plan file" || return 1
    assert_all_get
    count=$(jq -s '[.[] | select(.method=="POST")] | length' "$FIXTURE_LOG")
    [ "$count" -eq 0 ] || { fail "dry-run issued POST"; return 1; }

    for notify_alias in regression e2e benchmark; do
        start_fixture normal || return 4
        export JENKINS_NOTIFY_SLACK_CHANNEL=C0123456789
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" "$notify_alias"
        assert_status 0 "Slack notification dry-run $notify_alias" || return 1
        path=$(assert_private_path "Slack notification launch plan $notify_alias") || return 1
        assert_json_file "$path" 'any(.parameters[]; .name=="SEND_SLACK_NOTIFICATION" and .value==true and .source=="override") and any(.parameters[]; .name=="NOTIFY_SLACK_CHANNEL" and .value=="C0123456789" and .source=="override")' "Slack notification launch plan $notify_alias" || return 1
        if [ "$notify_alias" = benchmark ]; then
            assert_json_file "$path" 'all(.parameters[]; .name != "CUSTOM_SSH_PUBLIC_KEY")' "benchmark Slack dry-run has no managed SSH key" || return 1
        else
            assert_json_file "$path" 'any(.parameters[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="fixture-public-key-content" and .source=="override")' "Slack dry-run managed SSH key $notify_alias" || return 1
        fi
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "Slack dry-run SSH key content $notify_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "Slack dry-run SSH key path $notify_alias" || return 1
        assert_output_absent C0123456789 "Slack notification dry-run output $notify_alias" || return 1
        count=$(jq -s '[.[] | select(.method=="POST")] | length' "$FIXTURE_LOG")
        [ "$count" -eq 0 ] || { fail "Slack notification dry-run issued POST for $notify_alias"; return 1; }
    done

    start_fixture normal || return 4
    export JENKINS_NOTIFY_SLACK_CHANNEL=C0123456789
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression SEND_SLACK_NOTIFICATION=false
    assert_status 2 "managed Slack Boolean override refusal" || return 1
    assert_output_absent C0123456789 "managed Slack Boolean override refusal" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression NOTIFY_SLACK_CHANNEL=other
    assert_status 2 "managed Slack channel override refusal" || return 1
    assert_output_absent C0123456789 "managed Slack channel override refusal" || return 1
    for trigger_alias in regression e2e; do
        start_fixture normal || return 4
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias" CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
        assert_status 0 "managed SSH key caller override $trigger_alias" || return 1
        path=$(assert_private_path "managed SSH key caller override launch plan $trigger_alias") || return 1
        assert_json_file "$path" '([.parameters[] | select(.name=="CUSTOM_SSH_PUBLIC_KEY")] | length) == 1 and any(.parameters[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="caller-public-key-content" and .source=="override") and all(.parameters[]; .name!="CUSTOM_SSH_PUBLIC_KEY" or .value!="fixture-public-key-content")' "managed SSH key caller precedence $trigger_alias" || return 1
        assert_file_absent "$path" "$SSH_PUBLIC_KEY_CONTENT" "managed SSH key env content in launch plan $trigger_alias" || return 1
        assert_output_absent caller-public-key-content "managed SSH key caller override output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "managed SSH key env content output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "managed SSH key env path output $trigger_alias" || return 1
        assert_all_get
    done

    for trigger_alias in regression e2e; do
        start_fixture normal || return 4
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias" CUSTOM_SSH_PUBLIC_KEY=first-caller-public-key-content CUSTOM_SSH_PUBLIC_KEY=second-caller-public-key-content
        assert_status 2 "duplicate managed SSH key caller override $trigger_alias" || return 1
        assert_output_absent first-caller-public-key-content "duplicate managed SSH key first caller output $trigger_alias" || return 1
        assert_output_absent second-caller-public-key-content "duplicate managed SSH key second caller output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "duplicate managed SSH key env content output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "duplicate managed SSH key env path output $trigger_alias" || return 1
        assert_all_get
    done

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" benchmark CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
    assert_status 2 "unsupported managed SSH key caller override" || return 1
    assert_output_absent caller-public-key-content "unsupported managed SSH key caller override output" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "unsupported managed SSH key env content output" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_FILE" "unsupported managed SSH key env path output" || return 1
    assert_all_get

    for trigger_alias in regression e2e; do
        start_fixture normal || return 4
        run_capture_env -u JENKINS_SSH_PUBLIC_KEY "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias" CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
        assert_status 0 "caller SSH key with unset environment $trigger_alias" || return 1
        path=$(assert_private_path "caller SSH key with unset environment launch plan $trigger_alias") || return 1
        assert_json_file "$path" '([.parameters[] | select(.name=="CUSTOM_SSH_PUBLIC_KEY")] | length) == 1 and any(.parameters[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="caller-public-key-content" and .source=="override") and all(.parameters[]; .name!="CUSTOM_SSH_PUBLIC_KEY" or .value!="fixture-public-key-content")' "caller SSH key with unset environment precedence $trigger_alias" || return 1
        assert_file_absent "$path" "$SSH_PUBLIC_KEY_CONTENT" "caller SSH key with unset environment env content $trigger_alias" || return 1
        assert_output_absent caller-public-key-content "caller SSH key with unset environment output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "caller SSH key with unset environment managed content $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "caller SSH key with unset environment managed path $trigger_alias" || return 1
        assert_all_get

        start_fixture normal || return 4
        run_capture_env JENKINS_SSH_PUBLIC_KEY= "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias" CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
        assert_status 0 "caller SSH key with empty environment $trigger_alias" || return 1
        path=$(assert_private_path "caller SSH key with empty environment launch plan $trigger_alias") || return 1
        assert_json_file "$path" '([.parameters[] | select(.name=="CUSTOM_SSH_PUBLIC_KEY")] | length) == 1 and any(.parameters[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="caller-public-key-content" and .source=="override") and all(.parameters[]; .name!="CUSTOM_SSH_PUBLIC_KEY" or .value!="fixture-public-key-content")' "caller SSH key with empty environment precedence $trigger_alias" || return 1
        assert_file_absent "$path" "$SSH_PUBLIC_KEY_CONTENT" "caller SSH key with empty environment env content $trigger_alias" || return 1
        assert_output_absent caller-public-key-content "caller SSH key with empty environment output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "caller SSH key with empty environment managed content $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "caller SSH key with empty environment managed path $trigger_alias" || return 1
        assert_all_get
    done

    missing_key_file="$RUN_DIR/missing-ssh-public-key"
    empty_key_file="$RUN_DIR/empty-ssh-public-key"
    invalid_key_file="$RUN_DIR/invalid-ssh-public-key"
    : > "$empty_key_file" || return 3
    mkdir "$invalid_key_file" || return 3
    for trigger_alias in regression e2e; do
        start_fixture normal || return 4
        run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias" CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
        assert_status 0 "caller SSH key bypasses missing environment file $trigger_alias" || return 1
        path=$(assert_private_path "caller SSH key bypasses missing environment file launch plan $trigger_alias") || return 1
        assert_json_file "$path" '([.parameters[] | select(.name=="CUSTOM_SSH_PUBLIC_KEY")] | length) == 1 and any(.parameters[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="caller-public-key-content" and .source=="override") and all(.parameters[]; .name!="CUSTOM_SSH_PUBLIC_KEY" or .value!="fixture-public-key-content")' "caller SSH key bypasses missing environment file precedence $trigger_alias" || return 1
        assert_file_absent "$path" "$SSH_PUBLIC_KEY_CONTENT" "caller SSH key bypasses missing environment file env content $trigger_alias" || return 1
        assert_output_absent caller-public-key-content "caller SSH key bypasses missing environment file output $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "caller SSH key bypasses missing environment file managed content $trigger_alias" || return 1
        assert_output_absent "$missing_key_file" "caller SSH key bypasses missing environment file path $trigger_alias" || return 1
        assert_all_get
    done


    for trigger_alias in regression e2e; do
        start_fixture normal || return 4
        run_capture_env -u JENKINS_SSH_PUBLIC_KEY "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias"
        assert_status 0 "unset SSH public key environment $trigger_alias" || return 1
        path=$(assert_private_path "unset SSH public key launch plan $trigger_alias") || return 1
        assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_SSH_PUBLIC_KEY" and .value == "" and .source == "jenkins-default")' "unset SSH public key uses empty Jenkins default $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "unset SSH public key environment content $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "unset SSH public key environment path $trigger_alias" || return 1
        assert_all_get

        start_fixture normal || return 4
        run_capture_env JENKINS_SSH_PUBLIC_KEY= "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias"
        assert_status 0 "empty SSH public key environment $trigger_alias" || return 1
        path=$(assert_private_path "empty SSH public key launch plan $trigger_alias") || return 1
        assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_SSH_PUBLIC_KEY" and .value == "" and .source == "jenkins-default")' "empty SSH public key uses empty Jenkins default $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "empty SSH public key environment content $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "empty SSH public key environment path $trigger_alias" || return 1
        assert_all_get

        start_fixture normal || return 4
        run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias"
        assert_status 3 "unavailable SSH public key file $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "unavailable SSH public key file content $trigger_alias" || return 1
        assert_output_absent "$missing_key_file" "unavailable SSH public key file path $trigger_alias" || return 1
        assert_all_get

        start_fixture normal || return 4
        run_capture_env JENKINS_SSH_PUBLIC_KEY="$invalid_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias"
        assert_status 3 "invalid SSH public key file $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "invalid SSH public key file content $trigger_alias" || return 1
        assert_output_absent "$invalid_key_file" "invalid SSH public key file path $trigger_alias" || return 1
        assert_all_get

        start_fixture normal || return 4
        run_capture_env JENKINS_SSH_PUBLIC_KEY="$empty_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" "$trigger_alias"
        assert_status 3 "empty SSH public key file $trigger_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "empty SSH public key file content $trigger_alias" || return 1
        assert_output_absent "$empty_key_file" "empty SSH public key file path $trigger_alias" || return 1
        assert_all_get
    done
    tilde_home="$RUN_DIR/tilde-home"
    tilde_key_name=".ssh/tilde-public-key"
    tilde_key_file="$tilde_home/$tilde_key_name"
    tilde_key_ref="~/$tilde_key_name"
    tilde_key_content='tilde-public-key-content'
    mkdir -p "$(dirname "$tilde_key_file")" || return 3
    printf '%s\n' "$tilde_key_content" > "$tilde_key_file" || return 3
    chmod 600 "$tilde_key_file" || return 3
    start_fixture normal || return 4
    run_capture_env HOME="$tilde_home" JENKINS_SSH_PUBLIC_KEY="$tilde_key_ref" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" regression
    assert_status 0 "tilde SSH public key environment" || return 1
    path=$(assert_private_path "tilde SSH public key launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name == "CUSTOM_SSH_PUBLIC_KEY" and .value == "tilde-public-key-content" and .source == "override")' "tilde SSH public key injection" || return 1
    assert_json_file "$path" "all(.parameters[]; .name != \"CUSTOM_SSH_PUBLIC_KEY\" or .value != \"$tilde_key_file\")" "tilde SSH public key path exclusion" || return 1
    assert_output_absent "$tilde_key_content" "tilde SSH public key content" || return 1
    assert_output_absent "$tilde_key_ref" "tilde SSH public key shorthand" || return 1
    assert_output_absent "$tilde_key_file" "tilde SSH public key path" || return 1
    assert_all_get


    start_fixture ssh-key-missing || return 4
    run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" regression
    assert_status 0 "missing managed SSH key Jenkins parameter is optional" || return 1
    path=$(assert_private_path "missing managed SSH key launch plan") || return 1
    assert_json_file "$path" 'all(.parameters[]; .name != "CUSTOM_SSH_PUBLIC_KEY")' "missing managed SSH key has no injected parameter" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "missing managed SSH key Jenkins parameter content" || return 1
    assert_output_absent "$missing_key_file" "missing managed SSH key Jenkins parameter path" || return 1
    assert_all_get


    start_fixture normal || return 4
    export JENKINS_NOTIFY_SLACK_CHANNEL=
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression
    assert_status 0 "empty Slack channel dry-run" || return 1
    path=$(assert_private_path "empty Slack channel launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name=="SEND_SLACK_NOTIFICATION" and .value==true and .source=="jenkins-default") and any(.parameters[]; .name=="NOTIFY_SLACK_CHANNEL" and .value=="" and .source=="jenkins-default")' "empty Slack channel uses Jenkins defaults" || return 1

    for notify_alias in regression e2e benchmark; do
        start_fixture post-201 || return 4
        export JENKINS_NOTIFY_SLACK_CHANNEL=C0123456789
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute "$notify_alias"
        assert_status 0 "Slack notification execute $notify_alias" || return 1
        assert_output_absent C0123456789 "Slack notification execute output $notify_alias" || return 1
        assert_log '([.[] | select(.method=="POST")] | length)==1 and all(.[] | select(.method=="POST"); any(.form[]; .name=="SEND_SLACK_NOTIFICATION" and .value=="true") and any(.form[]; .name=="NOTIFY_SLACK_CHANNEL" and .value=="C0123456789"))' "Slack notification POST $notify_alias" || return 1
        if [ "$notify_alias" = benchmark ]; then
            assert_log 'all(.[] | select(.method=="POST"); all(.form[]; .name != "CUSTOM_SSH_PUBLIC_KEY"))' "benchmark Slack notification has no managed SSH key" || return 1
        else
            assert_log 'all(.[] | select(.method=="POST"); any(.form[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="fixture-public-key-content"))' "managed SSH key POST $notify_alias" || return 1
        fi
        assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "execute SSH key content $notify_alias" || return 1
        assert_output_absent "$SSH_PUBLIC_KEY_FILE" "execute SSH key path $notify_alias" || return 1
    done
    start_fixture normal || return 4
    run_capture_env -u JENKINS_SSH_PUBLIC_KEY "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" benchmark
    assert_status 0 "benchmark dry-run without SSH public key environment" || return 1
    path=$(assert_private_path "benchmark launch plan without SSH public key environment") || return 1
    assert_json_file "$path" 'all(.parameters[]; .name != "CUSTOM_SSH_PUBLIC_KEY")' "benchmark launch plan has no managed SSH key" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "benchmark dry-run without SSH public key content" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_FILE" "benchmark dry-run without SSH public key path" || return 1
    assert_all_get
    start_fixture normal || return 4
    run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" benchmark
    assert_status 0 "benchmark ignores invalid SSH public key file" || return 1
    path=$(assert_private_path "benchmark launch plan with invalid SSH public key file") || return 1
    assert_json_file "$path" 'all(.parameters[]; .name != "CUSTOM_SSH_PUBLIC_KEY")' "benchmark invalid SSH public key has no managed key" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "benchmark invalid SSH public key content" || return 1
    assert_output_absent "$missing_key_file" "benchmark invalid SSH public key path" || return 1
    assert_all_get

    start_fixture post-201 || return 4
    run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" --execute benchmark
    assert_status 0 "benchmark execute ignores SSH public key environment" || return 1
    assert_json_stdout '(.job == "benchmark") and (.state == "QUEUED") and (.queueId > 0)' "benchmark execute env-only result" || return 1
    assert_log '([.[] | select(.method=="POST")] | length)==1 and all(.[] | select(.method=="POST"); all(.form[]; .name != "CUSTOM_SSH_PUBLIC_KEY"))' "benchmark execute env-only has no managed SSH key" || return 1
    assert_output_absent "$missing_key_file" "benchmark execute env-only SSH key path" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "benchmark execute env-only SSH key content" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_FILE" "benchmark execute env-only managed SSH key path" || return 1
    start_fixture e2e-false-explicit || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e RUN_V2_TEST=false
    assert_status 2 "e2e false override refusal" || return 1
    assert_output_absent dummy-token "e2e refusal" || return 1
    case $(output_text) in
        *"Current pipelines/e2e/Jenkinsfile coerces RUN_V2_TEST=false to true; this wrapper refuses that effective value."*) ;;
        *) fail "e2e explicit false did not emit the exact warning"; return 1;;
    esac
    assert_all_get
    start_fixture e2e-false-omitted || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e
    assert_status 2 "e2e false default refusal" || return 1
    assert_all_get
    case $(output_text) in
        *"Current pipelines/e2e/Jenkinsfile coerces RUN_V2_TEST=false to true; this wrapper refuses that effective value."*) ;;
        *) fail "e2e default false did not emit the exact warning"; return 1;;
    esac

    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression 'CUSTOM_TEST_OPTIONS=a=b=c'
    assert_status 0 "first-equals preservation" || return 1
    path=$(assert_private_path "first-equals launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name=="CUSTOM_TEST_OPTIONS" and .value=="a=b=c")' "first-equals value" || return 1
    assert_json_file "$path" 'all(.parameters[]; ((.value|tostring|contains("dummy-token"))|not))' "launch-plan secret redaction" || return 1

    run_capture "$SKILL_DIR/scripts/trigger_job.sh" benchmark TEST_SIZE=not-a-choice
    assert_status 2 "invalid choice" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" e2e RUN_V2_TEST=TRUE
    assert_status 2 "invalid boolean" || return 1
    start_fixture required-space || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression 'REQUIRED TEXT=ok'
    assert_status 0 "required parameter name with whitespace" || return 1
    path=$(assert_private_path "whitespace parameter launch plan") || return 1
    assert_json_file "$path" 'any(.parameters[]; .name=="REQUIRED TEXT" and .value=="ok" and .source=="override")' "whitespace parameter preservation" || return 1
    start_fixture buildable-false || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression
    assert_status 2 "nonbuildable trigger" || return 1
    assert_all_get
    start_fixture raw-types || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression FIXTURE_TOKEN=secret
    assert_status 2 "password parameter refusal" || return 1
    assert_output_absent secret "password parameter refusal" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression
    assert_status 2 "required override for absent default" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression REQUIRED_TEXT=ok
    assert_status 2 "defaulted password and unsupported type refusal" || return 1
    case $(output_text) in
        *"Password parameters cannot be triggered by this wrapper"*|*"Unsupported Jenkins parameter type"*) ;;
        *) fail "defaulted unsafe type did not emit a refusal"; return 1;;
    esac

    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression UNKNOWN=value
    assert_status 2 "unknown parameter" || return 1
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" regression 'CUSTOM_TEST_OPTIONS=a=b=c' 'CUSTOM_TEST_OPTIONS=duplicate'
    assert_status 2 "duplicate parameter" || return 1
    assert_all_get

    start_fixture post-201 || return 4
    run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" --execute regression 'CUSTOM_TEST_OPTIONS=-i negative --exclude cluster' CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
    assert_status 0 "201 trigger with caller-first SSH key" || return 1
    assert_json_stdout '(. | keys) == ["job","queueId","state"] and .job == "regression" and (.queueId|type)=="number" and .queueId > 0 and .state == "QUEUED"' "201 trigger result" || return 1
    assert_log '([.[] | select(.method=="POST")] | length) == 1 and all(.[] | select(.method=="POST"); (.path=="/job/private/job/longhorn-tests-regression/buildWithParameters") and .auth=="ok" and .crumb=="ok" and (.form|length)>=1 and any(.form[]; .name=="CUSTOM_TEST_OPTIONS" and .value=="-i negative --exclude cluster") and ([.form[] | select(.name=="CUSTOM_SSH_PUBLIC_KEY")] | length)==1 and any(.form[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="caller-public-key-content") and all(.form[]; .value != "fixture-public-key-content" and (.value|contains("dummy-token")|not)))' "201 caller-first trigger request" || return 1
    assert_log "all(.[] | select(.method==\"POST\"); all(.form[]; .value != \"$missing_key_file\"))" "201 caller-first trigger path exclusion" || return 1
    assert_output_absent caller-public-key-content "201 caller-first trigger caller SSH key output" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "201 caller-first trigger env SSH key content" || return 1
    assert_output_absent "$missing_key_file" "201 caller-first trigger env SSH key path" || return 1

    start_fixture post-302 || return 4
    run_capture_env JENKINS_SSH_PUBLIC_KEY="$missing_key_file" "$BASH" "$SKILL_DIR/scripts/trigger_job.sh" --execute e2e RUN_V2_TEST=true CUSTOM_SSH_PUBLIC_KEY=caller-public-key-content
    assert_status 0 "302 trigger with caller-first SSH key" || return 1
    assert_json_stdout '(.state == "QUEUED") and (.queueId > 0)' "302 trigger result" || return 1
    assert_log '([.[] | select(.method=="POST")] | length) == 1 and all(.[] | select(.method=="POST"); ([.form[] | select(.name=="CUSTOM_SSH_PUBLIC_KEY")] | length)==1 and any(.form[]; .name=="CUSTOM_SSH_PUBLIC_KEY" and .value=="caller-public-key-content") and all(.form[]; .value != "fixture-public-key-content"))' "302 caller-first trigger request" || return 1
    assert_log "all(.[] | select(.method==\"POST\"); all(.form[]; .value != \"$missing_key_file\"))" "302 caller-first trigger path exclusion" || return 1
    assert_output_absent caller-public-key-content "302 caller-first trigger caller SSH key output" || return 1
    assert_output_absent "$SSH_PUBLIC_KEY_CONTENT" "302 caller-first trigger env SSH key content" || return 1
    assert_output_absent "$missing_key_file" "302 caller-first trigger env SSH key path" || return 1

    start_fixture crumb-disabled || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute regression 'CUSTOM_TEST_OPTIONS=ok'
    assert_status 0 "crumb-disabled trigger" || return 1
    assert_log 'all(.[] | select(.method=="POST"); .crumb == "not-required")' "crumb-disabled request"

    start_fixture crumb-malformed || return 4
    run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute regression 'CUSTOM_TEST_OPTIONS=ok'
    assert_status 4 "malformed crumb" || return 1

    for trigger_case in post-location-missing post-location-foreign post-status-400 post-status-403 post-status-500; do
        start_fixture "$trigger_case" || return 4
        run_capture "$SKILL_DIR/scripts/trigger_job.sh" --execute regression 'CUSTOM_TEST_OPTIONS=ok'
        assert_status 4 "rejected trigger $trigger_case" || return 1
        assert_output_absent dummy-token "rejected trigger $trigger_case" || return 1
        count=$(jq -s '[.[] | select(.method=="POST")] | length' "$FIXTURE_LOG")
        [ "$count" -eq 1 ] || { fail "POST was retried for $trigger_case"; return 1; }
    done
    count=$(jq -s '[.[] | select(.method=="POST")] | length' "$FIXTURE_LOG")
    [ "$count" -eq 1 ] || { fail "POST was retried"; return 1; }
    pass "trigger contracts"
    return 0
}

monitor_mode() {
    local count
    require_script get_build_status.sh || return $?
    require_script wait_for_build.sh || return $?
    require_script list_builds.sh || return $?
    require_script resolve_build.sh || return $?
    start_fixture normal || return 4
    clear_log
    run_capture "$SKILL_DIR/scripts/get_build_status.sh" unknown 7
    assert_status 2 "unknown build-status alias" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "unknown build-status alias contacted fixture"; return 1; }
    start_fixture normal || return 4
    run_capture "$SKILL_DIR/scripts/get_build_status.sh" regression 7
    assert_status 0 "build status" || return 1
    assert_json_stdout '(. | keys)==["build","building","job","queueId","result"] and .job=="regression" and .build==7 and .queueId==101 and (.building|type)=="boolean" and (.result==null or (.result|type)=="string")' "build status schema" || return 1
    run_capture "$SKILL_DIR/scripts/get_build_status.sh" regression 0
    assert_status 2 "invalid build number" || return 1
    run_capture "$SKILL_DIR/scripts/get_build_status.sh" regression 01
    assert_status 2 "noncanonical build number" || return 1

    run_capture "$SKILL_DIR/scripts/list_builds.sh" regression 2
    assert_status 0 "bounded recent builds" || return 1
    assert_json_stdout '(. | keys)==["builds","job"] and .job=="regression" and [.builds[].build]==[7,6] and [.builds[].queueId]==[101,100]' "recent builds schema" || return 1
    assert_log 'any(.[]; .method=="GET" and (.query|contains("tree=builds[number,queueId,building,result]{0,2}")))' "bounded recent builds request" || return 1
    run_capture "$SKILL_DIR/scripts/resolve_build.sh" regression 101 2
    assert_status 0 "resolve build by queue id" || return 1
    assert_json_stdout '(. | keys)==["build","building","job","queueId","result"] and .job=="regression" and .queueId==101 and .build==7 and .result=="SUCCESS"' "resolved build schema" || return 1
    assert_log 'any(.[]; .method=="GET" and (.path|endswith("/7/api/json")))' "resolved build identity request" || return 1
    run_capture "$SKILL_DIR/scripts/resolve_build.sh" regression 999 2
    assert_status 5 "missing queue correlation" || return 1
    assert_json_stdout '.job=="regression" and .queueId==999 and .build==null and .result=="NOT_FOUND"' "missing queue correlation result" || return 1

    start_fixture queue-build-transition || return 4
    : > "$FAKE_SLEEP_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
    assert_status 0 "queue to build" || return 1
    assert_json_stdout '(.job=="regression" and .build==7 and .result=="SUCCESS")' "wait success" || return 1
    assert_json_stdout '.queueId==101' "wait queue id" || return 1
    assert_log 'any(.[]; .method=="GET" and (.path|contains("/queue/item/101/"))) and any(.[]; .method=="GET" and (.path|endswith("/7/api/json")))' "queue/build request" || return 1
    assert_log 'all(.[]; .method=="GET")' "monitor GET-only" || return 1
    assert_log '.[0].method=="GET" and (.[0].path|contains("/queue/item/101/"))' "immediate queue request" || return 1
    start_fixture queue-pending-multi || return 4
    : > "$FAKE_SLEEP_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 120
    assert_status 0 "queue 5/10/30 cadence" || return 1
    expected_sleep=$(printf '5\n10\n30\n')
    [ "$(cat "$FAKE_SLEEP_LOG")" = "$expected_sleep" ] || {
        fail "queue sleep sequence was not 5, 10, 30"
        return 1
    }

    start_fixture queue-expired-recover || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
    assert_status 0 "expired queue recovery" || return 1
    assert_json_stdout '.job=="regression" and .queueId==101 and .build==7 and .result=="SUCCESS"' "expired queue recovery result" || return 1
    assert_log 'any(.[]; .method=="GET" and (.path|contains("/queue/item/101/"))) and any(.[]; .method=="GET" and (.query|contains("tree=builds[number,queueId,building,result]{0,100}"))) and any(.[]; .method=="GET" and (.path|endswith("/7/api/json")))' "expired queue recovery requests" || return 1
    assert_log '([.[] | select(.method=="GET" and (.path|contains("/job/")) and (.path|test("/[0-9]+/api/json$"))) | .path] | length)==1 and ([.[] | select(.method=="GET" and (.path|contains("/job/")) and (.path|test("/[0-9]+/api/json$"))) | .path][0] | endswith("/7/api/json"))' "expired recovery never probes build numbers" || return 1
    start_fixture queue-expired-not-found || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
    assert_status 5 "expired queue without correlation" || return 1
    assert_json_stdout '.job==null and .queueId==101 and .build==null and .result=="NOT_FOUND"' "expired queue not found result" || return 1
    assert_log 'all(.[]; (.path|test("/job/.*/[0-9]+/api/json$")) | not)' "missing correlation never probes build numbers" || return 1


    start_fixture queue-cancel-before || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
    assert_status 5 "queue cancellation" || return 1
    assert_json_stdout '.job==null and .build==null and .result=="CANCELLED"' "queue cancellation result" || return 1

    start_fixture wait-hang || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 1
    assert_status 5 "hanging wait deadline clamp" || return 1
    assert_json_stdout '.result=="TIMEOUT"' "hanging wait timeout result" || return 1
    count=$(jq -s '[.[] | select(.method=="GET")] | length' "$FIXTURE_LOG")
    [ "$count" -le 2 ] || { fail "deadline-aware wait retried past deadline"; return 1; }

    start_fixture queue-timeout-before || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 1
    assert_status 5 "pre-resolution timeout" || return 1
    assert_json_stdout '.job==null and .build==null and .result=="TIMEOUT"' "pre-resolution timeout result" || return 1

    start_fixture queue-timeout-after || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 1
    assert_status 5 "post-resolution timeout" || return 1
    assert_json_stdout '.job=="regression" and .build==7 and .result=="TIMEOUT"' "post-resolution timeout result" || return 1

    start_fixture build-failure || return 4
    run_capture "$SKILL_DIR/scripts/wait_for_build.sh" 101 20
    assert_status 6 "completed build failure" || return 1
    assert_json_stdout '.job=="regression" and .build==7 and .result=="FAILURE"' "completed failure result" || return 1
    pass "monitor contracts"
    return 0
}

inspect_ssh_mode() {
    local path manifest hosts
    require_script inspect_build.sh || return $?
    require_script get_artifact.sh || return $?
    require_script ssh_job_host.sh || return $?
    require_script wait_for_job_host.sh || return $?
    start_fixture reports-artifacts || return 4
    clear_log
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" unknown 7
    assert_status 2 "unknown inspection alias" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "unknown inspection alias contacted fixture"; return 1; }
    start_fixture reports-artifacts || return 4
    export JENKINS_SSH_USER=jenkins-test
    export HOME="$RUN_DIR/home"
    mkdir -p "$HOME/.ssh"
    RESOLVED_IDENTITY_FILE="$HOME/.ssh/id_test"
    : > "$RESOLVED_IDENTITY_FILE"
    chmod 600 "$RESOLVED_IDENTITY_FILE"
    export JENKINS_SSH_IDENTITY_FILE='~/.ssh/id_test'

    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "inspect build" || return 1
    manifest=$(assert_private_path "inspection manifest") || return 1
    assert_private_dir "$(dirname "$manifest")" || return 1
    assert_json_file "$manifest" '(. | keys)==["build","files","job","result"] and .job=="regression" and .build==7 and (.files|keys)==["artifacts","build","console","junit","remoteHosts","robot"] and (.files.junit|type)=="string" and (.files.robot|type)=="string"' "inspection manifest schema" || return 1
    remote_path=$(jq -r '.files.remoteHosts' "$manifest")
    assert_json_file "$(dirname "$manifest")/$remote_path" '.hosts == ["192.0.2.10"] and .job=="regression" and .build==7' "remote host manifest" || return 1
    for manifest_key in build console artifacts remoteHosts junit robot; do
        rel=$(jq -r ".files.${manifest_key}" "$manifest")
        if [ "$rel" != "null" ]; then
            manifest_file="$(dirname "$manifest")/$rel"
            [ -f "$manifest_file" ] || { fail "manifest file missing: $manifest_key"; return 1; }
            manifest_mode=$(python -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$manifest_file") || return 1
            [ "$manifest_mode" = "0o600" ] || { fail "manifest file mode for $manifest_key was $manifest_mode"; return 1; }
            assert_file_absent "$manifest_file" dummy-token "manifest file $manifest_key" || return 1
        fi
    done
    assert_output_absent dummy-token "inspection output" || return 1
    assert_output_absent "$JENKINS_URL" "inspection output" || return 1
    assert_log 'any(.[]; .method=="GET" and (.path|endswith("/consoleText"))) and any(.[]; .method=="GET" and (.path|endswith("/testReport/api/json"))) and any(.[]; .method=="GET" and (.path|endswith("/robot/api/json")))' "inspection endpoints" || return 1
    start_fixture reports-missing || return 4
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "missing optional reports" || return 1
    manifest=$(assert_private_path "missing-report manifest") || return 1
    assert_json_file "$manifest" '.files.junit == null and .files.robot == null' "missing-report manifest" || return 1

    start_fixture reports-artifacts || return 4


    run_capture "$SKILL_DIR/scripts/get_artifact.sh" regression 7 artifacts/results.xml
    assert_status 0 "artifact retrieval" || return 1
    path=$(assert_private_path "artifact output") || return 1
    assert_private_dir "$(dirname "$path")" || return 1
    run_capture "$SKILL_DIR/scripts/get_artifact.sh" regression 7 ../secrets
    assert_status 2 "artifact traversal refusal" || return 1
    run_capture "$SKILL_DIR/scripts/get_artifact.sh" regression 7 unknown.txt
    case "$RUN_STATUS" in 2|4) ;; *) fail "unknown artifact status $RUN_STATUS"; return 1;; esac

    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 0 "resolve-only SSH" || return 1
    path=$(assert_private_path "SSH target") || return 1
    assert_private_dir "$(dirname "$path")" || return 1
    assert_json_file "$path" '(. | keys)==["build","host","identityFile","job","user"] and .job=="regression" and .build==7 and .host=="192.0.2.10" and .user=="jenkins-test"' "SSH target schema" || return 1
    jq -e --arg identity "$RESOLVED_IDENTITY_FILE" '.identityFile == $identity' "$path" >/dev/null 2>&1 || {
        fail "resolve-only target did not contain the resolved identity path"
        return 1
    }
    [ ! -s "$FAKE_SSH_LOG" ] || { fail "resolve-only invoked ssh"; return 1; }

    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" regression 7
    assert_status 0 "interactive SSH" || return 1
    expected_ssh=$(printf '<%s>\n' -tt -i "$RESOLVED_IDENTITY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null 'jenkins-test@192.0.2.10')
    [ "$(cat "$FAKE_SSH_LOG")" = "$expected_ssh" ] || {
        fail "interactive SSH arguments were not exact"
        return 1
    }
    : > "$FAKE_SSH_LOG"
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" regression 7 -- bash -c 'printf spaced' ''
    assert_status 0 "command SSH" || return 1
    expected_ssh=$(printf '<%s>\n' -i "$RESOLVED_IDENTITY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null 'jenkins-test@192.0.2.10' bash -c 'printf spaced' '')
    [ "$(cat "$FAKE_SSH_LOG")" = "$expected_ssh" ] || {
        fail "command SSH argument array was not preserved"
        return 1
    }

    start_fixture console-ipv6 || return 4
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "inspection with IPv6 host" || return 1
    manifest=$(assert_private_path "IPv6 inspection manifest") || return 1
    remote_path=$(jq -r '.files.remoteHosts' "$manifest")
    assert_json_file "$(dirname "$manifest")/$remote_path" '.hosts == ["2600:1f18:671d:ea00:8589:9089:1065:aff9"]' "canonical IPv6 remote host" || return 1
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 0 "resolve-only IPv6 SSH" || return 1
    path=$(assert_private_path "IPv6 SSH target") || return 1
    assert_json_file "$path" '.host=="2600:1f18:671d:ea00:8589:9089:1065:aff9" and .user=="jenkins-test"' "IPv6 SSH target" || return 1
    : > "$FAKE_SSH_LOG"
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" regression 7
    assert_status 0 "interactive IPv6 SSH" || return 1
    expected_ssh=$(printf '<%s>\n' -tt -i "$RESOLVED_IDENTITY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -6 -l jenkins-test '2600:1f18:671d:ea00:8589:9089:1065:aff9')
    [ "$(cat "$FAKE_SSH_LOG")" = "$expected_ssh" ] || {
        fail "interactive IPv6 SSH arguments were not exact"
        return 1
    }

    start_fixture console-ipv6-compressed || return 4
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "inspection canonicalizes compressed IPv6" || return 1
    manifest=$(assert_private_path "compressed IPv6 inspection manifest") || return 1
    remote_path=$(jq -r '.files.remoteHosts' "$manifest")
    assert_json_file "$(dirname "$manifest")/$remote_path" '.hosts == ["2001:db8::1"]' "compressed IPv6 remote host" || return 1

    for invalid_ipv6_mode in console-invalid-ipv6 console-unbracketed-ipv6; do
        start_fixture "$invalid_ipv6_mode" || return 4
        run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
        assert_status 0 "$invalid_ipv6_mode inspection" || return 1
        manifest=$(assert_private_path "$invalid_ipv6_mode inspection manifest") || return 1
        remote_path=$(jq -r '.files.remoteHosts' "$manifest")
        assert_json_file "$(dirname "$manifest")/$remote_path" '.hosts == []' "$invalid_ipv6_mode exclusion" || return 1
        run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
        assert_status 2 "$invalid_ipv6_mode SSH refusal" || return 1
    done

    start_fixture console-mixed-ip || return 4
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "inspection with mixed IP hosts" || return 1
    manifest=$(assert_private_path "mixed IP inspection manifest") || return 1
    remote_path=$(jq -r '.files.remoteHosts' "$manifest")
    assert_json_file "$(dirname "$manifest")/$remote_path" '.hosts == ["192.0.2.10", "2001:db8::1"]' "mixed IP remote hosts" || return 1
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 2 "mixed IP multiple host refusal" || return 1

    start_fixture reports-artifacts || return 4
    unset JENKINS_SSH_IDENTITY_FILE
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 3 "missing SSH identity" || return 1
    export JENKINS_SSH_IDENTITY_FILE='~/.ssh/id_test'
    mkdir "$HOME/.ssh/id-directory"
    export JENKINS_SSH_IDENTITY_FILE='~/.ssh/id-directory'
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 3 "invalid SSH identity" || return 1
    export JENKINS_SSH_IDENTITY_FILE='~/.ssh/id_test'

    unset JENKINS_SSH_USER
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 3 "missing SSH user" || return 1
    export JENKINS_SSH_USER=jenkins-test
    start_fixture console-no-ip || return 4
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "inspection with zero hosts" || return 1
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 2 "zero host refusal" || return 1
    start_fixture console-multiple-ip || return 4
    run_capture "$SKILL_DIR/scripts/inspect_build.sh" regression 7
    assert_status 0 "inspection with multiple hosts" || return 1
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" --resolve-only regression 7
    assert_status 2 "multiple host refusal" || return 1
    unset JENKINS_SSH_USER JENKINS_SSH_IDENTITY_FILE
    start_fixture host-wait-ready || return 4
    : > "$FAKE_SLEEP_LOG"
    : > "$FAKE_SSH_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" regression 7 60
    assert_status 0 "wait for provisioned host" || return 1
    path=$(assert_private_path "host wait result") || return 1
    assert_private_dir "$(dirname "$path")" || return 1
    assert_json_file "$path" '(. | keys)==["build","host","job","result"] and .job=="regression" and .build==7 and .host=="192.0.2.10" and .result=="READY"' "host wait ready schema" || return 1
    [ "$(cat "$FAKE_SLEEP_LOG")" = "$(printf '15\n15')" ] || { fail "host wait did not use exact 15-second polling"; return 1; }
    count=$(jq -s '[.[] | select(.method=="GET" and (.path|endswith("/consoleText")))] | length' "$FIXTURE_LOG")
    [ "$count" -eq 3 ] || { fail "host wait expected 3 console requests, got $count"; return 1; }
    [ ! -s "$FAKE_SSH_LOG" ] || { fail "host wait invoked ssh"; return 1; }

    start_fixture host-wait-ipv6-ready || return 4
    : > "$FAKE_SLEEP_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" regression 7 60
    assert_status 0 "wait for provisioned IPv6 host" || return 1
    path=$(assert_private_path "IPv6 host wait result") || return 1
    assert_json_file "$path" '.host=="2600:1f18:671d:ea00:8589:9089:1065:aff9" and .result=="READY"' "IPv6 host wait ready" || return 1
    [ "$(cat "$FAKE_SLEEP_LOG")" = "$(printf '15\n15')" ] || { fail "IPv6 host wait did not use exact 15-second polling"; return 1; }

    start_fixture host-wait-multiple || return 4
    : > "$FAKE_SLEEP_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" regression 7 60
    assert_status 2 "multiple provisioned hosts refusal" || return 1
    [ ! -s "$FAKE_SLEEP_LOG" ] || { fail "multiple-host refusal slept before failing"; return 1; }

    start_fixture host-wait-timeout || return 4
    : > "$FAKE_SLEEP_LOG"
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" regression 7 1
    assert_status 5 "host provisioning timeout" || return 1
    path=$(assert_private_path "host wait timeout result") || return 1
    assert_json_file "$path" '(. | keys)==["build","host","job","result"] and .job=="regression" and .build==7 and .host==null and .result=="TIMEOUT"' "host wait timeout schema" || return 1
    count=$(jq -s '[.[] | select(.method=="GET" and (.path|endswith("/consoleText")))] | length' "$FIXTURE_LOG")
    [ "$count" -eq 1 ] || { fail "host timeout expected one deadline-clamped request, got $count"; return 1; }
    [ ! -s "$FAKE_SSH_LOG" ] || { fail "host timeout invoked ssh"; return 1; }

    start_fixture host-wait-ready || return 4
    clear_log
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" unknown 7 60
    assert_status 2 "unknown host-wait alias" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "unknown host-wait alias contacted fixture"; return 1; }
    run_capture "$SKILL_DIR/scripts/wait_for_job_host.sh" regression 7 0
    assert_status 2 "invalid host-wait timeout" || return 1
    [ ! -s "$FIXTURE_LOG" ] || { fail "invalid host-wait timeout contacted fixture"; return 1; }

    export JENKINS_SSH_USER=jenkins-test
    export JENKINS_SSH_IDENTITY_FILE='~/.ssh/id_test'
    export FAKE_SSH_EXIT=7
    start_fixture reports-artifacts || return 4
    run_capture "$SKILL_DIR/scripts/ssh_job_host.sh" regression 7
    assert_status 7 "SSH failure" || return 1
    unset FAKE_SSH_EXIT
    pass "inspection and SSH contracts"
    return 0
}

skill_mode() {
    local skill_text
    if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
        fail "Missing skill instructions: $SKILL_DIR/SKILL.md"
        return 99
    fi
    skill_text=$(cat "$SKILL_DIR/SKILL.md") || return 1
    for phrase in \
        "name: jenkins-ops" \
        "Use when a Longhorn developer asks to list, trigger, monitor, inspect, diagnose, or access hosts" \
        "JENKINS_URL" "JENKINS_USER" "JENKINS_TOKEN" \
        "JENKINS_NOTIFY_SLACK_CHANNEL" "SEND_SLACK_NOTIFICATION=true" "NOTIFY_SLACK_CHANNEL" \
        "JENKINS_SSH_IDENTITY_FILE" "JENKINS_SSH_USER" "JENKINS_SSH_PUBLIC_KEY" \
        "trigger-and-forget" "RUN_V2_TEST=false" "CUSTOM_TEST_OPTIONS" "CUSTOM_SSH_PUBLIC_KEY" \
        "at most the final 200 console lines" "20 console lines" \
        "300 characters" "[truncated; raw evidence remains in" "temporary-directory" \
        "StrictHostKeyChecking=no" "UserKnownHostsFile=/dev/null" "safely expands a leading" \
        "ticket/jenkins_<alias>-<build-number>-job/" "logs/console.txt" \
        "wait_for_job_host.sh" "900 seconds" "every 15 seconds" "never invokes SSH" \
        "bracketed IPv6" "requires \`python\`" "ssh -6"; do
        case "$skill_text" in
            *"$phrase"*) ;;
            *) fail "SKILL.md missing required contract text: $phrase"; return 1;;
        esac
    done
    case "$skill_text" in
        *". ./.env"*|*"set -a"*) ;;
        *) fail "SKILL.md missing same-shell .env retry instruction"; return 1;;
    esac
    pass "skill contract checks"
    return 0
}

live_readonly_mode() {
    require_script list_jobs.sh || return $?
    require_script get_job_parameters.sh || return $?
    if [ -z "${JENKINS_URL:-}" ] || [ -z "${JENKINS_USER:-}" ] || [ -z "${JENKINS_TOKEN:-}" ]; then
        fail "live-readonly requires JENKINS_URL, JENKINS_USER, and JENKINS_TOKEN"
        return 3
    fi
    RUN_OUTPUT="$EVIDENCE_ROOT/live-readonly.txt"
    : > "$RUN_OUTPUT"
    "$SKILL_DIR/scripts/list_jobs.sh" >>"$RUN_OUTPUT" 2>&1
    RUN_STATUS=$?
    assert_status 0 "live list jobs" || return 1
    jq -e '(.jobs|length)==3' "$RUN_OUTPUT" >/dev/null 2>&1 || { fail "live catalog schema"; return 1; }
    for alias in regression e2e benchmark; do
        "$SKILL_DIR/scripts/get_job_parameters.sh" "$alias" >>"$RUN_OUTPUT" 2>&1
        RUN_STATUS=$?
        assert_status 0 "live parameters $alias" || return 1
        path=$(tail -n 1 "$RUN_OUTPUT")
        [ -f "$path" ] || { fail "live parameters did not produce a private file"; return 1; }
        jq -e '(.parameters|length)>0 and (.buildable==true)' "$path" >/dev/null 2>&1 || { fail "live parameters schema $alias"; return 1; }
    done
    assert_output_absent dummy-token "live-readonly output" || return 1
    pass "live read-only checks"
    return 0
}

all_mode() {
    # Step 2 RED contract: start the fixture first, then fail clearly while
    # operation scripts are intentionally absent. Once scripts exist, execute
    # every contract group in deterministic order.
    start_fixture normal || return 4
    if [ ! -x "$SKILL_DIR/scripts/list_jobs.sh" ]; then
        fail "Missing Jenkins operation script: $SKILL_DIR/scripts/list_jobs.sh"
        return 99
    fi
    read_mode || return $?
    trigger_mode || return $?
    monitor_mode || return $?
    inspect_ssh_mode || return $?
    skill_mode || return $?
    pass "all fake-Jenkins contracts"
    return 0
}

usage() {
    say "Usage: $0 {all|read|trigger|monitor|inspect-ssh|skill|live-readonly}" >&2
    return 2
}

main() {
    local mode=${1:-}
    case "$mode" in
        all|read|trigger|monitor|inspect-ssh|skill|live-readonly) ;;
        *) usage; return 2;;
    esac
    if [ ! -d "$EVIDENCE_ROOT" ] && ! mkdir -m 700 -p "$EVIDENCE_ROOT"; then
        fail "Private temporary output is unavailable"
        return 3
    fi
    case "$mode" in
        all)
            if [ -x "$SKILL_DIR/scripts/list_jobs.sh" ]; then
                EVIDENCE_PATH="$EVIDENCE_ROOT/final-tests.txt"
            else
                EVIDENCE_PATH="$EVIDENCE_ROOT/red-runtime.txt"
            fi
            ;;
        read) EVIDENCE_PATH="$EVIDENCE_ROOT/read-tests.txt";;
        trigger) EVIDENCE_PATH="$EVIDENCE_ROOT/trigger-tests.txt";;
        monitor) EVIDENCE_PATH="$EVIDENCE_ROOT/monitor-tests.txt";;
        inspect-ssh) EVIDENCE_PATH="$EVIDENCE_ROOT/inspect-ssh-tests.txt";;
        skill) EVIDENCE_PATH="$EVIDENCE_ROOT/green-scenarios.md";;
        live-readonly) EVIDENCE_PATH="$EVIDENCE_ROOT/live-readonly.txt";;
    esac
    : > "$EVIDENCE_PATH" || {
        fail "Private evidence output is unavailable"
        return 3
    }
    if ! command -v chmod >/dev/null 2>&1; then
        fail "Required command is unavailable: chmod"
        return 3
    fi
    chmod 600 "$EVIDENCE_PATH" || return 3
    check_prerequisites || return $?
    RUN_DIR=$(mktemp -d "$EVIDENCE_ROOT/runner.XXXXXX") || {
        fail "Private temporary output is unavailable"
        return 3
    }
    chmod 700 "$RUN_DIR" || return 3
    SSH_PUBLIC_KEY_FILE="$RUN_DIR/fixture-ssh-public-key"
    SSH_PUBLIC_KEY_CONTENT='fixture-public-key-content'
    printf '%s\n' "$SSH_PUBLIC_KEY_CONTENT" > "$SSH_PUBLIC_KEY_FILE" || return 3
    chmod 600 "$SSH_PUBLIC_KEY_FILE" || return 3
    export JENKINS_SSH_PUBLIC_KEY="$SSH_PUBLIC_KEY_FILE"
    trap cleanup EXIT HUP INT TERM
    if [ "$mode" != live-readonly ]; then
        make_fake_tools || return 3
    fi
    case "$mode" in
        all) all_mode;;
        read) read_mode;;
        trigger) trigger_mode;;
        monitor) monitor_mode;;
        inspect-ssh) inspect_ssh_mode;;
        skill) skill_mode;;
        live-readonly) live_readonly_mode;;
    esac
}

main "$@"
exit $?
