#!/usr/bin/env bash
# sync_crd_helm.sh - One-stop shop for CRD generation and Helm sync (workspace root)

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
Usage: $SCRIPT_NAME [options]

Regenerate CRDs in repo/longhorn-manager, copy them into repo/longhorn chart templates, and regenerate manifests.

Options:
  --execute           Run make/cp/bash commands (default dry-run)
  --force             Permit overwriting Helm chart CRDs
  --json-log          Emit JSON log lines
  --no-color          Disable ANSI color output
  -n, --dry-run       Dry-run mode (default)
  -h, --help          Show this help message
USAGE
}

defensive_parse_args "$@"
if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "sync-crd-helm does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

REPO_MANAGER="repo/longhorn-manager"
REPO_HELM="repo/longhorn"

if ! git remote get-url upstream >/dev/null 2>&1; then
  warn "Missing upstream remote; continuing"
elif ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
  warn "Cannot resolve refs/remotes/upstream/HEAD; run 'git remote set-head upstream --auto' later"
fi
defensive_record_safety_ref

stage_generate() {
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] (cd $REPO_MANAGER && make generate)"
  else
    defensive_run_cmd "(cd \"$REPO_MANAGER\" && make generate)"
  fi
}

stage_sync() {
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] mkdir -p $REPO_HELM/chart/templates"
    info "[DRY-RUN] cp $REPO_MANAGER/k8s/crds.yaml $REPO_HELM/chart/templates/crds.yaml (requires --force during execute)"
  else
    defensive_run_cmd "mkdir -p \"$REPO_HELM/chart/templates\""
    defensive_require_force "overwrite $REPO_HELM/chart/templates/crds.yaml"
    defensive_run_cmd "cp \"$REPO_MANAGER/k8s/crds.yaml\" \"$REPO_HELM/chart/templates/crds.yaml\""
  fi
}

stage_manifests() {
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] (cd $REPO_HELM && bash ./scripts/generate-longhorn-yaml.sh)"
  else
    defensive_run_cmd "(cd \"$REPO_HELM\" && bash ./scripts/generate-longhorn-yaml.sh)"
  fi
}

stage_ascii_check() {
  target="$REPO_HELM/deploy/longhorn.yaml"
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] grep -rP '[^\\x00-\\x7f]' $target"
    return
  fi
  if grep -rP '[^\x00-\x7f]' "$target" >/dev/null; then
    die "Non-ASCII characters detected in $target"
  else
    info "ASCII check passed for $target"
  fi
}

info "[1/3] Stage 1: Generating CRDs"
stage_generate
info "[2/3] Stage 2: Syncing CRDs into Helm chart"
stage_sync
info "[3/3] Stage 3: Regenerating manifests"
stage_manifests
info "[Check] Verifying ASCII-only compliance"
stage_ascii_check

info "[SUCCESS] CRD synchronization workflow complete."
