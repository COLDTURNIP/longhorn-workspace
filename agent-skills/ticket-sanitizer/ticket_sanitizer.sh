#!/usr/bin/env bash
# ticket_sanitizer.sh - Advanced parsing for ticket organization and naming.
# Enforces ${org}-${ticket_id}-${description} format.

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
Usage: $SCRIPT_NAME [options] [ticket-root]

Normalize ticket directories to the format org-id-description and ensure standard subfolders exist.

Options:
  --execute           Apply renames and directory creation (default dry-run)
  --force             Permit filesystem mutations (required for renames)
  --json-log          Emit JSON logs
  --no-color          Disable ANSI color (not used here)
  -n, --dry-run       Force dry-run mode (default)
  -h, --help          Show help

Arguments:
  ticket-root        Optional path to ticket root (default: ticket)
USAGE
}

defensive_parse_args "$@"
if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 1 ]; then
  error "Too many arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

TICKET_ROOT=${DEFENSIVE_POSITIONAL_ARGS[0]:-ticket}

if ! git remote get-url upstream >/dev/null 2>&1; then
  warn "Missing upstream remote; continuing without it"
elif ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
  warn "Cannot resolve refs/remotes/upstream/HEAD; run 'git remote set-head upstream --auto' later"
fi
defensive_record_safety_ref

info "Ticket root: $TICKET_ROOT"
info "Dry-run mode: $DRY_RUN"
info "Force mode: $FORCE"

shopt -s nullglob
for folder in "$TICKET_ROOT"/*/; do
    [ -d "$folder" ] || continue
    original_name=$(basename "$folder")

    normalized=$(echo "$original_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

    if [[ $normalized =~ ^([0-9]+) ]]; then
        org="unknown"
        ticket_id=$(echo "$normalized" | cut -d'-' -f1)
        description=$(echo "$normalized" | cut -d'-' -f2-)
    elif [[ $normalized =~ ^([a-z0-9]+)-([0-9]+) ]]; then
        org=$(echo "$normalized" | cut -d'-' -f1)
        ticket_id=$(echo "$normalized" | cut -d'-' -f2)
        description=$(echo "$normalized" | cut -d'-' -f3-)
    else
        org="lh"
        ticket_id="0000"
        description="$normalized"
    fi

    if [ -z "$description" ] || [ "$description" == "$ticket_id" ]; then
        description="unknown"
    fi

    new_name="${org}-${ticket_id}-${description}"

    if [ "$original_name" != "$new_name" ]; then
        msg="Renaming ${original_name} -> ${new_name}"
        if [ "$DRY_RUN" = true ]; then
            info "[DRY-RUN] $msg"
        else
            defensive_require_force "rename ticket folder $original_name"
            defensive_run_cmd "mv \"$TICKET_ROOT/$original_name\" \"$TICKET_ROOT/$new_name\""
        fi
        current_folder="$TICKET_ROOT/$new_name"
    else
        current_folder="$folder"
    fi

    for required_dir in "$current_folder/logs/extracted" "$current_folder/repro"; do
        if [ "$DRY_RUN" = true ]; then
            info "[DRY-RUN] mkdir -p $required_dir"
        else
            defensive_run_cmd "mkdir -p \"$required_dir\""
        fi
    done

    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] touch $current_folder/description.md"
    else
        if [ ! -f "$current_folder/description.md" ]; then
            defensive_run_cmd "touch \"$current_folder/description.md\""
        fi
    fi
done

info "[SUCCESS] Ticket folders normalized to 3-segment format."
