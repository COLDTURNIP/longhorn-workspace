#!/bin/bash
# ascii_scanner.sh - Force ASCII-only compliance check.
# Target: 0x00-0x7F range only.

set -e

TARGET=$1

if [ -z "$TARGET" ]; then
    echo "[USAGE] bash $0 <target_path>"
    exit 1
fi

# Clean @ prefix if provided by AI
TARGET=${TARGET#@}

if [ ! -e "$TARGET" ]; then
    echo "[ERROR] Target path does not exist: $TARGET"
    exit 1
fi

echo "[INFO] Scanning for non-ASCII characters in: $TARGET"

# Use grep to find characters outside the 00-7F range
# -n: Line number, -r: Recursive, -P: Perl regex, -I: Ignore binaries
# LC_ALL=C ensures grep treats files as byte sequences
FOUND_VIOLATIONS=$(LC_ALL=C grep -rnP '[^\x00-\x7f]' "$TARGET" --exclude-dir=".git" || true)

if [ -n "$FOUND_VIOLATIONS" ]; then
    echo "------------------------------------------------------------"
    echo "[VIOLATION DETECTED] Non-ASCII characters found:"
    echo "$FOUND_VIOLATIONS"
    echo "------------------------------------------------------------"
    echo "[ERROR] Compliance check failed. Please remove non-ASCII characters (emojis, smart quotes, etc.)."
    exit 1
else
    echo "[SUCCESS] ASCII compliance check passed for: $TARGET"
    exit 0
fi
