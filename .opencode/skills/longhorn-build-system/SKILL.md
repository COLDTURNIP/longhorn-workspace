---
name: longhorn-build-system
description: >
  Use when asked how Make targets work in Longhorn repos, adding or debugging a
  build/test/validate/package task, checking Docker Buildx behavior, or deciding
  whether a repo still uses a legacy Dapper flow.
compatibility: opencode
metadata:
  applies-to: longhorn-manager, longhorn-engine, longhorn-instance-manager, longhorn-share-manager, backing-image-manager, longhorn-spdk-engine, cli, shared helper repos
  excludes: csi-* repos unless their own Makefile says otherwise
  version: "2.0"
---

# Longhorn Build System

## What I Do

- Explain the current Longhorn Make + Docker Buildx build model.
- Map common Make targets to Dockerfile stages and scripts.
- Keep legacy Dapper guidance scoped to repos that still declare `.dapper` and `Dockerfile.dapper`.
- Provide agent-safe verification rules for build, test, validate, CI, and package work.

## Core Rule

Use the repo Makefile as the authoritative build/test interface.

For current native Longhorn repos, Make usually runs Docker Buildx against
multi-stage Dockerfiles. Do not treat host `go build` or `go test` as final
verification. Quick host-side Go commands can be useful for iteration, but the
result that matters is the repo Make target.

## Current Native Pattern

Many native repos define explicit Make targets like this:

```makefile
build:
	docker buildx build --target build-artifacts --output type=local,dest=. -f Dockerfile .

validate:
	docker buildx build --target validate -f Dockerfile .

test:
	docker buildx build --target test-artifacts --output type=local,dest=. -f Dockerfile .

ci:
	docker buildx build --target ci-artifacts --output type=local,dest=. -f Dockerfile .

package:
	bash scripts/package

.DEFAULT_GOAL := ci
```

Some repos build a test image first and then run it with `docker run`, often
with privileged flags or host mounts for storage tests. Always read the local
Makefile before assuming a target is pure `docker buildx build`.

## Dockerfile Stages

Current native Dockerfiles usually define these stages:

| Stage | Purpose |
|-------|---------|
| `base` | Toolchain, system packages, vendored module flags, source copy |
| `build` | Runs `./scripts/build` |
| `validate` | Runs `./scripts/validate` |
| `test` | Runs `./scripts/test` when tests can run inside a build stage |
| `build-artifacts` | Copies built binaries to local output |
| `test-artifacts` | Copies coverage or test output to local output |
| `ci-artifacts` | Combines CI outputs such as binaries, validation markers, and coverage |

`GOFLAGS=-mod=vendor` is commonly set in the Dockerfile, not by the host shell.
The Dockerfile is the source of truth for Go version, OS packages, lint version,
build tags, and required native libraries.

## Quick Reference

| Command | Purpose | Notes |
|---------|---------|-------|
| `make` | Default CI target | Usually equivalent to `make ci` |
| `make build` | Build binaries | Usually writes `bin/` artifacts locally |
| `make test` | Run unit tests | May run inside Buildx or a privileged test container |
| `make validate` | Lint/static checks | Usually a Dockerfile `validate` stage |
| `make ci` | CI-equivalent artifact build | Usually writes artifacts locally |
| `make package` | Build/publish image artifacts | Usually delegates to `scripts/package` |
| `make generate` | Repo-specific generation | Common in `longhorn-manager`; inspect Makefile |

## Legacy Dapper Repos

Some shared/helper repos may still use the older dynamic script pattern:

```makefile
TARGETS := $(shell ls scripts)

.dapper:
	@echo Downloading dapper
	@curl -sL https://releases.rancher.com/dapper/latest/dapper-`uname -s`-`uname -m` > .dapper.tmp
	@chmod +x .dapper.tmp
	@./.dapper.tmp -v
	@mv .dapper.tmp .dapper

$(TARGETS): .dapper
	./.dapper $@
```

Treat Dapper as a repo-local legacy implementation detail, not the workspace
default. If a repo has both `.dapper` Makefile targets and `Dockerfile.dapper`,
follow that repo's Makefile and inspect `Dockerfile.dapper` for environment
variables such as `DAPPER_ENV`.

## Adding or Changing Build Tasks

For Buildx-native repos:

1. Read the existing Makefile and Dockerfile stages.
2. Add or adjust the script under `scripts/` only when the Dockerfile stage
   already calls it or will be updated to call it.
3. Add or update the Make target when the task must be invokable directly.
4. Keep artifacts explicit with `--output type=local,dest=.` when local files
   are expected.

For legacy Dapper repos, adding an executable file under `scripts/` may still
create a Make target automatically, but only rely on that when the Makefile uses
`TARGETS := $(shell ls scripts)`.

## Debugging Build Issues

1. Inspect `Makefile` to identify the exact command and target.
2. Inspect `Dockerfile` for the stage invoked by Make.
3. Inspect the called script under `scripts/`.
4. Reproduce with the same Make target before using host-side shortcuts.
5. If the target uses `docker run`, check required privileges and mounts such as
   `/dev`, `/proc`, `/sys`, `/tmp`, or bind propagation.

Common Buildx checks:

```bash
docker buildx version
docker buildx ls
make validate
make test
```

## Agent Verification Rules

- MUST use Make targets for final build/test/validate verification.
- SHOULD mention when verification was skipped because Docker, Buildx, network,
  or privileged mounts were unavailable.
- MAY use host `go test` for fast local debugging only when followed by Make.
- MUST inspect non-native repos, CSI sidecars, UI, and test repos before choosing
  commands; do not assume native Longhorn targets.

## References

- Repo Makefile: target names, Docker Buildx invocations, package commands.
- Repo Dockerfile: build environment and stage behavior.
- Repo scripts: implementation of build, test, validate, ci, package.
- `repo/AGENTS.md` and `AGENTS.d/build-contract.md`: workspace policy.
