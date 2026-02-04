#!/usr/bin/env bash
set -euo pipefail

# check_test_diff.sh
# Guard script to prevent accidental deletion or large removals of *_test.go files
# Usage: check_test_diff.sh [--repo <path>] | [-C <path>]

repo=""

usage(){
  cat <<EOF
Usage: $0 [--repo <path>] | [-C <path>]

Runs git diff against HEAD in the current repository (or the one given by --repo / -C).
Exits with status 1 if any *_test.go file is deleted, or if any *_test.go file
has more than 100 deleted lines in the diff. Otherwise exits 0.
EOF
}

if [ "$#" -gt 0 ]; then
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo|-C)
        shift
        if [ "$#" -eq 0 ]; then
          echo "Error: missing path for $1" >&2
          usage
          exit 2
        fi
        repo="$1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 2
        ;;
    esac
  done
fi

git_cmd=(git)
if [ -n "$repo" ]; then
  if [ ! -d "$repo" ]; then
    echo "Error: repository path '$repo' does not exist" >&2
    exit 2
  fi
  # Verify this is a git repository
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: '$repo' is not a git repository" >&2
    exit 2
  fi
  git_cmd+=( -C "$repo" )
fi

# 1) Detect deleted test files using required command
mapfile -t deleted_tests < <("${git_cmd[@]}" diff --name-status --diff-filter=D HEAD 2>/dev/null | awk '{print $2}' | grep -E '_test\.go$' || true)

if [ "${#deleted_tests[@]}" -gt 0 ]; then
  echo "Error: the following *_test.go files were deleted in git diff HEAD:" >&2
  for f in "${deleted_tests[@]}"; do
    echo "  - $f" >&2
  done
  exit 1
fi

# 2) Check deleted line counts for added/changed/modified files using required command
declare -a too_many_deleted=()

# Iterate numstat lines: added\tdeleted\tpath
while IFS=$'\t' read -r added deleted path; do
  # only consider test files
  case "$path" in
    *_test.go)
      # deleted may be '-' for binary files; ensure numeric
      if [[ "$deleted" =~ ^[0-9]+$ ]]; then
        if [ "$deleted" -gt 100 ]; then
          too_many_deleted+=("$path:$deleted")
        fi
      fi
      ;;
    *)
      ;;
  esac
done < <("${git_cmd[@]}" diff --numstat --diff-filter=ACM HEAD 2>/dev/null || true)

if [ "${#too_many_deleted[@]}" -gt 0 ]; then
  echo "Error: the following *_test.go files have more than 100 deleted lines in git diff HEAD:" >&2
  for entry in "${too_many_deleted[@]}"; do
    IFS=':' read -r p c <<<"$entry"
    echo "  - $p : $c deleted lines" >&2
  done
  exit 1
fi

echo "OK: no deleted *_test.go files and no *_test.go with >100 deleted lines in git diff HEAD"
exit 0
