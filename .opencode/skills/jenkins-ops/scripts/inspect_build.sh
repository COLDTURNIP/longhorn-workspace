#!/usr/bin/env bash
# Collect private evidence for one completed or in-progress Jenkins build.
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
case "$BUILD_NUMBER_ARG" in
  ""|*[!0-9]*|0*)
    usage
    exit "$EXIT_ARG"
    ;;
esac

# Resolve the fixed catalog before checking credentials or contacting Jenkins.
require_command jq
resolve_job "$JOB_ALIAS_ARG"

require_command curl
require_command mktemp
require_command chmod
require_jenkins_env
normalize_base_url
build_job_url "$JOB_ALIAS_ARG"

new_private_dir
trap 'if [ -n "${PRIVATE_DIR:-}" ]; then rm -rf "$PRIVATE_DIR"; fi' EXIT

RAW_BUILD_FILE="$PRIVATE_DIR/build-response.json"
NORMALIZED_FILE="$PRIVATE_DIR/normalized-build.json"
BUILD_FILE="$PRIVATE_DIR/build.json"
ARTIFACTS_FILE="$PRIVATE_DIR/artifacts.json"
CONSOLE_FILE="$PRIVATE_DIR/console.txt"
REMOTE_HOSTS_FILE="$PRIVATE_DIR/remote-hosts.json"
JUNIT_FILE="$PRIVATE_DIR/test-report.json"
ROBOT_FILE="$PRIVATE_DIR/robot-report.json"
MANIFEST_FILE="$PRIVATE_DIR/inspection-manifest.json"

# The filtered metadata request is the only source for build parameters and
# artifact names. Raw metadata is removed after normalization so unredacted
# values do not remain in the private directory.
JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/api/json?tree=number,queueId,building,result,artifacts[fileName,relativePath],actions[_class,urlName,parameters[name,value]]" "$RAW_BUILD_FILE" || REQUEST_RC=$?
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

# Validate required Jenkins metadata and normalize it into the two public
# evidence objects. Actions may be empty objects, as Jenkins commonly returns
# for actions that have no parameters; malformed populated fields fail closed.
if ! jq -S -e --arg job "$JOB_ALIAS_ARG" --arg build "$BUILD_NUMBER_ARG" '
  def fail: error("malformed build metadata");
  def scalar: (type == "string" or type == "number" or type == "boolean" or type == "null");
  def sensitive: test("TOKEN|PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY"; "i");
  def malformed_action:
    if type != "object" then true
    elif (has("urlName") and (.urlName != null) and ((.urlName | type) != "string")) then true
    else false
    end;
  def malformed_parameter:
    if type != "object" then true
    elif (has("name") | not) then true
    elif ((.name | type) != "string") then true
    elif ((.name | length) == 0) then true
    elif (has("value") | not) then true
    elif ((.value | scalar) | not) then true
    else false
    end;
  def malformed_artifact:
    if type != "object" then true
    elif (has("fileName") | not) then true
    elif ((.fileName | type) != "string") then true
    elif (has("relativePath") | not) then true
    elif ((.relativePath | type) != "string") then true
    else false
    end;
  . as $root
  | if ($root | type) != "object" then fail
    elif (($root | has("number")) | not) or (($root.number | type) != "number") or (($root.number | floor) != $root.number) or ($root.number <= 0) or (($root.number | tostring) != $build) then fail
    elif (($root.queueId? // null) != null) and ((($root.queueId | type) != "number") or (($root.queueId | floor) != $root.queueId) or (($root.queueId <= 0) and ($root.queueId != -1))) then fail
    elif (($root | has("building")) | not) or (($root.building | type) != "boolean") then fail
    elif (($root | has("result")) | not) or (($root.result | type) != "string" and ($root.result | type) != "null") then fail
    elif (($root | has("actions")) | not) or (($root.actions | type) != "array") then fail
    elif (($root | has("artifacts")) | not) or (($root.artifacts | type) != "array") then fail
    elif (any($root.actions[]; malformed_action)) then fail
    else
      ([ $root.actions[]
         | if ((.parameters? // null) == null) then []
           elif ((.parameters | type) != "array") then fail
           else .parameters
           end
       ] | (add // [])) as $raw_parameters
      | if (any($raw_parameters[]; malformed_parameter)) then fail
        else
          ($raw_parameters | map({name:.name, value:(if (.name | sensitive) then "[REDACTED]" else .value end)} ) | sort_by(.name)) as $parameters
          | ($root.artifacts | map(if malformed_artifact then fail else {fileName:.fileName, relativePath:.relativePath} end) | sort_by(.relativePath)) as $artifacts
          | {build:{job:$job, build:($root.number), queueId:($root.queueId? // null), building:$root.building, result:$root.result, parameters:$parameters}, artifacts:$artifacts, robot:(any($root.actions[]; (type == "object") and (.urlName? == "robot")))}
        end
    end
' "$RAW_BUILD_FILE" > "$NORMALIZED_FILE" 2>/dev/null; then
  rm -f "$RAW_BUILD_FILE" "$NORMALIZED_FILE" "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true
  _jenkins_error "Jenkins build metadata is malformed"
  exit "$EXIT_JENKINS"
fi
chmod 600 "$NORMALIZED_FILE" >/dev/null 2>&1 || {
  _jenkins_error "Private temporary output is unavailable"
  exit 3
}
if ! jq -S -e '.build' "$NORMALIZED_FILE" > "$BUILD_FILE" 2>/dev/null || ! jq -S -e '{artifacts:.artifacts}' "$NORMALIZED_FILE" > "$ARTIFACTS_FILE" 2>/dev/null; then
  _jenkins_error "Jenkins build metadata is malformed"
  exit "$EXIT_JENKINS"
fi
chmod 600 "$BUILD_FILE" "$ARTIFACTS_FILE" >/dev/null 2>&1 || {
  _jenkins_error "Private temporary output is unavailable"
  exit 3
}
ROBOT_AVAILABLE=$(jq -r '.robot' "$NORMALIZED_FILE" 2>/dev/null) || {
  _jenkins_error "Jenkins build metadata is malformed"
  exit "$EXIT_JENKINS"
}
rm -f "$RAW_BUILD_FILE" "$NORMALIZED_FILE" "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true

# Fetch the complete console evidence. It remains private and is never echoed.
JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/consoleText" "$CONSOLE_FILE" || REQUEST_RC=$?
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
chmod 600 "$CONSOLE_FILE" >/dev/null 2>&1 || {
  _jenkins_error "Private temporary output is unavailable"
  exit 3
}
rm -f "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true

# Extract exact control-plane assignments through the shared validator.
extract_controlplane_hosts "$CONSOLE_FILE" "$REMOTE_HOSTS_FILE" "$JOB_ALIAS_ARG" "$BUILD_NUMBER_ARG" || exit $?

# Optional JUnit and Robot reports are fetched only at their exact endpoints.
# A 404 means unavailable; every other non-success response is an error.
JUNIT_REF=""
JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/testReport/api/json" "$JUNIT_FILE" || REQUEST_RC=$?
case "$REQUEST_RC" in 2|3) exit "$REQUEST_RC" ;; esac
if [ "$REQUEST_RC" -ne 0 ]; then
  if [ "$REQUEST_RC" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
    _jenkins_error "Jenkins transport error"
  else
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  fi
  exit "$EXIT_JENKINS"
fi
case "${JENKINS_HTTP_STATUS:-}" in
  404)
    rm -f "$JUNIT_FILE" "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true
    ;;
  200)
    if ! jq -e 'type == "object"' "$JUNIT_FILE" >/dev/null 2>&1; then
      _jenkins_error "Jenkins JUnit report is malformed"
      exit "$EXIT_JENKINS"
    fi
    chmod 600 "$JUNIT_FILE" >/dev/null 2>&1 || {
      _jenkins_error "Private temporary output is unavailable"
      exit 3
    }
    JUNIT_REF="test-report.json"
    rm -f "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true
    ;;
  *)
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
    exit "$EXIT_JENKINS"
    ;;
esac

ROBOT_REF=""
if [ "$ROBOT_AVAILABLE" = true ]; then
  JENKINS_REQUEST_FORM=()
  JENKINS_REQUEST_HEADERS=()
  JENKINS_REQUEST_ARGS=()
  REQUEST_RC=0
  jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/robot/api/json" "$ROBOT_FILE" || REQUEST_RC=$?
  case "$REQUEST_RC" in 2|3) exit "$REQUEST_RC" ;; esac
  if [ "$REQUEST_RC" -ne 0 ]; then
    if [ "$REQUEST_RC" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
      _jenkins_error "Jenkins transport error"
    else
      map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
    fi
    exit "$EXIT_JENKINS"
  fi
  case "${JENKINS_HTTP_STATUS:-}" in
    404)
      rm -f "$ROBOT_FILE" "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true
      ;;
    200)
      if ! jq -e 'type == "object"' "$ROBOT_FILE" >/dev/null 2>&1; then
        _jenkins_error "Jenkins Robot report is malformed"
        exit "$EXIT_JENKINS"
      fi
      chmod 600 "$ROBOT_FILE" >/dev/null 2>&1 || {
        _jenkins_error "Private temporary output is unavailable"
        exit 3
      }
      ROBOT_REF="robot-report.json"
      rm -f "${JENKINS_HTTP_HEADERS:-}" >/dev/null 2>&1 || true
      ;;
    *)
      map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
      exit "$EXIT_JENKINS"
      ;;
  esac
fi

# Construct the manifest only after every required and optional evidence file
# is complete. Its file references are relative to this private directory.
if ! jq -S -n --arg job "$JOB_ALIAS_ARG" --argjson build "$BUILD_NUMBER_ARG" --slurpfile build_data "$BUILD_FILE" --arg junit "$JUNIT_REF" --arg robot "$ROBOT_REF" '
  {job:$job, build:$build, result:$build_data[0].result,
   files:{build:"build.json", console:"console.txt", junit:(if $junit == "" then null else $junit end), robot:(if $robot == "" then null else $robot end), artifacts:"artifacts.json", remoteHosts:"remote-hosts.json"}}
' > "$MANIFEST_FILE" 2>/dev/null; then
  _jenkins_error "Unable to write inspection manifest"
  exit "$EXIT_JENKINS"
fi
chmod 600 "$MANIFEST_FILE" >/dev/null 2>&1 || {
  _jenkins_error "Private temporary output is unavailable"
  exit 3
}
trap - EXIT
printf '%s\n' "$MANIFEST_FILE"
