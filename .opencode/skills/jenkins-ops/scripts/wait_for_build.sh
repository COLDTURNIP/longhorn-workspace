#!/usr/bin/env bash
# Wait for an approved Jenkins queue item and its resulting build.

# This wrapper is read-only. Keep dry-run disabled while sourcing the shared
# library so no trigger-only behavior can leak into monitoring.
DRY_RUN=false
case "$0" in */*) SCRIPT_DIR=${0%/*} ;; *) SCRIPT_DIR=. ;; esac
SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd -P)
SCRIPT_NAME=${0##*/}
# shellcheck source=/dev/null
source "$SCRIPT_DIR/jenkins_common.sh"

usage() {
  printf 'Usage: %s <positive-queue-id> [timeout-seconds]\n' "$SCRIPT_NAME" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit "$EXIT_ARG"
fi

QUEUE_ID=$1
TIMEOUT_SECONDS=${2:-600}

# Queue identifiers use the canonical positive-integer form. This also avoids
# Bash treating a leading zero as an octal prefix in any later arithmetic.
case "$QUEUE_ID" in
  ''|*[!0-9]*|0*)
    _jenkins_error 'Invalid queue id'
    exit "$EXIT_ARG"
    ;;
esac
case "$TIMEOUT_SECONDS" in
  ''|*[!0-9]*|0*)
    _jenkins_error 'Invalid timeout'
    exit "$EXIT_ARG"
    ;;
esac
if [ "${#TIMEOUT_SECONDS}" -gt 5 ]; then
  _jenkins_error 'Invalid timeout'
  exit "$EXIT_ARG"
fi
if [ "${#TIMEOUT_SECONDS}" -eq 5 ] && [ "$TIMEOUT_SECONDS" -gt 86400 ] 2>/dev/null; then
  _jenkins_error 'Invalid timeout'
  exit "$EXIT_ARG"
fi

# SECONDS is the clock used by jenkins_request for deadline-aware requests.
# Set it before any environment, catalog, or network work so the complete wait
# budget is measured from wrapper start.
SECONDS=0
DEADLINE=$TIMEOUT_SECONDS

require_command jq
require_command curl
require_command mktemp
require_command chmod
require_jenkins_env
normalize_base_url
new_private_dir

# Queue/build response bodies are private implementation evidence and are
# removed when this monitor exits. jenkins_request itself enforces mode 0600.
cleanup_private_dir() {
  if [ -n "${PRIVATE_DIR:-}" ] && [ -d "$PRIVATE_DIR" ]; then
    rm -rf "$PRIVATE_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup_private_dir EXIT HUP INT TERM

QUEUE_FILE="$PRIVATE_DIR/queue.json"
BUILD_FILE="$PRIVATE_DIR/build.json"
QUEUE_URL="${BASE_URL}/queue/item/${QUEUE_ID}/api/json"

# These globals are set only after the queue executable URL has been matched
# against one of the catalog's exact job URLs.
RESOLVED_ALIAS=""
RESOLVED_JOB_URL=""
RESOLVED_BUILD=""
QUEUE_PENDING_COUNT=0
QUEUE_NOT_FOUND_SIGNAL=74

emit_wait_result() {
  local alias=${1:-} build=${2:-} result=${3:-}
  if [ -n "$alias" ]; then
    jq -cn -S --arg job "$alias" --argjson queueId "$QUEUE_ID" --argjson build "$build" --arg result "$result" \
      '{build:$build,job:$job,queueId:$queueId,result:$result}'
  else
    jq -cn -S --argjson queueId "$QUEUE_ID" --arg result "$result" \
      '{build:null,job:null,queueId:$queueId,result:$result}'
  fi
}

emit_timeout() {
  emit_wait_result "${RESOLVED_ALIAS:-}" "${RESOLVED_BUILD:-}" TIMEOUT
  exit "$EXIT_TIMEOUT"
}

# Return 75 when the absolute deadline has elapsed, preserve local validation
# errors (2/3), and map all Jenkins transport/HTTP failures to exit 4.
request_get() {
  local url=$1 outfile=$2 allow_not_found=${3:-false} request_rc
  if [ "$SECONDS" -ge "$DEADLINE" ]; then
    return "$JENKINS_DEADLINE_SIGNAL"
  fi
  JENKINS_REQUEST_FORM=()
  JENKINS_REQUEST_HEADERS=()
  JENKINS_REQUEST_ARGS=()
  request_rc=0
  if jenkins_request GET "$url" "$outfile" "$DEADLINE"; then
    request_rc=0
  else
    request_rc=$?
  fi
  if [ "$request_rc" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
    return "$JENKINS_DEADLINE_SIGNAL"
  fi
  if [ "$request_rc" -ne 0 ]; then
    if [ "$allow_not_found" = true ] && [ "${JENKINS_HTTP_STATUS:-}" = 404 ]; then
      return "$QUEUE_NOT_FOUND_SIGNAL"
    fi
    case "$request_rc" in
      2|3) return "$request_rc" ;;
      *)
        map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
        return "$EXIT_JENKINS"
        ;;
    esac
  fi
  if [ "$allow_not_found" = true ] && [ "${JENKINS_HTTP_STATUS:-}" = 404 ]; then
    return "$QUEUE_NOT_FOUND_SIGNAL"
  fi
  if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
    return "$EXIT_JENKINS"
  fi
  return 0
}

sleep_until_deadline() {
  local requested=$1 remaining sleep_for
  remaining=$((DEADLINE - SECONDS))
  if [ "$remaining" -le 0 ]; then
    return "$JENKINS_DEADLINE_SIGNAL"
  fi
  sleep_for=$requested
  if [ "$sleep_for" -gt "$remaining" ]; then
    sleep_for=$remaining
  fi
  sleep "$sleep_for"
  if [ "$SECONDS" -ge "$DEADLINE" ]; then
    return "$JENKINS_DEADLINE_SIGNAL"
  fi
  return 0
}

# Validate the queue envelope before interpreting cancellation or executable
# data. Jenkins may add unrelated fields, but known fields must retain their
# expected types.
validate_queue_envelope() {
  if ! jq -e '
    type == "object"
    and ((has("cancelled") | not) or (.cancelled | type == "boolean"))
    and ((has("blocked") | not) or (.blocked | type == "boolean"))
  ' "$QUEUE_FILE" >/dev/null 2>&1; then
    _jenkins_error 'Jenkins queue response is malformed'
    return "$EXIT_JENKINS"
  fi
  return 0
}

validate_queue_executable() {
  if ! jq -e '
    type == "object"
    and (
      (has("executable") | not)
      or (.executable == null)
      or (
        (.executable | type == "object")
        and (.executable | has("number"))
        and ((.executable.number | type) == "number")
        and (.executable.number >= 1)
        and (.executable.number == (.executable.number | floor))
        and (.executable | has("url"))
        and ((.executable.url | type) == "string")
        and ((.executable.url | length) > 0)
      )
    )
  ' "$QUEUE_FILE" >/dev/null 2>&1; then
    _jenkins_error 'Jenkins queue response is malformed'
    return "$EXIT_JENKINS"
  fi
  return 0
}

# Compare the executable URL byte-for-byte with each allowlisted catalog job
# URL followed by the resolved positive build number. No server-provided URL
# is used to construct a later request.
resolve_executable() {
  local executable_url=$1 build_number=$2 candidate expected candidate_rc
  for candidate in regression e2e benchmark; do
    candidate_rc=0
    if build_job_url "$candidate"; then
      candidate_rc=0
    else
      candidate_rc=$?
    fi
    if [ "$candidate_rc" -ne 0 ]; then
      _jenkins_error 'Jenkins job catalog is malformed'
      return "$EXIT_JENKINS"
    fi
    expected="${JOB_URL}${build_number}/"
    if [ "$executable_url" = "$expected" ]; then
      RESOLVED_ALIAS=$candidate
      RESOLVED_JOB_URL=$JOB_URL
      RESOLVED_BUILD=$build_number
      return 0
    fi
  done
  _jenkins_error 'Jenkins queue executable is not an approved build'
  return "$EXIT_JENKINS"
}

# Recover an expired queue item by correlating its immutable queue id against
# bounded recent-build metadata from each approved job. Exactly one match is
# required; build-number probing is never used.
recover_expired_queue() {
  local candidate candidate_file candidate_count candidate_build total_matches request_rc
  total_matches=0
  for candidate in regression e2e benchmark; do
    candidate_file="$PRIVATE_DIR/recent-${candidate}.json"
    build_job_url "$candidate" || return "$EXIT_JENKINS"
    request_rc=0
    if request_get "${JOB_URL}api/json?tree=builds[number,queueId,building,result]{0,100}" "$candidate_file"; then
      request_rc=0
    else
      request_rc=$?
    fi
    if [ "$request_rc" -ne 0 ]; then
      return "$request_rc"
    fi
    if ! jq -e '
      def valid_integer: (type == "number") and (. >= 1) and (. == floor);
      def valid_queue_id: (type == "number") and (. == floor) and ((. == -1) or (. >= 1));
      def valid_result: (type == "string") or (type == "null");
      type == "object"
      and (has("builds") and (.builds | type) == "array")
      and all(.builds[];
        type == "object"
        and (has("number") and (.number | valid_integer))
        and (has("building") and (.building | type) == "boolean")
        and (has("result") and (.result | valid_result))
        and ((.queueId? // null) as $queue | (($queue == null) or ($queue | valid_queue_id)))
      )
    ' "$candidate_file" >/dev/null 2>&1; then
      _jenkins_error 'Jenkins recent builds response is malformed'
      return "$EXIT_JENKINS"
    fi
    candidate_count=$(jq -r --arg queue "$QUEUE_ID" \
      '[.builds[] | select((.queueId? // null) != null and (.queueId | tostring) == $queue)] | length' \
      "$candidate_file" 2>/dev/null) || {
      _jenkins_error 'Jenkins recent builds response is malformed'
      return "$EXIT_JENKINS"
    }
    case "$candidate_count" in
      0) ;;
      1)
        candidate_build=$(jq -r --arg queue "$QUEUE_ID" \
          '.builds[] | select((.queueId? // null) != null and (.queueId | tostring) == $queue) | .number' \
          "$candidate_file" 2>/dev/null) || {
          _jenkins_error 'Jenkins recent builds response is malformed'
          return "$EXIT_JENKINS"
        }
        RESOLVED_ALIAS=$candidate
        RESOLVED_BUILD=$candidate_build
        RESOLVED_JOB_URL=$JOB_URL
        total_matches=$((total_matches + 1))
        ;;
      *)
        _jenkins_error 'Jenkins queue id matched multiple recent builds'
        return "$EXIT_JENKINS"
        ;;
    esac
  done
  if [ "$total_matches" -eq 1 ]; then
    return 0
  fi
  if [ "$total_matches" -gt 1 ]; then
    _jenkins_error 'Jenkins queue id matched multiple approved builds'
  else
    return "$EXIT_TIMEOUT"
  fi
  return "$EXIT_JENKINS"
}

# Queue polling starts with an immediate request. Pending responses use the
# exact 5/10/30 cadence; the sequence is not restarted after later responses.
while :; do
  request_rc=0
  if request_get "$QUEUE_URL" "$QUEUE_FILE" true; then
    request_rc=0
  else
    request_rc=$?
  fi
  case "$request_rc" in
    "$JENKINS_DEADLINE_SIGNAL") emit_timeout ;;
    "$QUEUE_NOT_FOUND_SIGNAL")
      recovery_rc=0
      recover_expired_queue || recovery_rc=$?
      case "$recovery_rc" in
        0) break ;;
        "$JENKINS_DEADLINE_SIGNAL") emit_timeout ;;
        "$EXIT_TIMEOUT")
          emit_wait_result '' '' NOT_FOUND
          exit "$EXIT_TIMEOUT"
          ;;
        *) exit "$recovery_rc" ;;
      esac
      ;;
    0) ;;
    *) exit "$request_rc" ;;
  esac

  validate_queue_envelope
  cancelled=$(jq -r 'if (.cancelled? == true) then "true" else "false" end' "$QUEUE_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins queue response is malformed'
    exit "$EXIT_JENKINS"
  }
  if [ "$cancelled" = true ]; then
    emit_wait_result '' '' CANCELLED
    exit "$EXIT_TIMEOUT"
  fi

  validate_queue_executable
  executable_present=$(jq -r 'if (.executable? == null) then "false" else "true" end' "$QUEUE_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins queue response is malformed'
    exit "$EXIT_JENKINS"
  }
  if [ "$executable_present" = false ]; then
    QUEUE_PENDING_COUNT=$((QUEUE_PENDING_COUNT + 1))
    case "$QUEUE_PENDING_COUNT" in
      1) poll_sleep=5 ;;
      2) poll_sleep=10 ;;
      *) poll_sleep=30 ;;
    esac
    sleep_rc=0
    if sleep_until_deadline "$poll_sleep"; then
      sleep_rc=0
    else
      sleep_rc=$?
    fi
    case "$sleep_rc" in
      "$JENKINS_DEADLINE_SIGNAL") emit_timeout ;;
      0) continue ;;
      *) exit "$sleep_rc" ;;
    esac
  fi

  executable_number=$(jq -r '.executable.number' "$QUEUE_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins queue response is malformed'
    exit "$EXIT_JENKINS"
  }
  case "$executable_number" in
    ''|*[!0-9]*|0*)
      _jenkins_error 'Jenkins queue response is malformed'
      exit "$EXIT_JENKINS"
      ;;
  esac
  executable_url=$(jq -r '.executable.url' "$QUEUE_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins queue response is malformed'
    exit "$EXIT_JENKINS"
  }
  if ! resolve_executable "$executable_url" "$executable_number"; then
    exit "$EXIT_JENKINS"
  fi
  break
done

# The first build GET follows queue resolution immediately, with no cadence
# sleep. Every response that is not a completed build is followed by 30s.
while :; do
  BUILD_URL="${RESOLVED_JOB_URL}${RESOLVED_BUILD}/api/json?tree=number,queueId,building,result"
  request_rc=0
  if request_get "$BUILD_URL" "$BUILD_FILE"; then
    request_rc=0
  else
    request_rc=$?
  fi
  case "$request_rc" in
    "$JENKINS_DEADLINE_SIGNAL") emit_timeout ;;
    0) ;;
    *) exit "$request_rc" ;;
  esac

  if ! jq -e '
    type == "object"
    and (has("number") and ((.number | type) == "number") and (.number >= 1)
         and (.number == (.number | floor)))
    and (has("queueId") and ((.queueId | type) == "number") and (.queueId >= 1)
         and (.queueId == (.queueId | floor)))
    and (has("building") and (.building | type == "boolean"))
    and (has("result") and ((.result == null) or (.result | type == "string")))
  ' "$BUILD_FILE" >/dev/null 2>&1; then
    _jenkins_error 'Jenkins build response is malformed'
    exit "$EXIT_JENKINS"
  fi
  response_number=$(jq -r '.number' "$BUILD_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins build response is malformed'
    exit "$EXIT_JENKINS"
  }
  case "$response_number" in
    ''|*[!0-9]*|0*)
      _jenkins_error 'Jenkins build response is malformed'
      exit "$EXIT_JENKINS"
      ;;
  esac
  if [ "$response_number" != "$RESOLVED_BUILD" ]; then
    _jenkins_error 'Jenkins build response is malformed'
    exit "$EXIT_JENKINS"
  fi
  response_queue_id=$(jq -r '.queueId' "$BUILD_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins build response is malformed'
    exit "$EXIT_JENKINS"
  }
  if [ "$response_queue_id" != "$QUEUE_ID" ]; then
    _jenkins_error 'Jenkins build response queue id does not match'
    exit "$EXIT_JENKINS"
  fi

  building=$(jq -r '.building' "$BUILD_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins build response is malformed'
    exit "$EXIT_JENKINS"
  }
  result_present=$(jq -r 'if .result == null then "false" else "true" end' "$BUILD_FILE" 2>/dev/null) || {
    _jenkins_error 'Jenkins build response is malformed'
    exit "$EXIT_JENKINS"
  }
  if [ "$building" = false ] && [ "$result_present" = true ]; then
    result=$(jq -r '.result' "$BUILD_FILE" 2>/dev/null) || {
      _jenkins_error 'Jenkins build response is malformed'
      exit "$EXIT_JENKINS"
    }
    emit_wait_result "$RESOLVED_ALIAS" "$RESOLVED_BUILD" "$result"
    if [ "$result" = SUCCESS ]; then
      exit 0
    fi
    exit "$EXIT_BUILD_FAILURE"
  fi

  sleep_rc=0
  if sleep_until_deadline 30; then
    sleep_rc=0
  else
    sleep_rc=$?
  fi
  case "$sleep_rc" in
    "$JENKINS_DEADLINE_SIGNAL") emit_timeout ;;
    0) ;;
    *) exit "$sleep_rc" ;;
  esac
done
