#!/bin/bash
# sync_crd_helm.sh - One-stop shop for CRD generation and Helm sync
# MUST be run from the workspace root.

set -e

# Define relative paths
REPO_MANAGER="repo/longhorn-manager"
REPO_HELM="repo/longhorn"

echo "[1/3] Stage 1: Generating CRDs in ${REPO_MANAGER}..."
cd "${REPO_MANAGER}"
make generate  # Executes controller-gen and code-generator
cd - > /dev/null

echo "[2/3] Stage 2: Syncing CRDs to ${REPO_HELM}..."
# Ensure destination directory exists
mkdir -p "${REPO_HELM}/chart/templates"
cp "${REPO_MANAGER}/k8s/crds.yaml" "${REPO_HELM}/chart/templates/crds.yaml"

echo "[3/3] Stage 3: Generating final manifests in ${REPO_HELM}..."
cd "${REPO_HELM}"
bash ./scripts/generate-longhorn-yaml.sh
cd - > /dev/null

# Compliance Check (Global Policy)
echo "[Check] Verifying ASCII-only compliance for generated files..."
if grep -rP '[^\x00-\x7f]' "${REPO_HELM}/deploy/longhorn.yaml"; then
    echo "[ERROR] Non-ASCII characters detected!"
    exit 1
fi

echo "[SUCCESS] CRD synchronization complete."
