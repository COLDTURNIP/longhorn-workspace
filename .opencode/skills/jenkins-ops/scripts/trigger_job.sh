#!/usr/bin/env bash
# Validate live Jenkins parameters and optionally enqueue one approved job.

DRY_RUN=true
case "$0" in */*) SCRIPT_DIR=${0%/*} ;; *) SCRIPT_DIR=. ;; esac
SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd -P)
SCRIPT_NAME=${0##*/}
# shellcheck source=/dev/null
. "$SCRIPT_DIR/jenkins_common.sh"

usage() {
  printf 'Usage: %s [--execute] <job-alias> [key=value ...]\n' "$SCRIPT_NAME" >&2
}

if [ "${1:-}" = --execute ]; then
  DRY_RUN=false
  shift
fi
if [ "$#" -lt 1 ]; then
  usage
  exit "$EXIT_ARG"
fi
JOB_ALIAS_ARG=$1
shift
case "$JOB_ALIAS_ARG" in ""|--*) usage; exit "$EXIT_ARG" ;; esac

require_command jq
resolve_job "$JOB_ALIAS_ARG"
require_command curl
require_command mktemp
require_command chmod
new_private_dir
DEFINITIONS_FILE="$PRIVATE_DIR/parameters.json"
fetch_parameter_definitions "$JOB_ALIAS_ARG" "$DEFINITIONS_FILE"

SUPPORTS_SSH_PUBLIC_KEY=false
INJECT_SSH_PUBLIC_KEY=false
CALLER_SSH_PUBLIC_KEY=false
for argument in "$@"; do
  case "$argument" in
    CUSTOM_SSH_PUBLIC_KEY=*) CALLER_SSH_PUBLIC_KEY=true ;;
  esac
done
if jq -e 'any(.parameters[]; .name == "CUSTOM_SSH_PUBLIC_KEY" and .type == "StringParameterDefinition")' "$DEFINITIONS_FILE" >/dev/null 2>&1; then
  SUPPORTS_SSH_PUBLIC_KEY=true
fi
if [ "$SUPPORTS_SSH_PUBLIC_KEY" = true ] &&
   [ "$CALLER_SSH_PUBLIC_KEY" = false ]; then
  require_ssh_env public-key || exit $?
  if [ -n "$JENKINS_SSH_PUBLIC_KEY_CONTENT" ]; then
    INJECT_SSH_PUBLIC_KEY=true
  fi
fi




if ! jq -e '.buildable == true' "$DEFINITIONS_FILE" >/dev/null 2>&1; then
  _jenkins_error 'Jenkins job is not buildable'
  exit "$EXIT_ARG"
fi
if jq -e 'any(.parameters[]; .type == "PasswordParameterDefinition")' "$DEFINITIONS_FILE" >/dev/null 2>&1; then
  _jenkins_error 'Password parameters cannot be triggered by this wrapper'
  exit "$EXIT_ARG"
fi
if jq -e 'any(.parameters[]; (.type == "BooleanParameterDefinition" or .type == "StringParameterDefinition" or .type == "TextParameterDefinition" or .type == "ChoiceParameterDefinition" or .type == "PasswordParameterDefinition") | not)' "$DEFINITIONS_FILE" >/dev/null 2>&1; then
  _jenkins_error 'Unsupported Jenkins parameter type'
  exit "$EXIT_ARG"
fi


OVERRIDE_NAMES=()
OVERRIDE_VALUES=()
for argument in "$@"; do
  case "$argument" in
    *=*) name=${argument%%=*}; value=${argument#*=} ;;
    *) _jenkins_error 'Each parameter override must use key=value'; exit "$EXIT_ARG" ;;
  esac
  if [ -z "$name" ]; then
    _jenkins_error 'Parameter name must not be empty'
    exit "$EXIT_ARG"
  fi
  for existing_name in "${OVERRIDE_NAMES[@]}"; do
    if [ "$existing_name" = "$name" ]; then
      _jenkins_error 'Duplicate parameter override'
      exit "$EXIT_ARG"
    fi
  done
  parameter_type=$(jq -r --arg name "$name" '.parameters[] | select(.name == $name) | .type' "$DEFINITIONS_FILE" 2>/dev/null)
  if [ -z "$parameter_type" ]; then
    _jenkins_error 'Unknown Jenkins parameter override'
    exit "$EXIT_ARG"
  fi
  if printf '%s' "$name" | jq -R -e 'test("TOKEN|PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY"; "i")' >/dev/null 2>&1; then
    _jenkins_error 'Sensitive Jenkins parameters cannot be overridden'
    exit "$EXIT_ARG"
  fi
  case "$parameter_type" in
    BooleanParameterDefinition)
      case "$value" in true|false) ;; *) _jenkins_error 'Boolean parameter values must be lowercase true or false'; exit "$EXIT_ARG" ;; esac
      ;;
    ChoiceParameterDefinition)
      if ! jq -e --arg name "$name" --arg value "$value" 'any(.parameters[] | select(.name == $name) | .choices[]; . == $value)' "$DEFINITIONS_FILE" >/dev/null 2>&1; then
        _jenkins_error 'Choice parameter value is not allowed'
        exit "$EXIT_ARG"
      fi
      ;;
    StringParameterDefinition|TextParameterDefinition) ;;
    PasswordParameterDefinition)
      _jenkins_error 'Password parameters cannot be triggered by this wrapper'
      exit "$EXIT_ARG"
      ;;
    *)
      _jenkins_error 'Unsupported Jenkins parameter type'
      exit "$EXIT_ARG"
      ;;
  esac
  OVERRIDE_NAMES+=("$name")
  OVERRIDE_VALUES+=("$value")
done

if [ -n "${JENKINS_NOTIFY_SLACK_CHANNEL:-}" ]; then
  for existing_name in "${OVERRIDE_NAMES[@]}"; do
    case "$existing_name" in
      SEND_SLACK_NOTIFICATION|NOTIFY_SLACK_CHANNEL)
        _jenkins_error 'Slack notification parameters are managed by JENKINS_NOTIFY_SLACK_CHANNEL'
        exit "$EXIT_ARG"
        ;;
    esac
  done
  notify_channel_type=$(jq -r '.parameters[] | select(.name == "NOTIFY_SLACK_CHANNEL") | .type' "$DEFINITIONS_FILE" 2>/dev/null)
  send_notification_type=$(jq -r '.parameters[] | select(.name == "SEND_SLACK_NOTIFICATION") | .type' "$DEFINITIONS_FILE" 2>/dev/null)
  if [ "$notify_channel_type" != StringParameterDefinition ] ||
     [ "$send_notification_type" != BooleanParameterDefinition ]; then
    _jenkins_error 'Jenkins Slack notification parameter contract is unavailable'
    exit "$EXIT_JENKINS"
  fi
  OVERRIDE_NAMES+=(SEND_SLACK_NOTIFICATION NOTIFY_SLACK_CHANNEL)
  OVERRIDE_VALUES+=(true "$JENKINS_NOTIFY_SLACK_CHANNEL")
fi
if [ "$INJECT_SSH_PUBLIC_KEY" = true ]; then
  OVERRIDE_NAMES+=(CUSTOM_SSH_PUBLIC_KEY)
  OVERRIDE_VALUES+=("$JENKINS_SSH_PUBLIC_KEY_CONTENT")
fi


OVERRIDES_FILE="$PRIVATE_DIR/overrides.json"
printf '{}\n' > "$OVERRIDES_FILE"
chmod 600 "$OVERRIDES_FILE"
index=0
while [ "$index" -lt "${#OVERRIDE_NAMES[@]}" ]; do
  name=${OVERRIDE_NAMES[$index]}
  value=${OVERRIDE_VALUES[$index]}
  parameter_type=$(jq -r --arg name "$name" '.parameters[] | select(.name == $name) | .type' "$DEFINITIONS_FILE")
  next_file="$PRIVATE_DIR/overrides.next"
  if [ "$parameter_type" = BooleanParameterDefinition ]; then
    jq -S --arg name "$name" --argjson value "$value" '. + {($name): $value}' "$OVERRIDES_FILE" > "$next_file"
  else
    jq -S --arg name "$name" --arg value "$value" '. + {($name): $value}' "$OVERRIDES_FILE" > "$next_file"
  fi
  chmod 600 "$next_file"
  mv "$next_file" "$OVERRIDES_FILE"
  index=$((index + 1))
done
if ! jq -e --argjson overrides "$(cat "$OVERRIDES_FILE")" '
  all(.parameters[]; . as $parameter | $parameter.default.present or ($overrides | has($parameter.name)))
' "$DEFINITIONS_FILE" >/dev/null 2>&1; then
  _jenkins_error 'A Jenkins parameter without a default requires an override'
  exit "$EXIT_ARG"
fi

LAUNCH_PLAN="$PRIVATE_DIR/launch-plan.json"
if ! jq -S --argjson overrides "$(cat "$OVERRIDES_FILE")" --argjson warnings "$JOB_WARNINGS_JSON" '
  . as $metadata
  | {job:.job, buildable:true,
     parameters:(.parameters | map(
       . as $parameter
       | if ($overrides | has($parameter.name)) then
           {name:$parameter.name, type:$parameter.type, source:"override", value:$overrides[$parameter.name]}
         elif $parameter.default.present then
           {name:$parameter.name, type:$parameter.type, source:"jenkins-default", value:$parameter.default.value}
         else error("missing required parameter") end
       ) | sort_by(.name)),
     warnings:($warnings | to_entries | sort_by(.key) | map(.value))}
' "$DEFINITIONS_FILE" > "$LAUNCH_PLAN" 2>/dev/null; then
  _jenkins_error 'Unable to construct a Jenkins launch plan'
  exit "$EXIT_ARG"
fi
chmod 600 "$LAUNCH_PLAN"

if [ "$JOB_ALIAS_ARG" = e2e ]; then
  effective_v2=$(jq -r '.parameters[] | select(.name == "RUN_V2_TEST") | .value | if type == "boolean" then tostring else "invalid" end' "$LAUNCH_PLAN")
  if [ "$effective_v2" = false ]; then
    warning=$(jq -r '.jobs.e2e.warnings["RUN_V2_TEST=false"]' "$JOBS_FILE")
    _jenkins_error "$warning"
    exit "$EXIT_ARG"
  fi
fi

if [ "$DRY_RUN" = true ]; then
  printf '%s\n' "$LAUNCH_PLAN"
  exit "$EXIT_OK"
fi

CRUMB_FILE="$PRIVATE_DIR/crumb.json"
fetch_crumb "$CRUMB_FILE"
JENKINS_REQUEST_FORM=()
index=0
while [ "$index" -lt "${#OVERRIDE_NAMES[@]}" ]; do
  JENKINS_REQUEST_FORM+=("${OVERRIDE_NAMES[$index]}=${OVERRIDE_VALUES[$index]}")
  index=$((index + 1))
done
JENKINS_REQUEST_HEADERS=()
if [ "$JENKINS_CRUMB_DISABLED" != true ]; then
  JENKINS_REQUEST_HEADERS+=("${JENKINS_CRUMB_FIELD}: ${JENKINS_CRUMB_VALUE}")
fi
JENKINS_REQUEST_ARGS=()
POST_BODY="$PRIVATE_DIR/trigger-response"
request_status=0
jenkins_request POST "${JOB_URL}buildWithParameters" "$POST_BODY" || request_status=$?
case "$request_status" in
  2|3) exit "$request_status" ;;
esac
if [ "$request_status" -ne 0 ]; then
  _jenkins_error 'Jenkins trigger outcome is uncertain; inspect the Jenkins queue before any manual retry'
  exit "$EXIT_JENKINS"
fi
case "${JENKINS_HTTP_STATUS:-}" in
  201|302) ;;
  *) map_http_error "${JENKINS_HTTP_STATUS:-}" POST; exit "$EXIT_JENKINS" ;;
esac
location=$(response_header Location || true)
case "$location" in
  "${BASE_URL}/queue/item/"*/)
    queue_id=${location#"${BASE_URL}/queue/item/"}
    queue_id=${queue_id%/}
    case "$queue_id" in ""|*[!0-9]*|0) _jenkins_error 'Jenkins returned an invalid queue location'; exit "$EXIT_JENKINS" ;; esac
    ;;
  *) _jenkins_error 'Jenkins returned an invalid queue location'; exit "$EXIT_JENKINS" ;;
esac
jq -nS --arg job "$JOB_ALIAS_ARG" --argjson queueId "$queue_id" '{job:$job, queueId:$queueId, state:"QUEUED"}'
