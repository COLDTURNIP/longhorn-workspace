#!/usr/bin/env bash

set -euo pipefail

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
    printf '%s\n' "Longhorn workspace root not found" >&2
    exit 3
  fi
  WORKSPACE_ROOT=$PARENT_DIR
done
cd "$WORKSPACE_ROOT"
source "$WORKSPACE_ROOT/scripts/lib/defensive_prelude.sh"
source "$WORKSPACE_ROOT/scripts/lib/python_runtime.sh"

usage() {
cat <<USAGE
Usage: $SCRIPT_NAME [options]

Run repo-init first, then run allowlisted indexers.

Options:
  --json              Emit final JSON summary to stdout only
  --execute           Perform actions (default)
  --force             Forward force context (wrapper keeps standard parsing)
  --json-log          Emit JSON log lines
  --no-color          Disable ANSI color output
  -n, --dry-run       Dry-run mode (validate and plan indexers only)
  -h, --help          Show this help
USAGE
}

JSON_STDOUT_FD=1
WRAPPER_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      ;;
    *)
      WRAPPER_ARGS+=("$1")
      ;;
  esac
  shift || true
done
set -- "${WRAPPER_ARGS[@]}"

defensive_parse_args "$@"

if [ "$JSON_OUTPUT" = true ]; then
  JSON_LOG=true
  exec 3>&1
  exec 1>&2
  JSON_STDOUT_FD=3
fi

if [ "${#DEFENSIVE_POSITIONAL_ARGS[@]}" -gt 0 ]; then
  error "init-workspace does not accept positional arguments"
  defensive_show_help
  exit "$EXIT_ARG"
fi

MODE="execute"
if [ "$DRY_RUN" = true ]; then
  MODE="dry-run"
fi

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [ "$DRY_RUN" = true ]; then
  EVIDENCE_DIR="/tmp/init-workspace.${TIMESTAMP}"
else
  EVIDENCE_DIR=".opencode/tmp/init-workspace/${TIMESTAMP}"
fi
LOG_DIR="${EVIDENCE_DIR}/logs"
REPO_JSON_FILE="${EVIDENCE_DIR}/repo-init.json"
INDEXERS_JSON_FILE="${EVIDENCE_DIR}/indexers.json"
SUMMARY_JSON_FILE="${EVIDENCE_DIR}/summary.json"
INDEXERS_NDJSON_FILE="${EVIDENCE_DIR}/indexers.ndjson"
MANIFEST_SORTED_FILE="${EVIDENCE_DIR}/indexers.sorted.ndjson"
EMBEDDED_MANIFEST_FILE="${EVIDENCE_DIR}/indexers.manifest.json"
KEEP_EVIDENCE_RUNS=5

report_failure_evidence() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "${EVIDENCE_DIR:-}" ]; then
    warn "Execution failed with rc=${rc}. Evidence directory: ${EVIDENCE_DIR}"
    warn "Please check execution records under ${EVIDENCE_DIR}/"
  fi
  return "$rc"
}

trap report_failure_evidence EXIT

if ! resolve_python_command; then
  die "Unable to resolve Python runtime"
fi

mkdir -p "$LOG_DIR"

REPO_INIT_SCRIPT="scripts/repo-init.sh"

if [ ! -f "$REPO_INIT_SCRIPT" ]; then
  die "Missing required script: $REPO_INIT_SCRIPT"
fi

write_embedded_manifest() {
  cat > "$EMBEDDED_MANIFEST_FILE" <<'JSON'
{
  "version": 1,
  "indexers": [
    {
      "name": "interaction-mapper",
      "script": "agent-skills/interaction-mapper/map_interactions.sh",
      "execute_args": ["--execute", "--force"],
      "dry_run_args": ["--dry-run"],
      "outputs": [
        "context/indices/crd-interaction.json",
        "context/indices/rpc-topology.json"
      ],
      "requires_paths": [
        "repo/longhorn-manager",
        "repo/types"
      ]
    }
  ]
}
JSON

  if ! python_cmd - "$EMBEDDED_MANIFEST_FILE" >/dev/null <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    json.load(f)
PY
  then
    die "Invalid embedded indexers manifest"
  fi
}

prune_evidence_glob() {
  local pattern=$1
  local keep_count=$2
  local keep_path=${3:-}

  python_cmd - "$pattern" "$keep_count" "$keep_path" <<'PY'
import glob
import os
import shutil
import sys

pattern = sys.argv[1]
keep_count = int(sys.argv[2])
keep_path = os.path.abspath(sys.argv[3]) if sys.argv[3] else ""

paths = [p for p in glob.glob(pattern) if os.path.isdir(p)]
if not paths:
    raise SystemExit(0)

paths = [os.path.abspath(p) for p in paths]
paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)

if keep_path and keep_path in paths:
    paths.remove(keep_path)
    paths.insert(0, keep_path)

for stale in paths[keep_count:]:
    shutil.rmtree(stale, ignore_errors=True)
PY
}

write_embedded_manifest
prune_evidence_glob "/tmp/init-workspace.*" "$KEEP_EVIDENCE_RUNS" "$EVIDENCE_DIR"
prune_evidence_glob ".opencode/tmp/init-workspace/*" "$KEEP_EVIDENCE_RUNS" "$EVIDENCE_DIR"

run_repo_init() {
  local repo_log_file repo_rc
  local -a repo_cmd

  repo_log_file="${LOG_DIR}/repo-init.log"
  repo_cmd=(bash "$REPO_INIT_SCRIPT" --json)
  if [ "$DRY_RUN" = true ]; then
    repo_cmd+=(--dry-run)
  else
    repo_cmd+=(--execute)
  fi

  info "Running repo-init stage"
  set +e
  "${repo_cmd[@]}" >"$REPO_JSON_FILE" 2>"$repo_log_file"
  repo_rc=$?
  set -e

  if [ ! -s "$REPO_JSON_FILE" ]; then
    printf '{"summary":{"success":0,"skipped":0,"dry_run":0,"failed":0},"results":[],"wait_failures":0}\n' > "$REPO_JSON_FILE"
  fi

  if ! python_cmd - "$REPO_JSON_FILE" >/dev/null <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    json.load(f)
PY
  then
    error "repo-init did not return valid JSON"
    return "$EXIT_ENV"
  fi

  return "$repo_rc"
}

append_indexer_result() {
  local name=$1
  local script=$2
  local mode=$3
  local rc=$4
  local status=$5
  local message=$6
  local outputs_json=$7
  local log_path=$8

  python_cmd - "$INDEXERS_NDJSON_FILE" "$name" "$script" "$mode" "$rc" "$status" "$message" "$outputs_json" "$log_path" <<'PY'
import json
import sys
target = sys.argv[1]
obj = {
    "name": sys.argv[2],
    "script": sys.argv[3],
    "mode": sys.argv[4],
    "rc": int(sys.argv[5]),
    "status": sys.argv[6],
    "outputs": json.loads(sys.argv[8]),
}
message = sys.argv[7]
log_path = sys.argv[9]
if message:
    obj["message"] = message
if log_path:
    obj["log_path"] = log_path
with open(target, "a", encoding="utf-8") as f:
    f.write(json.dumps(obj, separators=(",", ":")) + "\n")
PY
}

build_outputs_json() {
  local outputs_raw=$1
  python_cmd - "$outputs_raw" <<'PY'
import json
import os
import sys
outputs = json.loads(sys.argv[1])
items = []
for path in outputs:
    items.append({"path": path, "present": os.path.exists(path)})
print(json.dumps(items, separators=(",", ":")))
PY
}

validate_requires_paths() {
  local requires_raw=$1
  python_cmd - "$requires_raw" <<'PY'
import json
import os
import sys
missing = [p for p in json.loads(sys.argv[1]) if not os.path.exists(p)]
if missing:
    print("missing:" + ",".join(missing))
    sys.exit(1)
print("ok")
PY
}

run_indexers() {
  : > "$INDEXERS_NDJSON_FILE"

  python_cmd - "$EMBEDDED_MANIFEST_FILE" > "$MANIFEST_SORTED_FILE" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
indexers = data.get("indexers", [])
indexers = sorted(indexers, key=lambda x: x.get("name", ""))
for entry in indexers:
    print(json.dumps(entry, separators=(",", ":")))
PY

  while IFS= read -r entry_json || [ -n "$entry_json" ]; do
    [ -z "$entry_json" ] && continue

    local name script execute_args_json outputs_json_declared requires_paths_json log_file outputs_json status rc message
    local -a cmd args

    name=$(python_cmd - "$entry_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("name", ""))
PY
)
    script=$(python_cmd - "$entry_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("script", ""))
PY
)
    execute_args_json=$(python_cmd - "$entry_json" <<'PY'
import json
import sys
print(json.dumps(json.loads(sys.argv[1]).get("execute_args", []), separators=(",", ":")))
PY
)
    outputs_json_declared=$(python_cmd - "$entry_json" <<'PY'
import json
import sys
print(json.dumps(json.loads(sys.argv[1]).get("outputs", []), separators=(",", ":")))
PY
)
    requires_paths_json=$(python_cmd - "$entry_json" <<'PY'
import json
import sys
print(json.dumps(json.loads(sys.argv[1]).get("requires_paths", []), separators=(",", ":")))
PY
)

    if [[ "$script" != agent-skills/* ]]; then
      warn "Indexer $name rejected: script outside allowlist prefix"
      outputs_json=$(build_outputs_json "$outputs_json_declared")
      append_indexer_result "$name" "$script" "$MODE" 3 "failed" "script outside agent-skills/" "$outputs_json" ""
      continue
    fi
    if [ ! -f "$script" ]; then
      warn "Indexer $name rejected: script missing"
      outputs_json=$(build_outputs_json "$outputs_json_declared")
      append_indexer_result "$name" "$script" "$MODE" 3 "failed" "script missing" "$outputs_json" ""
      continue
    fi
    if [ -L "$script" ]; then
      warn "Indexer $name rejected: symlink is not allowed"
      outputs_json=$(build_outputs_json "$outputs_json_declared")
      append_indexer_result "$name" "$script" "$MODE" 3 "failed" "script is symlink" "$outputs_json" ""
      continue
    fi
    set +e
    require_result=$(validate_requires_paths "$requires_paths_json")
    require_rc=$?
    set -e
    if [ "$require_rc" -ne 0 ]; then
      warn "Indexer $name skipped: ${require_result}"
      outputs_json=$(build_outputs_json "$outputs_json_declared")
      append_indexer_result "$name" "$script" "$MODE" 0 "skipped" "$require_result" "$outputs_json" ""
      continue
    fi

    if [ "$DRY_RUN" = true ]; then
      info "[DRY-RUN] would run: bash $script $(python_cmd - "$execute_args_json" <<'PY'
import json
import sys
print(" ".join(json.loads(sys.argv[1])))
PY
)"
      outputs_json=$(build_outputs_json "$outputs_json_declared")
      append_indexer_result "$name" "$script" "$MODE" 0 "skipped" "dry-run planned only" "$outputs_json" ""
      continue
    fi

    log_file="${LOG_DIR}/indexer-${name}.log"
    cmd=(bash "$script")
    mapfile -t args < <(python_cmd - "$execute_args_json" <<'PY'
import json
import sys
for item in json.loads(sys.argv[1]):
    print(item)
PY
)
    cmd+=("${args[@]}")

    info "Running indexer: $name"
    set +e
    "${cmd[@]}" >"$log_file" 2>&1
    rc=$?
    set -e

    outputs_json=$(build_outputs_json "$outputs_json_declared")
    if [ "$rc" -eq 0 ]; then
      status="success"
      message="completed"
      info "Indexer $name completed"
    else
      status="failed"
      message="indexer execution failed"
      warn "Indexer $name failed with rc=$rc"
    fi
    append_indexer_result "$name" "$script" "$MODE" "$rc" "$status" "$message" "$outputs_json" "$log_file"
  done < "$MANIFEST_SORTED_FILE"

  python_cmd - "$INDEXERS_NDJSON_FILE" > "$INDEXERS_JSON_FILE" <<'PY'
import json
import sys
items = []
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            items.append(json.loads(line))
print(json.dumps(items, separators=(",", ":")))
PY
}

write_summary_json() {
  local repo_rc=$1
  python_cmd - "$MODE" "$repo_rc" "$REPO_JSON_FILE" "$INDEXERS_JSON_FILE" > "$SUMMARY_JSON_FILE" <<'PY'
import json
import sys

mode = sys.argv[1]
repo_rc = int(sys.argv[2])
repo_path = sys.argv[3]
indexers_path = sys.argv[4]

with open(repo_path, "r", encoding="utf-8") as f:
    repo = json.load(f)
with open(indexers_path, "r", encoding="utf-8") as f:
    indexers = json.load(f)

failed_names = [i.get("name", "") for i in indexers if i.get("status") == "failed"]
warnings = {
    "indexers_failed": len(failed_names),
    "indexers_failed_names": failed_names,
}

if repo_rc != 0:
    overall = {"rc": 3, "status": "failed"}
else:
    if failed_names:
        overall = {"rc": 0, "status": "success_with_warnings"}
    else:
        overall = {"rc": 0, "status": "success"}

doc = {
    "mode": mode,
    "repo_init": {
        "rc": repo_rc,
        "summary": repo.get("summary", {"success": 0, "skipped": 0, "dry_run": 0, "failed": 0}),
        "results": repo.get("results", []),
        "wait_failures": repo.get("wait_failures", 0),
    },
    "indexers": indexers,
    "warnings": warnings,
    "overall": overall,
}
print(json.dumps(doc, separators=(",", ":")))
PY
}

print_human_summary() {
  python_cmd - "$SUMMARY_JSON_FILE" "$EVIDENCE_DIR" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    doc = json.load(f)
evidence = sys.argv[2]

repo = doc.get("repo_init", {})
repo_summary = repo.get("summary", {})
results = repo.get("results", [])
created = [r.get("repo", "") for r in results if r.get("status") == "success"]
skipped = [r.get("repo", "") for r in results if r.get("status") == "skipped"]
planned = [r.get("repo", "") for r in results if r.get("status") == "dry-run"]
failed = [r.get("repo", "") for r in results if r.get("status") == "failed"]
indexers = doc.get("indexers", [])

print("=== init-workspace summary ===")
print(f"mode: {doc.get('mode', 'unknown')}")
print(f"repo-init: {'ok' if repo.get('rc', 1) == 0 else 'failed'}")
print(
    "repos: counts success={0} skipped={1} dry-run={2} failed={3}".format(
        repo_summary.get("success", 0),
        repo_summary.get("skipped", 0),
        repo_summary.get("dry_run", 0),
        repo_summary.get("failed", 0),
    )
)
print("repos: created=" + (" ".join(created) if created else "-"))
print("repos: skipped=" + (" ".join(skipped) if skipped else "-"))
print("repos: planned=" + (" ".join(planned) if planned else "-"))
print("repos: failed=" + (" ".join(failed) if failed else "-"))

success_count = sum(1 for i in indexers if i.get("status") == "success")
failed_count = sum(1 for i in indexers if i.get("status") == "failed")
skipped_count = sum(1 for i in indexers if i.get("status") == "skipped")
print(
    f"indexers: totals total={len(indexers)} success={success_count} failed={failed_count} skipped={skipped_count}"
)
for idx in indexers:
    outputs = idx.get("outputs", [])
    present = sum(1 for o in outputs if o.get("present"))
    line = f"indexer: {idx.get('name','')} status={idx.get('status','')} rc={idx.get('rc',0)} outputs_present={present}/{len(outputs)}"
    if idx.get("log_path"):
        line += f" log={idx.get('log_path')}"
    if idx.get("message"):
        line += f" message={idx.get('message')}"
    print(line)

warnings = doc.get("warnings", {})
warn_count = warnings.get("indexers_failed", 0)
warn_names = warnings.get("indexers_failed_names", [])
if warn_count > 0:
    print("warnings: indexers_failed={0} ({1})".format(warn_count, " ".join(warn_names)))
else:
    print("warnings: none")
print(f"overall: {doc.get('overall', {}).get('status', 'unknown')}")
print(f"evidence_dir: {evidence}")
PY
}

emit_json_summary() {
  python_cmd - "$SUMMARY_JSON_FILE" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    doc = json.load(f)
print(json.dumps(doc, separators=(",", ":")))
PY
}

set +e
run_repo_init
REPO_INIT_RC=$?
set -e

if [ "$REPO_INIT_RC" -ne 0 ]; then
  warn "repo-init failed; skipping all indexers"
  printf '[]\n' > "$INDEXERS_JSON_FILE"
  write_summary_json "$REPO_INIT_RC"
  if [ "$JSON_OUTPUT" = true ]; then
    emit_json_summary >&"$JSON_STDOUT_FD"
  else
    print_human_summary
  fi
  exit "$EXIT_ENV"
fi

run_indexers
write_summary_json "$REPO_INIT_RC"

if [ "$JSON_OUTPUT" = true ]; then
  emit_json_summary >&"$JSON_STDOUT_FD"
else
  print_human_summary
fi

exit 0
