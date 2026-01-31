#!/usr/bin/env bash
# sync_crd_helm.sh - One-stop shop for CRD generation and Helm sync (workspace root)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

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
set -- "${DEFENSIVE_POSITIONAL_ARGS[@]:-}"
if [ "$#" -gt 0 ]; then
  error "sync-crd-helm does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

REPO_MANAGER="repo/longhorn-manager"
REPO_HELM="repo/longhorn"

defensive_require_clean_tree
defensive_require_upstream_head
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
