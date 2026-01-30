---
name: longhorn-build-system
description: Explains how Longhorn repos auto-generate Make targets from scripts/ folder files via Dapper containers
compatibility: opencode
metadata:
  applies-to: longhorn-manager, longhorn-engine, longhorn-instance-manager
  excludes: csi-* repos
  version: "1.0"
---

# Longhorn Build System

## What I do

- Explain the convention where `scripts/` filenames automatically become Make targets
- Show how Dapper containers ensure reproducible builds across different machines
- Provide examples of adding new build tasks without editing Makefiles
- Document standard scripts: `build`, `test`, `validate`, `ci`, `package`

## When to use me

Use this skill when:

- You need to understand how `make build` or `make test` actually works
- You're adding a new build task and want to follow Longhorn conventions
- You're debugging build issues and need to understand the Dapper environment
- You're new to Longhorn and wonder why Makefiles are so simple

## How It Works

### The Makefile Convention

All Longhorn component repos use this standard Makefile pattern:

```makefile
PROJECT := longhorn-manager
TARGETS := $(shell ls scripts)

$(TARGETS): .dapper
	./.dapper $@

.DEFAULT_GOAL := ci
```

### What This Means

1. **Script Discovery**: `TARGETS := $(shell ls scripts)` dynamically discovers all files in the `scripts/` directory
2. **Target Generation**: Each script filename automatically becomes a Make target via the pattern rule `$(TARGETS):`
3. **Dapper Execution**: All targets are executed inside a Dapper containerized environment (`./.dapper $@`)
4. **Default Behavior**: Running `make` without arguments executes `make ci`

### Concrete Example

Given this `scripts/` directory structure:
```
longhorn-manager/scripts/
|-- build
|-- ci
|-- package
|-- test
+-- validate
```

You automatically get these Make targets:
```bash
make build      # Executes scripts/build in Dapper container
make ci         # Executes scripts/ci in Dapper container
make package    # Executes scripts/package in Dapper container
make test       # Executes scripts/test in Dapper container
make validate   # Executes scripts/validate in Dapper container
```

**No need to modify the Makefile** when adding new scripts - they're automatically available as targets.

---

## Special Cases

### 1. `make generate` (longhorn-manager only)

This is a **special target** defined separately in the Makefile:

```makefile
generate:
	bash k8s/generate_code.sh
```

**Purpose**: Generate Kubernetes CRDs from Go source code  
**Output**: `/longhorn-manager/k8s/crds.yaml` and generated clientsets  
**Note**: This is NOT a script in `scripts/` - it's explicitly defined in the Makefile

### 2. Workflow-specific targets

Some repos define additional targets for CI/CD workflows:

```makefile
workflow-image-build-push: buildx-machine
	MACHINE=$(MACHINE) PUSH='true' IMAGE_NAME=$(PROJECT) bash scripts/package
```

These are used by GitHub Actions but typically not invoked manually.

---

## Usage Guidelines

### Adding a New Build Task

To add a new build operation:

1. Create a shell script in `scripts/` directory:
   ```bash
   vim scripts/integration-test
   ```

2. Make it executable:
   ```bash
   chmod +x scripts/integration-test
   ```

3. Use the new target:
   ```bash
   make integration-test
   ```

**That's it!** No Makefile changes needed.

### Debugging Build Issues

If `make build` fails:

1. **Check if script exists**:
   ```bash
   ls -l scripts/build
   ```

2. **Run script directly** (outside Dapper for debugging):
   ```bash
   bash scripts/build
   ```

3. **Check Dapper logs** (run via Make):
   ```bash
   make build
   ```

4. **Inspect Dapper environment**:
   ```bash
   cat Dockerfile.dapper
   ```

### Common Script Patterns

Most scripts follow this structure:

```bash
#!/bin/bash
set -e  # Exit on error

cd "$(dirname "$0")/.."  # Change to repo root

# Script logic here
# Usually calls: go build, go test, golangci-lint, etc.
```

---

## Dapper Environment

### What is Dapper?

Dapper is a containerized build tool that ensures **reproducible builds** across different developer machines by running all build commands inside a Docker container.

### Environment Details

Each repo's `Dockerfile.dapper` defines:
- **Base image**: Usually `registry.suse.com/bci/golang:1.25`
- **Go version**: 1.24-1.25 (via toolchain)
- **Build tools**: golangci-lint, Docker CLI, buildx
- **Dependencies**: Uses vendored Go modules (`GOFLAGS=-mod=vendor`)

### How Scripts Access Dapper

The Makefile's `.dapper` target automatically downloads Dapper if missing:

```makefile
.dapper:
	@echo Downloading dapper
	@curl -sL https://releases.rancher.com/dapper/latest/dapper-`uname -s`-`uname -m` > .dapper.tmp
	@chmod +x .dapper.tmp
	@./.dapper.tmp -v
	@mv .dapper.tmp .dapper
```

### Discovering Available Environment Variables

Dapper uses the `DAPPER_ENV` directive in `Dockerfile.dapper` to define which
host environment variables are passed through into the container. To discover
what options a repo supports:

1. Open the repo's `Dockerfile.dapper`
2. Find the `ENV DAPPER_ENV=...` line
3. Variables listed there can be set on the host and will be available inside
   the Dapper container

Example from `longhorn-manager/Dockerfile.dapper`:
```dockerfile
ENV DAPPER_ENV="IMAGE REPO VERSION TAG TESTS DRONE_REPO DRONE_PULL_REQUEST DRONE_COMMIT_REF NO_PACKAGE ARCHS"
```

Common pass-through variables across Longhorn repos:

| Variable | Purpose | Supported Repos |
|----------|---------|-----------------|
| `TESTS` | Filter test cases (via `-check.f`) | longhorn-manager |
| `ARCHS` | Multi-arch build targets (e.g., `amd64 arm64`) | longhorn-manager, longhorn-share-manager, backing-image-manager |
| `SKIP_TASKS` | Skip specific CI stages | longhorn-engine, longhorn-instance-manager |
| `NO_PACKAGE` | Skip Docker image packaging | longhorn-manager |
| `TAG` / `REPO` / `IMAGE` | Image tagging and registry | Most repos |

**Note**: Each repo may support different variables. Always check
`Dockerfile.dapper` for the authoritative list.

---

## Standard Script Behavior

### `scripts/build`
- Builds binaries for current architecture (amd64/arm64)
- Outputs to `bin/` directory
- Uses `CGO_ENABLED=0` for static linking
- Adds version/commit metadata via `-ldflags`

### `scripts/test`
- Runs all Go tests with `-race` detector (amd64 only)
- Generates `coverage.out`
- Supports `TESTS` env var for filtering tests (longhorn-manager only):
  ```bash
  TESTS="TestVolumeLifeCycle" make test
  ```
- Other repos do not currently support test filtering via environment variables

### `scripts/validate`
- Runs `go vet` (static analysis)
- Runs `golangci-lint run --timeout=5m`
- Runs `go fmt` check (must produce no output)

### `scripts/ci`
- Typically chains: `build` -> `validate` -> `test`
- This is the default target (`make` = `make ci`)

### `scripts/package`
- Builds Docker images
- Supports multi-platform builds (buildx)
- Tags images based on branch/tag

---

## Quick Reference

| Command | Script Executed | Purpose |
|---------|----------------|---------|
| `make` | `scripts/ci` | Full CI: build + validate + test |
| `make build` | `scripts/build` | Build binaries |
| `make test` | `scripts/test` | Run tests |
| `make validate` | `scripts/validate` | Lint and format check |
| `make package` | `scripts/package` | Build Docker images |
| `make generate` | `k8s/generate_code.sh` | Generate CRDs (longhorn-manager only) |

---

## Key Takeaways

1. **Convention over configuration**: Script names = Make targets
2. **No Makefile edits needed**: Just add scripts to `scripts/`
3. **Dapper ensures consistency**: Same build environment for everyone
4. **Standard patterns**: All Longhorn repos follow this convention
5. **Special case**: `make generate` is explicitly defined (not a script)

---

## Guidelines for AI Agents

### MUST: Use `make test` for Verification

Final verification and CI-equivalent checks **MUST** use `make test` (or other
`make` targets) instead of running `go test` directly on the host.

**Rationale**: Running `go test` directly on the host may produce inconsistent
results due to environment differences, making troubleshooting unreliable
without a common baseline.

### Why Direct `go test` is Discouraged

The Dapper container provides a controlled environment that eliminates
variability from:

- **Go toolchain version**: Host may have different Go version than CI
- **System packages and libraries**: Some tests require specific native
  dependencies (e.g., SPDK libraries, iSCSI tools)
- **Privileged operations**: Tests may need access to `/dev`, `/sys`, loop
  devices, or hugepages
- **Docker availability**: Some test suites spin up helper containers (e.g.,
  NFS server for backupstore tests)
- **Build flags**: Dapper sets `GOFLAGS=-mod=vendor` and repo-specific tags
  (e.g., `-tags="test qcow"` in longhorn-engine)
- **Race detector and timeout**: Scripts enforce consistent `-race` (amd64) and
  `-timeout` settings

### SHOULD: Use `go test` Only for Quick Local Debugging

`go test` may be used for rapid local iteration during development, but:

- Never treat `go test` results as the authoritative outcome
- Always confirm with `make test` before considering a fix complete
- Be aware that passing `go test` locally does not guarantee CI will pass

### Troubleshooting Baseline

When investigating test failures:

1. **Reproduce inside Dapper first**: Use `make test` to confirm the failure
2. **Compare environments**: If `go test` passes locally but `make test` fails,
   the difference is likely environmental
3. **Check Dockerfile.dapper**: Review what system dependencies, mounts, or
   privileged access the test environment requires

---

## References

- See any component repo's `Makefile` for the actual implementation
- See `Dockerfile.dapper` for build environment specification
- Dapper documentation: https://github.com/rancher/dapper
