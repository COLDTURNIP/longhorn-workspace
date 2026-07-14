#!/usr/bin/env bash
# Resolve one provisioned Jenkins build host and optionally access it over SSH.
# This wrapper never accepts a host argument: the host is taken only from the
# build console after the job alias and build number have been validated.
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
  printf 'Usage: %s [--resolve-only] <job-alias> <positive-build-number> [-- <remote-command> [args...]]\n' "$SCRIPT_NAME" >&2
}

RESOLVE_ONLY=false
if [ "${1:-}" = --resolve-only ]; then
  RESOLVE_ONLY=true
  shift
fi

if [ "$#" -lt 2 ]; then
  usage
  exit "$EXIT_ARG"
fi

JOB_ALIAS_ARG=$1
BUILD_NUMBER_ARG=$2
shift 2

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

REMOTE_COMMAND=()
if [ "$#" -gt 0 ]; then
  if [ "$1" != -- ]; then
    usage
    exit "$EXIT_ARG"
  fi
  shift
  if [ "$#" -eq 0 ]; then
    usage
    exit "$EXIT_ARG"
  fi
  REMOTE_COMMAND=("$@")
fi

# Resolve the fixed alias before checking credentials or contacting Jenkins.
# This keeps unknown aliases from reaching the network.
require_command jq
resolve_job "$JOB_ALIAS_ARG"

# SSH configuration is required for both modes because the resolve-only target
# records the configured user and identity path exactly as supplied.
require_ssh_env
if [ "$RESOLVE_ONLY" != true ]; then
  require_command ssh
fi
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
trap cleanup_private EXIT

CONSOLE_FILE="$PRIVATE_DIR/console.txt"
JENKINS_REQUEST_FORM=()
JENKINS_REQUEST_HEADERS=()
JENKINS_REQUEST_ARGS=()
REQUEST_RC=0
jenkins_request GET "${JOB_URL}${BUILD_NUMBER_ARG}/consoleText" "$CONSOLE_FILE" || REQUEST_RC=$?
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

REMOTE_HOSTS_FILE="$PRIVATE_DIR/remote-hosts.json"
extract_controlplane_hosts "$CONSOLE_FILE" "$REMOTE_HOSTS_FILE" "$JOB_ALIAS_ARG" "$BUILD_NUMBER_ARG" || exit $?
HOST_COUNT=$(jq -r '.hosts | length' "$REMOTE_HOSTS_FILE")
if [ "$HOST_COUNT" -ne 1 ]; then
  _jenkins_error 'Jenkins console did not contain exactly one valid control-plane host'
  exit "$EXIT_ARG"
fi
HOST=$(jq -r '.hosts[0]' "$REMOTE_HOSTS_FILE")

if [ "$RESOLVE_ONLY" = true ]; then
  TARGET_FILE="$PRIVATE_DIR/ssh-target.json"
  if ! jq -S -n \
      --arg job "$JOB_ALIAS_ARG" \
      --arg build "$BUILD_NUMBER_ARG" \
      --arg host "$HOST" \
      --arg user "$JENKINS_SSH_USER" \
      --arg identityFile "$JENKINS_SSH_IDENTITY_RESOLVED" \
      '{job:$job, build:($build | tonumber), host:$host, user:$user, identityFile:$identityFile}' \
      > "$TARGET_FILE" 2>/dev/null; then
    _jenkins_error 'Unable to write SSH target evidence'
    exit 3
  fi
  if ! chmod 600 "$TARGET_FILE" >/dev/null 2>&1; then
    _jenkins_error 'Private temporary output is unavailable'
    exit 3
  fi
  KEEP_PRIVATE=true
  printf '%s\n' "$TARGET_FILE"
  exit "$EXIT_OK"
fi

SSH_TARGET="${JENKINS_SSH_USER}@${HOST}"
SSH_ARGS=()
if [ "$#" -eq 0 ]; then
  SSH_ARGS=(-tt -i "$JENKINS_SSH_IDENTITY_RESOLVED" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$SSH_TARGET")
else
  SSH_ARGS=(-i "$JENKINS_SSH_IDENTITY_RESOLVED" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$SSH_TARGET")
  SSH_ARGS+=("${REMOTE_COMMAND[@]}")
fi

if ssh "${SSH_ARGS[@]}"; then
  exit "$EXIT_OK"
else
  _jenkins_error 'SSH connection or remote command failed'
  exit "$EXIT_SSH"
fi
