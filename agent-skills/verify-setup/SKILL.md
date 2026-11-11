---
name: verify-setup
description: >
  Use after workspace initialization or before development when workspace Git,
  remotes, or working-tree state may need checking. Use --build when Go, Docker,
  Docker Buildx, or make readiness is needed.
---

# Skill: verify-setup

## Purpose

This skill checks the Longhorn workspace before development. The default run
checks Git/remotes and working-tree state. Use `--build` to add Go, Docker,
Docker Buildx, and make checks.

## Usage

```bash
bash agent-skills/verify-setup/verify_setup.sh [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--execute` | Execute selected checks (default) |
| `--build` | Add Go, Docker, Docker Buildx, and make checks |
| `--dry-run`, `-n` | Preview selected checks without executing commands |
| `--json-log` | Emit JSON log entries for automation |
| `--no-color` | Disable ANSI color output |
| `--force` | Reserved; has no effect |
| `-h`, `--help` | Show help |

The script resolves the workspace root from its source path, so it can be
invoked from any current directory.

## Checks Performed

### Default workspace checks

- **Git remotes**: Require a Git workspace. Warn when `upstream`, its remote
  HEAD, or `origin` is unavailable; these warnings do not fail the check.
- **Working-tree state**: Report a clean tree, or warn when Git or jj reports
  changes. Existing work is preserved and the check remains successful. A
  failed Git or jj state inspection is an environment error (exit 3).

### Optional build checks

With `--build`, the script:

- Verifies that the `go` binary exists and prints its reported version. It does
  not enforce a minimum Go version.
- Verifies that the Docker daemon is reachable with `docker info`.
- Verifies `make` and Docker Buildx availability.
- Warns when `$GOPATH/bin` is not in `PATH` if Go is installed.

### Dry-run

`--dry-run` only describes the selected checks and exits successfully. It does
not run Git, Go, Docker, Buildx, or make checks.

## Output and exit codes

Logs use the shared defensive prelude and support ISO timestamps and JSON
output. Exit codes are:

- `0`: checks completed or a dry-run preview was shown
- `2`: invalid option or positional argument
- `3`: required workspace or build prerequisite is unavailable

## Examples

```bash
# Default workspace checks
bash agent-skills/verify-setup/verify_setup.sh

# Workspace checks plus build prerequisites
bash agent-skills/verify-setup/verify_setup.sh --build

# Preview without executing any checks
bash agent-skills/verify-setup/verify_setup.sh --dry-run --build
```

The script is read-only and does not modify workspace files.
