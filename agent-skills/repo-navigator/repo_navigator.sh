#!/usr/bin/env bash
# repo_navigator.sh - Enhanced with Client-suffix fallback

resolve_script_dir() {
  local source_path=${BASH_SOURCE[0]} source_dir target
  while [ -h "$source_path" ]; do
    source_dir=$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P)
    target=$(readlink "$source_path")
    case "$target" in
      /*) source_path=$target ;;
      *) source_path="$source_dir/$target" ;;
    esac
  done
  CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P
}
SCRIPT_DIR=$(resolve_script_dir)
WORKSPACE_ROOT=$SCRIPT_DIR
while [ ! -f "$WORKSPACE_ROOT/AGENTS.md" ] || [ ! -d "$WORKSPACE_ROOT/agent-skills" ] || [ ! -d "$WORKSPACE_ROOT/repo" ]; do
  PARENT_DIR=$(dirname "$WORKSPACE_ROOT")
  if [ "$PARENT_DIR" = "$WORKSPACE_ROOT" ]; then
    printf '%s\n' "Longhorn workspace root not found" >&2
    exit 3
  fi
  WORKSPACE_ROOT=$PARENT_DIR
done
cd "$WORKSPACE_ROOT"
source "$WORKSPACE_ROOT/scripts/lib/defensive_prelude.sh"

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
