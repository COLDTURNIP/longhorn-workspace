---
name: verify-setup
description: >
  Use after workspace initialization, before starting development work, or when the
  Go toolchain, Docker daemon, Docker Buildx, make, or git remotes are suspected to be misconfigured.
  Also use as a plan-gate check before executing a multi-step implementation plan.
---

# Skill: verify-setup

## Purpose

This skill validates a Longhorn developer workspace after initialization. It checks toolchain readiness (Go version, Docker daemon, Docker Buildx, make availability), git remote configuration, and workspace hygiene before development begins.

## Usage

```bash
bash agent-skills/verify-setup/verify_setup.sh [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--execute` | Run checks and perform commands (default) |
| `--dry-run` | Describe planned checks without executing |
| `--json-log` | Emit JSON log entries (useful for automation) |
| `--no-color` | Disable ANSI colors |
| `--force` | Reserved (no effect; included for interface consistency) |
| `--plan-mode` | Verify plan gate prerequisites |
| `-h`, `--help` | Show help message |

## Checks Performed

- **Plan-mode prerequisites**
  - When `--plan-mode` is specified, verifies plan gate prerequisites: checks for required plan contract documentation and scripts, and validates boulder state if present. Fails if any required plan-mode file is missing or invalid.

1. **Go toolchain**
   - Verifies `go` binary exists and prints version (expects Go >= 1.21; configurable via env `MIN_GO_VERSION`).
2. **Docker daemon**
   - Runs `docker info` to ensure Docker daemon is reachable.
3. **Make/Docker Buildx**
   - Verifies `make` is available and `docker buildx version` works. Current native Longhorn repos use Make targets backed by Docker Buildx and Dockerfile stages.
4. **Git remotes**
   - Warns (instead of failing) if `upstream` remote or its HEAD reference is missing, so the script can run in freshly cloned workspaces.
   - Warns if `origin` remote is missing (since PRs normally push to `origin`).
5. **Workspace cleanliness**
   - Fails if the workspace has uncommitted changes (`git status --porcelain`), unless `SKIP_CLEAN_CHECK=true` is set.
6. **Optional PATH sanity**
   - Warns if `$GOPATH/bin` is not in PATH when Go is installed.

## Output

- Logs are emitted via the shared defensive prelude (ISO timestamps, optional JSON).
- Exit codes: `0` success, `2` argument errors, `3` environment/tooling issues.
- On failure, the script prints remediation guidance (e.g., instructions to install Docker or configure `upstream`).

## Example

```bash
# Standard run (default is execute)
bash agent-skills/verify-setup/verify_setup.sh

# Dry-run preview
bash agent-skills/verify-setup/verify_setup.sh --dry-run

# JSON logs for automation
bash agent-skills/verify-setup/verify_setup.sh --json-log > verify.log
```

## Notes

- Requires the shared `scripts/lib/defensive_prelude.sh`.
- Does not modify any files unless future enhancements require caching.
- Intended to run before major plan execution (e.g., immediately after `repo-init`).
