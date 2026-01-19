# Repository Management & Engineering Guide

**Scope:** All Git repositories located under the @repo/ prefix.
**Context:** This guide extends the global @AGENTS.md and focuses on the technical structure, dependencies, and build requirements of the Longhorn multi-repo codebase.

## Repository Categories & Ownership

Repositories are categorized to determine the level of permitted modification and the required build toolchain.

### Team-Owned Native Longhorn Component Repos (Allowlist)

These are core components actively developed by the team. They follow the Dapper + scripts/ pattern.

- `backing-image-manager/`
- `cli/`
- `longhorn-engine/`
- `longhorn-instance-manager/`
- `longhorn-manager/`
- `longhorn-share-manager/`
- `longhorn-spdk-engine/` - part of Longhorn V2 engine
- `longhorn-ui/` - Frontend (Node.js toolchain, not Go/Dapper).

**Policy:** Full feature work and refactoring permitted.

### Shared Libraries / Helpers (High-Impact Allowlist)

High-impact dependencies. Changes here require coordinated validation across dependent components.

- `types/`
- `go-common-libs/`
- `backupstore/`
- `go-iscsi-helper/`
- `go-spdk-helper/`
- `sparse-tools/`

**Policy:** Significant caution required. Verify downstream impacts in the dependency hierarchy.

### Upstream CSI Sidecar Repos (NOT Owned by This Team)

These repositories are upstream kubernetes-csi sidecar clones. They are included to build/publish container images consumed by the Longhorn Helm chart as CSI driver dependencies.

**Repos:**

- `csi-attacher/`
- `csi-node-driver-registrar/`
- `csi-provisioner/`
- `csi-resizer/`
- `csi-snapshotter/`
- `livenessprobe/`

**Policy:** **Minimal Patching Only**. No refactoring or mechanical formatting. Use repo-specific Makefiles, not Dapper scripts.

### Integration / Packaging Repos

- `longhorn/` - Helm chart, deployment manifests, and design documents. See "CRD Generation and Helm Chart Workflow" section for operational steps.
- `longhorn-tests/` - E2E tests (Python-based, not Go/Dapper).

### Version Coordination

- `dep-versions/` - Central version coordination for external dependencies and CSI sidecars.
- `versions.json` - Version source of truth for external libs and sidecars.
- `version` - Current workspace version.

### Documents

- `website`

### Dependency Hierarchy (Simplified)

Changes in lower layers require validation in higher layers:

```
Foundation:    types/
                 |
               v
Utilities:     go-common-libs/
                 |
      +----------+----------+
      v          v          v
Helpers:   backupstore/  go-iscsi-helper/  go-spdk-helper/  sparse-tools/
                 |
      +----------+----------+
      v          v          v
Components: longhorn-engine/  longhorn-spdk-engine/
                 |
               v
Orchestration: longhorn-instance-manager/
                 |
               v
Operator:      longhorn-manager/
                 |
               v
Packaging:     longhorn/ (Helm chart + manifests)
```

## Build Systems

**Dapper-based Repos (Native)**

If a scripts/ directory exists, use the following entry points:

- `make validate`: Runs linters and static analysis.
- `make test:` Runs unit tests.
- `make build:` Compiles binaries.

Standard Makefile Repos (Upstream)

Does not use `scripts/`. Follow each repo's specific Makefile or release-tools documentation.

## Git Workflow & Safety

### Default Branch Detection

Branches may be named master or main. Always detect dynamically:

```bash
git symbolic-ref refs/remotes/upstream/HEAD | sed 's@^refs/remotes/upstream/@@'
```

### Branch Naming

Must follow the @ticket/ specification: `${ticket_id}-${brief_description}`. Example: `10105-fix_volume_attach`.

### Prohibited Git Actions

- **NO** force-pushing to shared branches.
- **NO** direct pushes to the upstream remote.
- **NO** commit signing (handled by the human user).

## Dependency Hygiene (Go Modules)

- Local Replaces: replace directives pointing to other @repo/ paths are allowed only during local development.
- Pre-submission Check: Before a PR is opened, agents MUST:
    1. Remove all local replace directives.
    2. Run go mod tidy to ensure go.mod and go.sum are clean.

## ASCII-Only Enforcement

As per the global workspace policy, every file within @repo/ MUST consist only of ASCII characters (0x00-0x7F).

- **Incremental Validation**: To optimize Token usage and execution time, Agents MUST ONLY run the ascii-scanner skill on **modified or staged files** before committing.
- **Trigger:** Run skill .opencode/skill/ascii-scanner after any code change, document writing, or report generation.
- **Fixes:** Replace any Unicode symbols, smart quotes, or emojis with ASCII equivalents.

## Special Workflows

### CRD & Helm Chart Synchronization
- **Trigger**: Any change to API definitions in `longhorn-manager/pkg/apis/`.
- **Requirement**: Updates MUST be propagated to the `longhorn/` (packaging) repo.
- **Action**: DO NOT perform manual copying. Use `sync-crd-helm` skill to ensure consistency.
