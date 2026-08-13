#!/usr/bin/env bash
# Download one artifact that is explicitly present in a Jenkins build.
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
  printf 'Usage: %s <job-alias> <positive-build-number> <relative-path>\n' "$SCRIPT_NAME" >&2
}

invalid_artifact_path() {
  _jenkins_error 'Artifact path is invalid'
  exit "$EXIT_ARG"
}

if [ "$#" -ne 3 ]; then
  usage
  exit "$EXIT_ARG"
fi

JOB_ALIAS_ARG=$1
BUILD_NUMBER_ARG=$2
RELATIVE_PATH_ARG=$3

case "$JOB_ALIAS_ARG" in
  ''|--*)
    usage
    exit "$EXIT_ARG"
    ;;
esac

# Do not use arithmetic here: Jenkins build numbers may be larger than the
# shell integer range. This is the canonical [1-9][0-9]* form.
case "$BUILD_NUMBER_ARG" in
  ''|*[!0-9]*|0*)
    usage
    exit "$EXIT_ARG"
    ;;
esac

# The requested path is only a relative POSIX path. Each component is encoded
# separately below, so separators cannot be supplied by an input component.
case "$RELATIVE_PATH_ARG" in
  ''|/*|*/|*//*|*[[:cntrl:]]*|*\\*)
    invalid_artifact_path
    ;;
esac
IFS=/ read -r -a ARTIFACT_SEGMENTS <<< "$RELATIVE_PATH_ARG"
for artifact_segment in "${ARTIFACT_SEGMENTS[@]}"; do
  case "$artifact_segment" in
    ''|.|..)
      invalid_artifact_path
      ;;
  esac
done

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
case "${PRIVATE_DIR:-}" in
  /*) ;;
  *)
    _jenkins_error 'Private temporary output is unavailable'
    exit "$EXIT_ENV"
    ;;
esac

# Evidence is retained only on success. Failed requests and malformed metadata
# leave no local path to discover or print.
KEEP_PRIVATE_DIR=false
trap 'if [ "${KEEP_PRIVATE_DIR:-false}" != true ] && [ -n "${PRIVATE_DIR:-}" ]; then rm -rf -- "$PRIVATE_DIR" >/dev/null 2>&1 || true; fi' EXIT

METADATA_FILE="$PRIVATE_DIR/metadata.json"
JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/api/json?tree=number,artifacts[fileName,relativePath]" "$METADATA_FILE" || REQUEST_RC=$?
case "$REQUEST_RC" in 2|3) exit "$REQUEST_RC" ;; esac
if [ "$REQUEST_RC" -ne 0 ]; then
  if [ "$REQUEST_RC" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
    _jenkins_error 'Jenkins transport error'
  else
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  fi
  exit "$EXIT_JENKINS"
fi
if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
  map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  exit "$EXIT_JENKINS"
fi

# Validate the complete required metadata shape before consulting the
# allowlist. Every published relativePath must itself be a safe relative path;
# this prevents malformed server metadata from becoming a URL component.
if ! jq -e --arg expected_build "$BUILD_NUMBER_ARG" '
  def positive_integer:
    if type != "number" then false else (floor == . and . > 0) end;
  def nonempty_string:
    if type != "string" then false else length > 0 end;
  def safe_relative_path:
    if (type != "string") or (length == 0) then false
    elif startswith("/") or endswith("/") or contains("//") or contains("\\") then false
    elif test("[[:cntrl:]]") then false
    else ([split("/")[] | (. == "" or . == "." or . == "..")] | any | not)
    end;
  if (type != "object") then false
  elif ((.number? | positive_integer) | not) then false
  elif ((.number | tostring) != $expected_build) then false
  elif ((.artifacts? | type) != "array") then false
  elif (any(.artifacts[];
      (type != "object")
      or ((.fileName? | nonempty_string) | not)
      or ((.relativePath? | safe_relative_path) | not)
    )) then false
  else true
  end
' "$METADATA_FILE" >/dev/null 2>&1; then
  _jenkins_error 'Jenkins artifact metadata is malformed'
  exit "$EXIT_JENKINS"
fi

MATCH_COUNT=$(jq -r --arg requested_path "$RELATIVE_PATH_ARG" '[.artifacts[] | select(.relativePath == $requested_path)] | length' "$METADATA_FILE" 2>/dev/null) || {
  _jenkins_error 'Jenkins artifact metadata is malformed'
  exit "$EXIT_JENKINS"
}
case "$MATCH_COUNT" in
  0)
    _jenkins_error 'Requested artifact is not allowlisted'
    exit "$EXIT_ARG"
    ;;
  1) ;;
  *)
    _jenkins_error 'Jenkins artifact metadata is ambiguous'
    exit "$EXIT_JENKINS"
    ;;
esac

# Encode each approved component, preserving only slash separators. The
# allowlisted path is the sole source of this URL suffix; no URL is accepted
# from user input or Jenkins metadata.
if ! ENCODED_PATH=$(jq -nr --arg requested_path "$RELATIVE_PATH_ARG" '$requested_path | split("/") | map(@uri) | join("/")' 2>/dev/null); then
  _jenkins_error 'Unable to encode artifact path'
  exit "$EXIT_JENKINS"
fi
if [ -z "$ENCODED_PATH" ]; then
  _jenkins_error 'Unable to encode artifact path'
  exit "$EXIT_JENKINS"
fi

ARTIFACT_FILE="$PRIVATE_DIR/artifact"
JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/artifact/${ENCODED_PATH}" "$ARTIFACT_FILE" || REQUEST_RC=$?
case "$REQUEST_RC" in 2|3) exit "$REQUEST_RC" ;; esac
if [ "$REQUEST_RC" -ne 0 ]; then
  if [ "$REQUEST_RC" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
    _jenkins_error 'Jenkins transport error'
  else
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  fi
  exit "$EXIT_JENKINS"
fi
if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
  map_http_error "${JENKINS_HTTP_STATUS:-}" GET || true
  exit "$EXIT_JENKINS"
fi

if [ ! -f "$ARTIFACT_FILE" ] || ! chmod 600 "$ARTIFACT_FILE" >/dev/null 2>&1; then
  _jenkins_error 'Private temporary output is unavailable'
  exit "$EXIT_ENV"
fi
KEEP_PRIVATE_DIR=true
printf '%s\n' "$ARTIFACT_FILE"
