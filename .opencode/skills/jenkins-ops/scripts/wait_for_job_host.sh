#!/usr/bin/env bash
# Wait until one validated Terraform control-plane host appears in a build log.

DRY_RUN=false
case "$0" in */*) SCRIPT_DIR=${0%/*} ;; *) SCRIPT_DIR=. ;; esac
SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd -P)
SCRIPT_NAME=${0##*/}
# shellcheck source=/dev/null
. "$SCRIPT_DIR/jenkins_common.sh"

usage() {
  printf 'Usage: %s <job-alias> <positive-build-number> [timeout-seconds]\n' "$SCRIPT_NAME" >&2
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit "$EXIT_ARG"
fi
JOB_ALIAS_ARG=$1
BUILD_NUMBER_ARG=$2
TIMEOUT_SECONDS=${3:-900}

case "$JOB_ALIAS_ARG" in ""|--*) usage; exit "$EXIT_ARG" ;; esac
case "$BUILD_NUMBER_ARG" in ""|*[!0-9]*|0*) usage; exit "$EXIT_ARG" ;; esac
case "$TIMEOUT_SECONDS" in ""|*[!0-9]*|0*) _jenkins_error 'Invalid timeout'; exit "$EXIT_ARG" ;; esac
if [ "${#TIMEOUT_SECONDS}" -gt 5 ] || { [ "${#TIMEOUT_SECONDS}" -eq 5 ] && [ "$TIMEOUT_SECONDS" -gt 86400 ] 2>/dev/null; }; then
  _jenkins_error 'Invalid timeout'
  exit "$EXIT_ARG"
fi

require_command jq
resolve_job "$JOB_ALIAS_ARG"
require_command curl
require_command mktemp
require_command chmod
require_jenkins_env
normalize_base_url
build_job_url "$JOB_ALIAS_ARG"
new_private_dir
KEEP_PRIVATE=false
cleanup_private() {
  if [ "${KEEP_PRIVATE:-false}" != true ] && [ -n "${PRIVATE_DIR:-}" ]; then
    rm -rf -- "$PRIVATE_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup_private EXIT HUP INT TERM

CONSOLE_FILE="$PRIVATE_DIR/console.txt"
REMOTE_HOSTS_FILE="$PRIVATE_DIR/remote-hosts.json"
RESULT_FILE="$PRIVATE_DIR/host-wait.json"
SECONDS=0
DEADLINE=$TIMEOUT_SECONDS

emit_result() {
  local result=$1 host=${2:-}
  if [ "$result" = READY ]; then
    jq -nS --arg job "$JOB_ALIAS_ARG" --argjson build "$BUILD_NUMBER_ARG" --arg host "$host" \
      '{job:$job, build:$build, host:$host, result:"READY"}' > "$RESULT_FILE" 2>/dev/null || return "$EXIT_ENV"
  else
    jq -nS --arg job "$JOB_ALIAS_ARG" --argjson build "$BUILD_NUMBER_ARG" \
      '{job:$job, build:$build, host:null, result:"TIMEOUT"}' > "$RESULT_FILE" 2>/dev/null || return "$EXIT_ENV"
  fi
  chmod 600 "$RESULT_FILE" >/dev/null 2>&1 || return "$EXIT_ENV"
  KEEP_PRIVATE=true
  printf '%s\n' "$RESULT_FILE"
}

emit_timeout() {
  emit_result TIMEOUT || {
    _jenkins_error 'Private temporary output is unavailable'
    exit "$EXIT_ENV"
  }
  exit "$EXIT_TIMEOUT"
}

sleep_until_deadline() {
  local remaining sleep_for
  remaining=$((DEADLINE - SECONDS))
  [ "$remaining" -gt 0 ] || return "$JENKINS_DEADLINE_SIGNAL"
  sleep_for=15
  [ "$sleep_for" -le "$remaining" ] || sleep_for=$remaining
  sleep "$sleep_for"
  [ "$SECONDS" -lt "$DEADLINE" ] || return "$JENKINS_DEADLINE_SIGNAL"
}

while :; do
  REQUEST_RC=0
  JENKINS_REQUEST_FORM=()
  JENKINS_REQUEST_HEADERS=()
  JENKINS_REQUEST_ARGS=()
  jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/consoleText" "$CONSOLE_FILE" "$DEADLINE" || REQUEST_RC=$?
  case "$REQUEST_RC" in
    0) ;;
    "$JENKINS_DEADLINE_SIGNAL") emit_timeout ;;
    2|3) exit "$REQUEST_RC" ;;
    *) map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true; exit "$EXIT_JENKINS" ;;
  esac
  if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
    exit "$EXIT_JENKINS"
  fi
  chmod 600 "$CONSOLE_FILE" >/dev/null 2>&1 || {
    _jenkins_error 'Private temporary output is unavailable'
    exit "$EXIT_ENV"
  }
  rm -f "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true
  extract_controlplane_hosts "$CONSOLE_FILE" "$REMOTE_HOSTS_FILE" "$JOB_ALIAS_ARG" "$BUILD_NUMBER_ARG" || exit $?
  HOST_COUNT=$(jq -r '.hosts | length' "$REMOTE_HOSTS_FILE")
  case "$HOST_COUNT" in
    0)
      SLEEP_RC=0
      sleep_until_deadline || SLEEP_RC=$?
      [ "$SLEEP_RC" -eq 0 ] || emit_timeout
      ;;
    1)
      HOST=$(jq -r '.hosts[0]' "$REMOTE_HOSTS_FILE")
      emit_result READY "$HOST" || {
        _jenkins_error 'Private temporary output is unavailable'
        exit "$EXIT_ENV"
      }
      exit "$EXIT_OK"
      ;;
    *)
      _jenkins_error 'Jenkins console contained multiple valid control-plane hosts'
      exit "$EXIT_ARG"
      ;;
  esac
done
