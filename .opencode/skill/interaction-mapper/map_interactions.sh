#!/bin/bash
# map_interactions.sh - Production-focused Proto-driven mapping.
# Excludes vendor, tests, and non-Go files from gRPC client discovery.

set -e

INDEX_DIR="context/indices"
mkdir -p "$INDEX_DIR"

# --- Phase 1: CRD-Controller Mapping (Source of Truth: register.go) ---
echo "[INFO] Phase 1: Mapping CRDs via register.go..."
CRD_WHITELIST=$(grep -rE "&\w+\{\}" repo/longhorn-manager/pkg/apis/longhorn repo/longhorn-manager/k8s/pkg/apis/longhorn 2>/dev/null | grep "register.go" | sed -E 's/.*&(\w+)\{\}.*/\1/' | grep -v "List$" | sort -u)

echo "{" > "$INDEX_DIR/crd-interaction.json"
FIRST=true
CONTROLLER_FILES=$(find repo/longhorn-manager/controller -name "*_controller.go" ! -name "base_controller.go" ! -name "*_test.go")
for file in $CONTROLLER_FILES; do
    STRUCT_NAME=$(grep -oP "type \K\w+Controller(?= struct)" "$file" || true)
    if [ -n "$STRUCT_NAME" ]; then
        KIND=${STRUCT_NAME%Controller}
        if echo "$CRD_WHITELIST" | grep -qxw "$KIND"; then
            if [ "$FIRST" = false ]; then echo "," >> "$INDEX_DIR/crd-interaction.json"; fi
            echo "  \"$KIND\": \"@repo/longhorn-manager/$file\"" >> "$INDEX_DIR/crd-interaction.json"
            FIRST=false
        fi
    fi
done
echo "}" >> "$INDEX_DIR/crd-interaction.json"

# --- Phase 2: Refined Production gRPC Topology ---
echo "[INFO] Phase 2: Mapping gRPC Topology (Source Files Only)..."

# 1. Discover services from .proto files in @repo/types (excluding vendor)
PROTO_FILES=$(find repo/types -name "*.proto" -not -path "*/vendor/*")
SERVICES=$(grep -hE "^service [A-Z]\w+" $PROTO_FILES | awk '{print $2}' | tr -d '{')

echo "{" > "$INDEX_DIR/rpc-topology.json"
FIRST=true

for svc in $SERVICES; do
    PROTO_PATH=$(grep -lE "service $svc\b" $PROTO_FILES | head -n 1)
    
    # NEW: Restricted grep to only scan *.go files and ignore *_test.go
    # Also continues to exclude vendor/ and types/ generated code.
    CLIENT_REPOS=$(grep -r --include="*.go" --exclude="*_test.go" "New${svc}Client" repo/ | \
        grep -v "repo/types" | grep -v "vendor/" | \
        cut -d'/' -f2 | sort -u | xargs | tr ' ' ',')

    if [ "$FIRST" = false ]; then echo "," >> "$INDEX_DIR/rpc-topology.json"; fi
    echo "  \"$svc\": {" >> "$INDEX_DIR/rpc-topology.json"
    echo "    \"definition\": \"@${PROTO_PATH#repo/}\"," >> "$INDEX_DIR/rpc-topology.json"
    echo "    \"clients\": \"$CLIENT_REPOS\"" >> "$INDEX_DIR/rpc-topology.json"
    echo "  }" >> "$INDEX_DIR/rpc-topology.json"
    FIRST=false
done
echo "}" >> "$INDEX_DIR/rpc-topology.json"

echo "[SUCCESS] Architectural maps are now exclusively based on production Go source code."
