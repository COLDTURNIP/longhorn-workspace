#!/bin/bash
# repo_navigator.sh - Enhanced with Client-suffix fallback

set -e
CRD_MAP="context/indices/crd-interaction.json"
RPC_MAP="context/indices/rpc-topology.json"

case "$1" in
    --crd)
        KIND=$2
        PATH_OUT=$(jq -r ".\"$KIND\"" "$CRD_MAP")
        echo "[TARGET] File: $PATH_OUT"
        ;;
    --rpc)
        SVC=$2
        RESULT=$(jq -r ".\"$SVC\"" "$RPC_MAP")
        if [ "$RESULT" == "null" ] && [[ "$SVC" == *ServiceClient ]]; then
            BASE_SVC=${SVC%Client}
            echo "[INFO] Not found $SVC, trying base service: $BASE_SVC"
            RESULT=$(jq -r ".\"$BASE_SVC\"" "$RPC_MAP")
        fi

        if [ "$RESULT" != "null" ]; then
            DEFINITION=$(echo "$RESULT" | jq -r ".definition")
            CLIENTS=$(echo "$RESULT" | jq -r ".clients")
            echo "[TARGET] Proto: $DEFINITION"
            echo "[CLIENTS] Consumed by: $CLIENTS"
        else
            echo "[ERROR] No RPC service found for $SVC."
        fi
        ;;
esac
