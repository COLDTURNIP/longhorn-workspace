#!/usr/bin/env bash
# repo_navigator.sh - Enhanced with Client-suffix fallback

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [--crd KIND | --rpc SERVICE]

Query interaction indices:
  --crd KIND     Print controller file for CRD
  --rpc SERVICE  Print proto definition and client repos for service
Flags: --execute/--dry-run, --json-log, --no-color, --force (unused)
USAGE
}

NAV_POSITIONAL_ARGS=()
DEFENSIVE_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --crd|--rpc)
      if [ "$#" -lt 2 ]; then
        error "Missing value for $1"
        defensive_show_help
        exit "$EXIT_ARG"
      fi
      NAV_POSITIONAL_ARGS+=("$1" "$2")
      shift 2
      ;;
    *)
      DEFENSIVE_ARGS+=("$1")
      shift
      ;;
  esac
done

defensive_parse_args "${DEFENSIVE_ARGS[@]}"
DEFENSIVE_POSITIONAL_ARGS=("${NAV_POSITIONAL_ARGS[@]}" "${DEFENSIVE_POSITIONAL_ARGS[@]}")

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -lt 2 ]; then
  error "Missing required arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

CRD_MAP="context/indices/crd-interaction.json"
RPC_MAP="context/indices/rpc-topology.json"

cmd=${DEFENSIVE_POSITIONAL_ARGS[0]}
arg=${DEFENSIVE_POSITIONAL_ARGS[1]}

if [ "$cmd" = "--crd" ]; then
  PATH_OUT=$(jq -r ".\"$arg\"" "$CRD_MAP")
  if [ "$PATH_OUT" = "null" ]; then
    error "No CRD mapping found for $arg"
    exit "$EXIT_ENV"
  fi
  info "[TARGET] File: $PATH_OUT"
elif [ "$cmd" = "--rpc" ]; then
  RESULT=$(jq -r ".\"$arg\"" "$RPC_MAP")
  if [ "$RESULT" == "null" ] && [[ "$arg" == *ServiceClient ]]; then
      BASE_SVC=${arg%Client}
      warn "Not found $arg, trying base service: $BASE_SVC"
      RESULT=$(jq -r ".\"$BASE_SVC\"" "$RPC_MAP")
  fi
  if [ "$RESULT" != "null" ]; then
      DEFINITION=$(echo "$RESULT" | jq -r ".definition")
      CLIENTS=$(echo "$RESULT" | jq -r ".clients")
      info "[TARGET] Proto: $DEFINITION"
      info "[CLIENTS] Consumed by: $CLIENTS"
  else
      error "No RPC service found for $arg"
      exit "$EXIT_ENV"
  fi
else
  error "Unknown mode: $cmd"
  defensive_show_help
  exit "$EXIT_ARG"
fi
