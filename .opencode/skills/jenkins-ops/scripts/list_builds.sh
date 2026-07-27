#!/usr/bin/env bash
# List a bounded set of recent builds for one approved Jenkins job.
# This entrypoint is read-only and never inherits trigger dry-run behavior.
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
  printf 'Usage: %s <job-alias> [count:1-100]\n' "$SCRIPT_NAME" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit "$EXIT_ARG"
fi

JOB_ALIAS_ARG=$1
COUNT=${2:-25}
case "$JOB_ALIAS_ARG" in
  ""|--*) usage; exit "$EXIT_ARG" ;;
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
require_command curl
require_command mktemp
require_command chmod
require_jenkins_env
normalize_base_url
build_job_url "$JOB_ALIAS_ARG"

new_private_dir
trap 'if [ -n "${PRIVATE_DIR:-}" ]; then rm -rf -- "$PRIVATE_DIR"; fi' EXIT
RESPONSE_FILE="$PRIVATE_DIR/builds-response.json"

JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}api/json?tree=builds[number,queueId,building,result]{0,${COUNT}}" "$RESPONSE_FILE" || REQUEST_RC=$?
case "$REQUEST_RC" in 2|3) exit "$REQUEST_RC" ;; esac
if [ "$REQUEST_RC" -ne 0 ]; then
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

if ! jq -e -cS --arg job "$JOB_ALIAS_ARG" '
  def valid_integer: (type == "number") and (. >= 1) and (. == floor);
  def valid_queue_id: (type == "number") and (. == floor) and ((. == -1) or (. >= 1));
  def valid_result: (type == "string") or (type == "null");
  if (type != "object") or
     (has("builds") | not) or
     ((.builds | type) != "array") or
     any(.builds[];
       (type != "object") or
       (has("number") | not) or ((.number | valid_integer) | not) or
       (has("building") | not) or ((.building | type) != "boolean") or
       (has("result") | not) or ((.result | valid_result) | not) or
       ((.queueId? // null) as $queue | (($queue == null) or ($queue | valid_queue_id)) | not)
     ) then
    error("malformed recent builds")
  else
    {
      job: $job,
      builds: (
        [.builds[] | {
          build: .number,
          building: .building,
          queueId: (.queueId? // null),
          result: .result
        }] | sort_by(.build) | reverse
      )
    }
  end
' "$RESPONSE_FILE" 2>/dev/null; then
  _jenkins_error "Jenkins recent builds response is malformed"
  exit "$EXIT_JENKINS"
fi
