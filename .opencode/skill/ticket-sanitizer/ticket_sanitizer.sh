#!/bin/bash
# ticket_sanitizer.sh - Advanced parsing for ticket organization and naming.
# Enforces ${org}-${ticket_id}-${description} format.

set -e

TICKET_ROOT="ticket"
echo "[INFO] Starting Advanced Ticket Sanitization..."

for folder in "$TICKET_ROOT"/*/; do
    [ -d "$folder" ] || continue
    original_name=$(basename "$folder")

    # Normalize: Lowercase and replace spaces/hyphens with underscores
    # Note: We temporarily use a temporary separator or array to avoid splitting the org/id
    normalized=$(echo "$original_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

    # Step-by-step logic to parse components
    if [[ $normalized =~ ^([0-9]+) ]]; then
        # Case: Starts with a number (e.g., "1234-note" or "1234")
        org="unknown"
        ticket_id=$(echo "$normalized" | cut -d'-' -f1)
        description=$(echo "$normalized" | cut -d'-' -f2-)
    elif [[ $normalized =~ ^([a-z0-9]+)-([0-9]+) ]]; then
        # Case: Starts with org-id (e.g., "aaa-1234-note" or "aaa-1234")
        org=$(echo "$normalized" | cut -d'-' -f1)
        ticket_id=$(echo "$normalized" | cut -d'-' -f2)
        description=$(echo "$normalized" | cut -d'-' -f3-)
    else
        # Case: Doesn't match standard pattern, fallback to default org
        org="lh"
        ticket_id="0000"
        description="$normalized"
    fi

    # Post-processing components
    # 1. Ensure ticket_id is numeric (handled by regex match above mostly)
    # 2. If description is empty or equals the ticket_id, set to "unknown"
    if [ -z "$description" ] || [ "$description" == "$ticket_id" ]; then
        description="unknown"
    fi

    # Reconstruct standard name
    new_name="${org}-${ticket_id}-${description}"

    # Perform rename if necessary
    if [ "$original_name" != "$new_name" ]; then
        echo "[ACTION] Normalizing: ${original_name} -> ${new_name}"
        mv "$TICKET_ROOT/$original_name" "$TICKET_ROOT/$new_name"
        current_folder="$TICKET_ROOT/$new_name"
    else
        current_folder="$folder"
    fi

    # Initialize standard structure
    mkdir -p "$current_folder/logs/extracted"
    mkdir -p "$current_folder/repro"
    [ -f "$current_folder/description.md" ] || touch "$current_folder/description.md"
done

echo "[SUCCESS] All ticket folders normalized to 3-segment format."
