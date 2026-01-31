# Defensive Shell Prelude Snippet

Purpose: provide a reusable shell prelude for Oh-My-OpenCode skills that enforces defensive defaults (dry-run, structured logging, atomic writes, backups) and standardized exit codes.

The defensive prelude now lives as a reusable library file:

```
.opencode/skills/lib/defensive_prelude.sh
```

## Usage

In your shell-based skill:

```bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/defensive_prelude.sh"

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]
  --execute           Perform actions (default dry-run)
  --force             Permit destructive operations
  --json-log          Emit JSON log lines
  --no-color          Disable ANSI color codes
  -n, --dry-run       Explicitly enable dry-run (default)
  -h, --help          Show this help
USAGE
}

defensive_parse_args "$@"
set -- "${DEFENSIVE_POSITIONAL_ARGS[@]:-}"

defensive_require_clean_tree
defensive_require_upstream_head
defensive_record_safety_ref

info "Dry-run: $DRY_RUN"
info "Force: $FORCE"

# Script logic here
```

## Available Helpers

- `defensive_parse_args "$@"` → populates shared flags (`DRY_RUN`, `FORCE`, `JSON_LOG`, `NO_COLOR`) and `DEFENSIVE_POSITIONAL_ARGS`.
- `defensive_show_help` → prints `usage` if defined.
- `defensive_require_clean_tree` / `defensive_require_upstream_head` / `defensive_record_safety_ref` → guard rails for git state.
- `defensive_backup_file <path>` and `defensive_atomic_write <path>` → safe file updates.
- `defensive_run_cmd "command"` → logs and executes (or logs only in dry-run).
- `defensive_require_force "description"` → enforce `--force` for destructive steps.
- Shared `info`, `warn`, `error`, `die` functions with ISO timestamp logging; JSON logging via `--json-log`.

## Guidance

- Default to dry-run. Require `--execute` (and `--force` when appropriate) to mutate state.
- Keep scripts ASCII-only and avoid global git config changes.
- Use `.safety-ref` recording to provide rollback pointers.
- Preserve user feedback consistency by relying on the shared `usage` pattern and log helpers.
- **Logging standard**: all helper functions emit `[ISO8601] [LEVEL] message` lines; enable `--json-log` for machine consumption. `--no-color` should suppress ANSI sequences when scripts add their own coloring.
- **Exit codes**: success = `0`, argument error = `2`, environment/safety error = `3`. Scripts may extend but must document deviations.

## Example

```bash
./my-skill.sh --execute --force --json-log > run.log
```

For a full reference implementation, see `.opencode/skills/lib/defensive_prelude.sh` and the updated skills (repo-init, ticket-sanitizer, sync-crd-helm, interaction-mapper, support-bundle-analysis/extract-bundle, verify-setup).
