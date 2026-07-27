#!/usr/bin/env bash
# Resolve one approved Jenkins build from its queue identifier.
# This entrypoint is read-only and searches only a bounded recent-build window.
DRY_RUN=false

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR=${BASH_SOURCE[0]%/*} ;;
  *) SCRIPT_DIR=. ;;
esac
SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd -P)
SCRIPT_NAME=${0##*/}

# shellcheck source=/dev/null
. "$SCRIPT_DIR/jenkins_common.sh"

usage() {
  printf 'Usage: %s <job-alias> <positive-queue-id> [count:1-100]\n' "$SCRIPT_NAME" >&2
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit "$EXIT_ARG"
fi

JOB_ALIAS_ARG=$1
QUEUE_ID=$2
COUNT=${3:-50}
case "$JOB_ALIAS_ARG" in
  ""|--*) usage; exit "$EXIT_ARG" ;;
esac
case "$QUEUE_ID" in
  ""|*[!0-9]*|0*) usage; exit "$EXIT_ARG" ;;
esac
case "$COUNT" in
  ""|*[!0-9]*|0*) usage; exit "$EXIT_ARG" ;;
esac
if [ "${#COUNT}" -gt 3 ] || [ "$COUNT" -gt 100 ]; then
  usage
  exit "$EXIT_ARG"
fi

require_command jq
resolve_job "$JOB_ALIAS_ARG"
require_command mktemp
require_command chmod

new_private_dir
trap 'if [ -n "${PRIVATE_DIR:-}" ]; then rm -rf -- "$PRIVATE_DIR"; fi' EXIT
BUILDS_FILE="$PRIVATE_DIR/builds.json"
MATCH_FILE="$PRIVATE_DIR/match.json"
STATUS_FILE="$PRIVATE_DIR/status.json"

LIST_RC=0
"$SCRIPT_DIR/list_builds.sh" "$JOB_ALIAS_ARG" "$COUNT" > "$BUILDS_FILE" || LIST_RC=$?
if [ "$LIST_RC" -ne 0 ]; then
  exit "$LIST_RC"
fi
chmod 600 "$BUILDS_FILE" >/dev/null 2>&1 || {
  _jenkins_error "Private temporary output is unavailable"
  exit 3
}

if ! jq -e -cS --arg queue "$QUEUE_ID" '
  [.builds[] | select(.queueId != null and (.queueId | tostring) == $queue)]
' "$BUILDS_FILE" > "$MATCH_FILE" 2>/dev/null; then
  _jenkins_error "Jenkins recent builds response is malformed"
  exit "$EXIT_JENKINS"
fi
chmod 600 "$MATCH_FILE" >/dev/null 2>&1 || {
  _jenkins_error "Private temporary output is unavailable"
  exit 3
}

MATCH_COUNT=$(jq -r 'length' "$MATCH_FILE" 2>/dev/null) || {
  _jenkins_error "Jenkins recent builds response is malformed"
  exit "$EXIT_JENKINS"
}
case "$MATCH_COUNT" in
  0)
    jq -cnS --arg job "$JOB_ALIAS_ARG" --argjson queueId "$QUEUE_ID" \
      '{build:null,building:null,job:$job,queueId:$queueId,result:"NOT_FOUND"}'
    exit "$EXIT_TIMEOUT"
    ;;
  1)
    MATCH_BUILD=$(jq -r '.[0].build' "$MATCH_FILE" 2>/dev/null) || {
      _jenkins_error "Jenkins recent builds response is malformed"
      exit "$EXIT_JENKINS"
    }
    STATUS_RC=0
    "$SCRIPT_DIR/get_build_status.sh" "$JOB_ALIAS_ARG" "$MATCH_BUILD" > "$STATUS_FILE" || STATUS_RC=$?
    if [ "$STATUS_RC" -ne 0 ]; then
      exit "$STATUS_RC"
    fi
    chmod 600 "$STATUS_FILE" >/dev/null 2>&1 || {
      _jenkins_error "Private temporary output is unavailable"
      exit 3
    }
    if ! jq -e -cS --arg queue "$QUEUE_ID" '
      select((.queueId | type) == "number" and (.queueId | tostring) == $queue)
    ' "$STATUS_FILE" 2>/dev/null; then
      _jenkins_error "Jenkins build does not match the requested queue id"
      exit "$EXIT_JENKINS"
    fi
    ;;
  *)
    _jenkins_error "Jenkins queue id matched multiple recent builds"
    exit "$EXIT_JENKINS"
    ;;
esac
