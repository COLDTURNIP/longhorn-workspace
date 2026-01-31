#!/usr/bin/env bash
# map_interactions.sh - Production-focused Proto-driven mapping.
# Excludes vendor, tests, and non-Go files from gRPC client discovery.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Generate architectural indices in context/indices/ for CRD-controller mapping and gRPC topology.

Options:
  --execute           Write JSON indices (default dry-run)
  --force             Permit overwriting existing index files
  --json-log          Emit JSON logs
  --no-color          Disable ANSI color
  -n, --dry-run       Dry-run mode (default)
  -h, --help          Show this help
USAGE
}

defensive_parse_args "$@"
if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "map_interactions does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

defensive_require_clean_tree
if ! git remote get-url upstream >/dev/null 2>&1; then
  warn "Missing upstream remote; continuing"
elif ! git symbolic-ref refs/remotes/upstream/HEAD >/dev/null 2>&1; then
  warn "Cannot resolve refs/remotes/upstream/HEAD; run 'git remote set-head upstream --auto' later"
fi
defensive_record_safety_ref

INDEX_DIR="context/indices"
if [ "$DRY_RUN" = true ]; then
  info "[DRY-RUN] mkdir -p $INDEX_DIR"
else
  defensive_run_cmd "mkdir -p \"$INDEX_DIR\""
fi

# --- Phase 1: CRD-Controller Mapping ---
info "[INFO] Phase 1: Mapping CRDs via register.go"
CRD_WHITELIST=$(grep -rE "&\w+\{\}" repo/longhorn-manager/pkg/apis/longhorn repo/longhorn-manager/k8s/pkg/apis/longhorn 2>/dev/null | grep "register.go" | sed -E 's/.*&(\w+)\{\}.*/\1/' | grep -v "List$" | sort -u)
CONTROLLER_FILES=$(find repo/longhorn-manager/controller -name "*_controller.go" ! -name "base_controller.go" ! -name "*_test.go")
TMP_CRD=$(mktemp)
{
  echo "{"
  FIRST=true
  for file in $CONTROLLER_FILES; do
    STRUCT_NAME=$(grep -oP "type \K\w+Controller(?= struct)" "$file" || true)
    if [ -n "$STRUCT_NAME" ]; then
      KIND=${STRUCT_NAME%Controller}
      if echo "$CRD_WHITELIST" | grep -qxw "$KIND"; then
        if [ "$FIRST" = false ]; then echo ","; fi
        echo "  \"$KIND\": \"@repo/longhorn-manager/$file\""
        FIRST=false
      fi
    fi
  done
  echo "}"
} > "$TMP_CRD"

# --- Phase 2: gRPC Topology ---
info "[INFO] Phase 2: Mapping gRPC topology"
PROTO_FILES=$(find repo/types -name "*.proto" -not -path "*/vendor/*")
SERVICES=$(grep -hE "^service [A-Z]\w+" $PROTO_FILES | awk '{print $2}' | tr -d '{')
TMP_RPC=$(mktemp)
{
  echo "{"
  FIRST=true
  for svc in $SERVICES; do
    PROTO_PATH=$(grep -lE "service $svc\b" $PROTO_FILES | head -n 1)
    CLIENT_REPOS=$(grep -r --include="*.go" --exclude="*_test.go" "New${svc}Client" repo/ | \
        grep -v "repo/types" | grep -v "vendor/" | \
        cut -d'/' -f2 | sort -u | xargs | tr ' ' ',')
    if [ "$FIRST" = false ]; then echo ","; fi
    echo "  \"$svc\": {"
    echo "    \"definition\": \"@${PROTO_PATH#repo/}\"," 
    echo "    \"clients\": \"$CLIENT_REPOS\""
    echo "  }"
    FIRST=false
  done
  echo "}"
} > "$TMP_RPC"

write_index() {
  local tmp_file=$1 target=$2
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] Would update $target"
    return
  fi
  defensive_require_force "overwrite $target"
  if [ -f "$target" ]; then
    defensive_backup_file "$target"
  fi
  defensive_atomic_write "$target" < "$tmp_file"
  info "Updated $target"
}

write_index "$TMP_CRD" "$INDEX_DIR/crd-interaction.json"
write_index "$TMP_RPC" "$INDEX_DIR/rpc-topology.json"

rm -f "$TMP_CRD" "$TMP_RPC"

info "[SUCCESS] Architectural maps updated." 
