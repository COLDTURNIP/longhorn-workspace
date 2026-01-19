# Repository Engineering and Architecture Guide

**Context**: This guide is a specialized extension of the workspace root "AGENTS.md".
**Inheritance**: All global policies (Git Workflow, ASCII-Only, Ghost Files) defined in the root "AGENTS.md" apply strictly to this directory.
**Focus**: Component categorization, Dapper build toolchains, and dependency impact analysis.

---

## 1. Repository Categorization and Policy

You MUST identify the repository type before modifying code to determine the allowed scope of changes.

* **Type A: Team-Owned Native Components (Allowlist)**
    * *Policy*: Full Refactoring and Feature Work Allowed.
    * *Build System*: Dapper (Containerized).
    * *Repositories*:
        - longhorn-manager (Orchestration and API)
        - longhorn-engine (Storage Engine Controller)
        - longhorn-instance-manager (Process Lifecycle)
        - longhorn-share-manager (NFS/vChents)
        - backing-image-manager
        - longhorn-spdk-engine (V2 Engine)
        - cli

* **Type B: Shared Libraries (High-Impact)**
    * *Policy*: High Caution. Changes here propagate to almost all other components.
    * *Requirement*: You MUST analyze downstream impacts in "go.mod" of dependent repos.
    * *Repositories*:
        - types (CRDs and API definitions)
        - go-common-libs (Utilities)
        - backupstore, go-iscsi-helper, go-spdk-helper, sparse-tools

* **Type C: Upstream CSI Sidecars (Vendor-Like)**
    * *Policy*: Minimal Patching ONLY.
        - PROHIBITED: Refactoring.
        - PROHIBITED: Mechanical Formatting or Linting sweeps.
        - ALLOWED: Only fix build issues or apply specific security patches.
    * *Repositories*:
        - csi-attacher, csi-provisioner, csi-resizer, csi-snapshotter, csi-node-driver-registrar
        - livenessprobe

---

## 2. The Build Contract (CRITICAL)

* **Native Longhorn Components (Type A and B)**
    * *Constraint*: NEVER run "go build" or "go test" directly on the host. These repos rely on "scripts/" wrapping Dapper.
    * *Command: Build*
        - Use: `make`
        - Action: Compiles binaries inside Dapper container.
    * *Command: Test*
        - Use: `make test`
        - Action: Runs unit tests inside Dapper.
    * *Command: Validate*
        - Use: `make validate`
        - Action: Runs linting and static analysis.
    * *Command: Clean*
        - Use: `make clean`
        - Action: Removes artifacts.

* **Upstream and Others (Type C and Integration)**
    * *Constraint*: Do not assume "scripts/" exists.
    * *CSI Sidecars*:
        - Action: Check "Makefile" or "release-tools/". Follow upstream conventions.
    * *UI (longhorn-ui)*:
        - Action: Use Node.js toolchain (`npm install && npm run build`).
    * *Tests (longhorn-tests)*:
        - Action: Use Python toolchain.

---

## 3. Dependency Hierarchy (Impact Map)

Use this hierarchy to plan your changes. Modifications in lower layers REQUIRE updates in upper layers.

* **Layer 1: Foundation (Lowest Level)**
    * *Repos*: types, go-common-libs
    * *Impact*: Affects Helpers, Core Engine, and Orchestration.

* **Layer 2: Helpers**
    * *Repos*: backupstore, go-iscsi-helper, go-spdk-helper, sparse-tools
    * *Impact*: Affects Core Engine.

* **Layer 3: Core Engine**
    * *Repos*: longhorn-engine, longhorn-spdk-engine
    * *Impact*: Affects Orchestration (Instance Manager).

* **Layer 4: Orchestration (Highest Level)**
    * *Repos*: longhorn-instance-manager -> longhorn-manager -> longhorn-share-manager
    * *Impact*: Affects End User functionality.

* **Impact Example**:
    - If you modify "repo/types" (Layer 1)...
    - You MUST expect and plan for "go.mod" updates in "repo/longhorn-manager" and "repo/longhorn-engine".

---

## 4. Special Engineering Workflows

* **CRD and Helm Synchronization**
    * *Trigger*: Changes to "repo/longhorn-manager/pkg/apis/..."
    * *Action*: You MUST sync these changes to "repo/longhorn/" (the Helm chart repo).
    * *Tool*: Use the "sync-crd-helm" skill if available, or request user guidance for manifest generation.

* **Version Coordination**
    * *Source of Truth*: "repo/dep-versions/versions.json"
    * *Usage*: When upgrading CSI sidecars or external dependencies, update this file to ensure CI consistency.
