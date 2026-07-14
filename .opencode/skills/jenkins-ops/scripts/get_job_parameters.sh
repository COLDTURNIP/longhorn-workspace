#!/usr/bin/env bash
# Fetch and normalize live Jenkins parameter metadata for one approved job.

# Read-only entry points must never inherit the trigger dry-run state.
DRY_RUN=false
case "$0" in */*) SCRIPT_DIR=${0%/*} ;; *) SCRIPT_DIR=. ;; esac
SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd -P)
SCRIPT_NAME=${0##*/}
SKILL_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)

# The common library owns strict-mode setup, Jenkins HTTP behavior, the
# catalog resolver, and private-directory helper used below. It sources the
# defensive prelude exactly once after DRY_RUN is fixed.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/jenkins_common.sh"

usage() {
  printf 'Usage: %s <job-alias>\n' "$SCRIPT_NAME" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit "$EXIT_ARG"
fi

JOB_ALIAS_ARG=$1
case "$JOB_ALIAS_ARG" in
  ""|--*)
    usage
    exit "$EXIT_ARG"
    ;;
esac

# Resolve locally before any Jenkins environment or network work.  This keeps
# an unknown alias a pure input error and prevents it from reaching the API.
require_command jq
resolve_job "$JOB_ALIAS_ARG"

# fetch_parameter_definitions performs the environment, URL, transport, and
# schema checks.  Create the private output directory only after the local
# alias check; it is mode 0700 and the fetched JSON is mode 0600.
require_command curl
require_command mktemp
require_command chmod
new_private_dir
case "${PRIVATE_DIR:-}" in
  /*) ;;
  *)
    error 'Private temporary output is unavailable'
    exit "$EXIT_ENV"
    ;;
esac
PARAMETERS_FILE="$PRIVATE_DIR/parameters.json"
fetch_parameter_definitions "$JOB_ALIAS_ARG" "$PARAMETERS_FILE"

# The common writer owns mode enforcement and sorted-key JSON serialization.
# chmod is repeated defensively without exposing the file or its contents.
chmod 600 "$PARAMETERS_FILE" || {
  error 'Private temporary output is unavailable'
  exit "$EXIT_ENV"
}
printf '%s\n' "$PARAMETERS_FILE"
