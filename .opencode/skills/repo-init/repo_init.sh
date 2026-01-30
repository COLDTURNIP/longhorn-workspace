#!/bin/bash
# Usage: ./repo_init.sh
# Batch clone and initialize all repos from repo/repo-list, supporting 'account/repo_name' format, only keep local 'upstream' branch

set -e

REPO_LIST="repo/repo-list"
REPO_DIR="repo"

if [ ! -f "$REPO_LIST" ]; then
    echo "ERROR: $REPO_LIST not found."
    exit 1
fi

while IFS= read -r ENTRY || [ -n "$ENTRY" ]; do
    ENTRY="$(echo "$ENTRY" | xargs)"
    [[ -z "$ENTRY" || "$ENTRY" =~ ^# ]] && continue

    # Only accept 'account/repo_name' format
    if [[ ! "$ENTRY" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
        echo "[WARN] Skip invalid format: '$ENTRY' (expect account/repo_name)" >&2
        continue
    fi

    account="${ENTRY%%/*}"
    reponame="${ENTRY##*/}"
    TARGET_PATH="${REPO_DIR}/${reponame}"

    if [ -d "$TARGET_PATH/.git" ]; then
        echo "[SKIP] $ENTRY already exists at $TARGET_PATH"
        continue
    fi

    echo "------------------------------------------------------------"
    echo "[ACTION] Cloning $ENTRY from upstream..."

    UPSTREAM_URL="https://github.com/${account}/${reponame}.git"
    git clone "$UPSTREAM_URL" "$TARGET_PATH" --origin upstream

    cd "$TARGET_PATH"

    # Detect default branch of upstream remote
    MAIN_BRANCH=$(git remote show upstream | grep 'HEAD branch' | cut -d' ' -f5)
    echo "[INFO] Detected upstream default branch: $MAIN_BRANCH"

    git switch -c upstream "upstream/$MAIN_BRANCH"

    # Delete all local branches except 'upstream'
    for branch in $(git branch --format='%(refname:short)'); do
      if [ "$branch" != "upstream" ]; then
        git branch -D "$branch" 2>/dev/null || true
        echo "[INFO] Removed local branch: $branch"
      fi
    done

    cd - > /dev/null
    echo "[DONE] $ENTRY complete."
done < "$REPO_LIST"

echo "=== All repositories processed ==="