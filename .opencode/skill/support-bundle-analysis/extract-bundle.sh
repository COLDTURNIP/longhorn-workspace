#!/bin/bash

# Support Bundle Extraction Script
# Automatically extracts support bundle and all node bundles
# Provides structure overview and diagnostic command suggestions

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script usage function
usage() {
    cat << EOF
Usage: $0 <bundle-file> [output-dir]

Arguments:
  bundle-file    Path to support bundle .zip file
  output-dir     Optional output directory (default: /tmp/sb-analysis-<timestamp>)

Interactive Mode (default):
  - Script will ask for extraction options
  - Options: temporary directory, specific directory, or already extracted

Example:
  $0 /path/to/supportbundle_*.zip
  $0 /path/to/bundle.zip /tmp/my-analysis

After extraction, you can analyze:
  - K8s resources: yamls/
  - Pod logs: logs/
  - Node system logs: nodes/<node-name>/logs/ ⭐

EOF
    exit 1
}

# Check if help requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# Parse arguments
BUNDLE_FILE=""
OUTPUT_DIR=""
ALREADY_EXTRACTED=false

if [ $# -ge 1 ]; then
    BUNDLE_FILE="$1"
fi

if [ $# -ge 2 ]; then
    OUTPUT_DIR="$2"
fi

# Validate bundle file
if [ -z "$BUNDLE_FILE" ]; then
    echo -e "${RED}Error: Bundle file not specified${NC}"
    usage
fi

if [ ! -f "$BUNDLE_FILE" ]; then
    echo -e "${RED}Error: Bundle file not found: $BUNDLE_FILE${NC}"
    exit 1
fi

# Interactive extraction options
echo ""
echo -e "${BLUE}=== Support Bundle Extraction ===${NC}"
echo ""

echo "Extraction Options:"
echo "1) Extract to temporary directory (recommended): /tmp/sb-analysis-<timestamp>"
echo "2) Extract to specific directory"
echo "3) Bundle already extracted"
echo ""
read -p "Choose option [1-3]: " extract_choice

case $extract_choice in
    1)
        OUTPUT_DIR="/tmp/sb-analysis-$(date +%s)"
        echo -e "${GREEN}Using temporary directory: $OUTPUT_DIR${NC}"
        ;;
    2)
        read -p "Enter extraction path: " user_path
        OUTPUT_DIR="$user_path"
        echo -e "${GREEN}Using custom directory: $OUTPUT_DIR${NC}"
        ;;
    3)
        read -p "Enter path to extracted bundle: " user_path
        OUTPUT_DIR="$user_path"
        ALREADY_EXTRACTED=true
        echo -e "${GREEN}Using already extracted bundle: $OUTPUT_DIR${NC}"
        ;;
    *)
        echo -e "${YELLOW}Invalid choice. Using temporary directory.${NC}"
        OUTPUT_DIR="/tmp/sb-analysis-$(date +%s)"
        ;;
esac

echo ""

# Step 1: Create output directory
if [ "$ALREADY_EXTRACTED" != "true" ]; then
    echo -e "${BLUE}Creating output directory...${NC}"
    mkdir -p "$OUTPUT_DIR"
    echo -e "${GREEN}Output directory: $OUTPUT_DIR${NC}"

    # Step 2: Extract main bundle
    echo -e "${BLUE}Extracting support bundle...${NC}"
    unzip -q "$BUNDLE_FILE" -d "$OUTPUT_DIR"

    # Find extracted bundle directory
    BUNDLE_DIR=$(find "$OUTPUT_DIR" -type d -name "supportbundle_*" | head -1)

    if [ -z "$BUNDLE_DIR" ]; then
        echo -e "${RED}Error: Could not find extracted bundle directory${NC}"
        exit 1
    fi

    echo -e "${GREEN}Extracted to: $BUNDLE_DIR${NC}"
    echo ""
fi

# Step 3: Extract all node bundles ⭐ CRITICAL FEATURE
if [ -d "$BUNDLE_DIR/nodes" ]; then
    echo -e "${BLUE}Extracting node bundles...${NC}"
    NODE_ZIPS=$(find "$BUNDLE_DIR/nodes" -maxdepth 1 -name "*.zip" 2>/dev/null)

    if [ -n "$NODE_ZIPS" ]; then
        NODE_COUNT=$(echo "$NODE_ZIPS" | wc -w)
        echo -e "${GREEN}Found $NODE_COUNT node bundles${NC}"

        for node_zip in $NODE_ZIPS; do
            node_name=$(basename "$node_zip" .zip)
            node_dir="$BUNDLE_DIR/nodes/$node_name"

            # Check if already extracted
            if [ -d "$node_dir" ]; then
                echo -e "${YELLOW}  - Skipping (already extracted): $node_name${NC}"
                continue
            fi

            # Extract node bundle
            mkdir -p "$node_dir"
            unzip -q "$node_zip" -d "$node_dir"
            echo -e "${GREEN}  ✓ Extracted: $node_name${NC}"
        done

        # Cleanup: remove original node zips to save space
        echo ""
        echo -e "${BLUE}Cleaning up original node zips...${NC}"
        for node_zip in $NODE_ZIPS; do
            rm -f "$node_zip"
        done
        echo -e "${GREEN}  ✓ Removed original node zips${NC}"
    else
        echo -e "${YELLOW}  ! No node bundles found in nodes/ directory${NC}"
    fi
else
    echo -e "${YELLOW}  ! No nodes/ directory found${NC}"
fi

# Step 4: Display structure and statistics
echo ""
echo -e "${BLUE}=== Bundle Structure ===${NC}"
echo ""

# Read metadata
if [ -f "$BUNDLE_DIR/metadata.yaml" ]; then
    echo -e "${GREEN}Metadata:${NC}"
    cat "$BUNDLE_DIR/metadata.yaml"
    echo ""
fi

# Count files
YAML_COUNT=$(find "$BUNDLE_DIR/yamls" -name "*.yaml" 2>/dev/null | wc -l)
LOG_COUNT=$(find "$BUNDLE_DIR/logs" -name "*.log" 2>/dev/null | wc -l)
NODE_DIR_COUNT=$(find "$BUNDLE_DIR/nodes" -maxdepth 1 -type d 2>/dev/null | wc -l)
NODE_LOG_COUNT=$(find "$BUNDLE_DIR/nodes" -name "*.log" 2>/dev/null | wc -l)

echo -e "${GREEN}Statistics:${NC}"
echo "  YAML files: $YAML_COUNT"
echo "  Pod log files: $LOG_COUNT"
echo "  Node directories: $NODE_DIR_COUNT"
echo "  Node log files: $NODE_LOG_COUNT"
echo ""

# List namespaces
if [ -d "$BUNDLE_DIR/yamls/namespaced" ]; then
    echo -e "${GREEN}Namespaces:${NC}"
    ls -1 "$BUNDLE_DIR/yamls/namespaced" | sed 's/^/  /'
    echo ""
fi

# List nodes
if [ -d "$BUNDLE_DIR/nodes" ]; then
    echo -e "${GREEN}Nodes:${NC}"
    find "$BUNDLE_DIR/nodes" -maxdepth 1 -type d | grep -v "^$BUNDLE_DIR/nodes$" | while read node_dir; do
        node_name=$(basename "$node_dir")
        # Count log files in each node
        logs=$(find "$node_dir" -name "*.log" 2>/dev/null | wc -l)
        echo "  $node_name ($logs log files)"
    done
    echo ""
fi

# Step 5: Node bundle structure overview ⭐ NEW
if [ -d "$BUNDLE_DIR/nodes" ]; then
    echo -e "${BLUE}Node Bundle Structure Overview:${NC}"
    echo "  Each node bundle contains:"
    echo "    - hostinfos/"
    echo "      - hostinfo"
    echo "      - kernel_config"
    echo "      - processes_info"
    echo "      - proc_mounts"
    echo "    - logs/"
    echo "      - dmesg.log          # Kernel errors, hardware failures"
    echo "      - kubelet.log        # Kubelet service logs"
    echo "      - k3s-service.log    # K3s main service logs"
    echo "      - k3s-agent-service.log  # K3s agent logs"
    echo "      - messages           # System main log"
    echo "      - spdk_tgt.log        # SPDK storage logs"
    echo ""
fi

# Step 6: Diagnostic command suggestions
echo -e "${BLUE}=== Quick Diagnostic Command Examples ===${NC}"
echo ""
echo -e "${GREEN}Search for errors in pod logs:${NC}"
echo "  grep -ri \"error\\|fail\\|panic\" $BUNDLE_DIR/logs/*/*/*.log"
echo ""
echo -e "${GREEN}Check node system logs:${NC}"
echo "  tail -100 $BUNDLE_DIR/nodes/*/logs/messages"
echo "  tail -100 $BUNDLE_DIR/nodes/*/logs/dmesg.log"
echo ""
echo -e "${GREEN}Check Kubelet logs:${NC}"
echo "  tail -100 $BUNDLE_DIR/nodes/*/logs/kubelet.log"
echo ""
echo -e "${GREEN}Analysis directory:${NC}"
echo "  cd $BUNDLE_DIR"
echo ""

echo -e "${GREEN}✓ Bundle extraction completed${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Confirm bundle path: $BUNDLE_DIR"
echo "  2. Describe your problem objective (e.g., 'Why is Pod X crashing?')"
echo "  3. Follow Support Bundle Analysis Skill (Architecture 2.0):"
echo "     - Start with SKILL.md (Pre-Analysis + Phase 0-1)"
echo "     - Proceed to diagnostic-flows.md for deep diagnosis (Phase 2-3)"
echo "     - Use patterns-library.md for root cause analysis (Phase 4)"
echo ""

