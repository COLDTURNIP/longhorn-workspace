#!/usr/bin/env bash
#
# ascii_scanner.sh - compatibility wrapper for the former ascii-scanner
# interface. New callers should run ascii-checker.sh in this folder directly;
# see SKILL.md.
#
# Usage: ascii_scanner.sh [--execute|--dry-run] [--json-log] [--no-color]
#                         [--force] PATH...
# Without --execute, only prints what would be checked (the former default).
# Directories are expanded to the files below them, skipping .git.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
execute=false
paths=()
for arg in "$@"; do
	case "${arg}" in
	--execute) execute=true ;;
	--dry-run) execute=false ;;
	--json-log | --no-color | --force) ;;
	-h | --help)
		sed -n '3,10p' "${BASH_SOURCE[0]}" | cut -c3-
		exit 0
		;;
	*) paths+=("${arg#@}") ;;
	esac
done

if [[ ${#paths[@]} -eq 0 ]]; then
	echo "ascii_scanner.sh: target path required" >&2
	exit 2
fi

if [[ ${execute} == false ]]; then
	echo "[DRY-RUN] Would check: ${paths[*]} (pass --execute to run)"
	exit 0
fi

for path in "${paths[@]}"; do
	if [[ -d ${path} ]]; then
		find "${path}" -name .git -prune -o -type f -print
	elif [[ -e ${path} || -L ${path} ]]; then
		printf '%s\n' "${path}"
	else
		echo "ascii_scanner.sh: target path does not exist: ${path}" >&2
		exit 2
	fi
done | bash "${SCRIPT_DIR}/ascii-checker.sh" -f -
