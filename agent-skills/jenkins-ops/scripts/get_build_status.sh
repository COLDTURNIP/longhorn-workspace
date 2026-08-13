#!/usr/bin/env bash
# Read one build's status from an approved Jenkins job.
# This entrypoint is read-only and never inherits trigger dry-run behavior.
DRY_RUN=false

# Keep bootstrap shell-only so missing command tests reach require_command with
# the documented exit status rather than failing while locating this script.
case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR=${BASH_SOURCE[0]%/*} ;;
  *) SCRIPT_DIR=. ;;
esac
SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd -P)
SCRIPT_NAME=${0##*/}

# shellcheck source=/dev/null
. "$SCRIPT_DIR/jenkins_common.sh"

usage() {
  printf 'Usage: %s <job-alias> <positive-build-number>\n' "$SCRIPT_NAME" >&2
}

if [ "$#" -ne 2 ]; then
  usage
  exit "$EXIT_ARG"
fi

JOB_ALIAS_ARG=$1
BUILD_NUMBER_ARG=$2
case "$JOB_ALIAS_ARG" in
  ""|--*)
    usage
    exit "$EXIT_ARG"
    ;;
esac
# The canonical form intentionally rejects zero and leading zeroes.  Do not
# use arithmetic: build numbers may be larger than the shell integer range.
case "$BUILD_NUMBER_ARG" in
  ""|*[!0-9]*|0*)
    usage
    exit "$EXIT_ARG"
    ;;
esac

# Resolve the alias before checking Jenkins variables or creating a request.
# resolve_job validates the fixed catalog and reports unknown aliases as exit 2.
require_command jq
resolve_job "$JOB_ALIAS_ARG"

# Check local dependencies before any temporary output or network operation.
require_command curl
require_command mktemp
require_command chmod
require_jenkins_env
normalize_base_url
build_job_url "$JOB_ALIAS_ARG"

new_private_dir
trap 'if [ -n "${PRIVATE_DIR:-}" ]; then rm -rf -- "$PRIVATE_DIR"; fi' EXIT
RESPONSE_FILE="$PRIVATE_DIR/build-response.json"

JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/api/json?tree=number,queueId,building,result" "$RESPONSE_FILE" || REQUEST_RC=$?
case "$REQUEST_RC" in 2|3) exit "$REQUEST_RC" ;; esac
if [ "$REQUEST_RC" -ne 0 ]; then
  # A deadline is not used by this wrapper, but do not leak the internal
  # signal if a shared implementation ever returns it here.
  if [ "$REQUEST_RC" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
    _jenkins_error "Jenkins transport error"
  else
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  fi
  exit "$EXIT_JENKINS"
fi
if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
  map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  exit "$EXIT_JENKINS"
fi

# Validate the required response shape and requested-build identity before
# constructing the intentionally small public object.  Extra Jenkins fields,
# including actions and URLs, are never emitted.
if ! jq -e -cS --arg job "$JOB_ALIAS_ARG" --arg build "$BUILD_NUMBER_ARG" '
  if (type != "object") or
     (has("number") | not) or
     (has("building") | not) or
     (has("result") | not) or
     (.number | type) != "number" or
     (.number | floor) != .number or
     (.number <= 0) or
     (((.queueId? // null) != null) and
       (((.queueId | type) != "number") or (.queueId | floor) != .queueId or ((.queueId <= 0) and (.queueId != -1)))) or
     (.number != ($build | tonumber)) or
     (.building | type) != "boolean" or
     ((.result | type) != "string" and (.result | type) != "null") then
    error("malformed build status")
  else
    {job: $job, build: .number, queueId: (.queueId? // null), building: .building, result: .result}
  end
' "$RESPONSE_FILE" 2>/dev/null; then
  _jenkins_error "Jenkins build response is malformed"
  exit "$EXIT_JENKINS"
fi
