#!/usr/bin/env bash
set -euo pipefail

# check_test_diff.sh
# Guard script to prevent accidental deletion or large removals of *_test.go files
# Usage: check_test_diff.sh [--repo <path>] | [-C <path>]
resolve_script_dir() {
  local source_path=${BASH_SOURCE[0]} source_dir target
  while [ -h "$source_path" ]; do
    source_dir=$(CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P)
    target=$(readlink "$source_path")
    case "$target" in
      /*) source_path=$target ;;
      *) source_path="$source_dir/$target" ;;
    esac
  done
  CDPATH= cd -- "$(dirname -- "$source_path")" && pwd -P
}
SCRIPT_DIR=$(resolve_script_dir)
WORKSPACE_ROOT=$SCRIPT_DIR
while [ ! -f "$WORKSPACE_ROOT/AGENTS.md" ] || [ ! -d "$WORKSPACE_ROOT/agent-skills" ] || [ ! -d "$WORKSPACE_ROOT/repo" ]; do
  PARENT_DIR=$(dirname "$WORKSPACE_ROOT")
  if [ "$PARENT_DIR" = "$WORKSPACE_ROOT" ]; then
    echo "Longhorn workspace root not found" >&2
    exit 3
  fi
  WORKSPACE_ROOT=$PARENT_DIR
done
cd "$WORKSPACE_ROOT"


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

# jj-first: use jj diff when available and no explicit --repo was given.
# Subrepos under repo/ are always plain git; jj only manages the workspace root.
USE_JJ=false
if [ -z "$repo" ] && test -d .jj && command -v jj >/dev/null 2>&1; then
  USE_JJ=true
fi

# 1) Detect deleted test files
if [ "$USE_JJ" = true ]; then
  mapfile -t deleted_tests < <(jj diff --summary 2>/dev/null | grep '^D ' | cut -d' ' -f2- | grep -E '_test\.go$' || true)
else
  # git --name-status outputs tab-separated: D<TAB>path
  mapfile -t deleted_tests < <("${git_cmd[@]}" diff --name-status --diff-filter=D HEAD 2>/dev/null | cut -f2 | grep -E '_test\.go$' || true)
fi

if [ "${#deleted_tests[@]}" -gt 0 ]; then
  echo "Error: the following *_test.go files were deleted in git diff HEAD:" >&2
  for f in "${deleted_tests[@]}"; do
    echo "  - $f" >&2
  done
  exit 1
fi

# 2) Check deleted line counts for added/changed/modified files
declare -a too_many_deleted=()

# Iterate numstat lines: added\tdeleted\tpath
# jj diff --git produces a unified diff; parse it to extract per-file removed-line counts
if [ "$USE_JJ" = true ]; then
  # Parse unified diff from jj: count removed lines per file.
  # Check and reset happen at each '--- a/' header (when the previous file's count is complete).
  current_file=""
  deleted_count=0
  while IFS= read -r line; do
    case "$line" in
      "--- a/"*)
        # Flush previous file before starting the next one
        if [ -n "$current_file" ] && [ "$deleted_count" -gt 100 ]; then
          case "$current_file" in
            *_test.go) too_many_deleted+=("$current_file:$deleted_count") ;;
          esac
        fi
        current_file="${line#--- a/}"
        deleted_count=0
        ;;
      "-"*)
        # Count removed lines; '--- a/' is caught above so only real removals reach here
        case "$current_file" in
          *_test.go) deleted_count=$((deleted_count + 1)) ;;
        esac
        ;;
    esac
  done < <(jj diff --git 2>/dev/null || true)
  # Flush last file
  if [ -n "$current_file" ] && [ "$deleted_count" -gt 100 ]; then
    case "$current_file" in
      *_test.go) too_many_deleted+=("$current_file:$deleted_count") ;;
    esac
  fi
else
  while IFS=$'\t' read -r added deleted path; do
    case "$path" in
      *_test.go)
        if [[ "$deleted" =~ ^[0-9]+$ ]]; then
          if [ "$deleted" -gt 100 ]; then
            too_many_deleted+=("$path:$deleted")
          fi
        fi
        ;;
    esac
  done < <("${git_cmd[@]}" diff --numstat --diff-filter=ACM HEAD 2>/dev/null || true)
fi

if [ "${#too_many_deleted[@]}" -gt 0 ]; then
  echo "Error: the following *_test.go files have more than 100 deleted lines in git diff HEAD:" >&2
  for entry in "${too_many_deleted[@]}"; do
    IFS=':' read -r p c <<<"$entry"
    echo "  - $p : $c deleted lines" >&2
  done
  exit 1
fi

echo "OK: no deleted *_test.go files and no *_test.go with >100 deleted lines in diff"
exit 0
