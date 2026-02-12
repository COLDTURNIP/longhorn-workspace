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
        - Use: `make build`
        - Action: Compiles binaries inside Dapper container.
    * *Command: Test*
        - Use: `make test`
        - Action: Runs unit tests inside Dapper.
    * *Command: Validate*
        - Use: `make validate`
        - Action: Runs linting and static analysis.
    * *Command: Package*
        - Use: `make package`
        - Action: Package binaries into a container image.
    * *Command: CI*
        - Use: `make`
        - Action: Build, validate, test, and package.

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

---

## 5. PR Preparation and Submission Workflow

This repository defines a concise, defensive workflow for preparing pull requests. Follow these steps for every contribution to ensure a clean history, proper attribution, and safe interaction with upstream and origin remotes.

* **Coding Convention**: Follow the Longhorn coding style guide: https://github.com/longhorn/longhorn/wiki/Coding-Convention

1. Verify a clean working tree

```sh
# Ensure no uncommitted changes or staged files
git status --porcelain
# Expect no output for a clean tree
```

2. Fetch upstream and determine default branch

```sh
# Fetch remote refs
git fetch upstream

# Detect upstream default branch (main or master)
git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@'
```

Failure mode: if the upstream/HEAD symbolic ref is missing or the command fails, stop and resolve remotes before proceeding. Do not attempt to guess the default branch; ask a maintainer or inspect upstream remote manually.

3. Create an optional safety backup branch (recommended)

```sh
# Create a local backup branch from current HEAD before rebasing
git branch backup/$(date +%Y%m%d%H%M%S)
```

4. Rebase onto upstream default

```sh
# Example: rebase onto upstream/main (use the detected branch name)
git rebase upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')
```

Conflict preference: when resolving conflicts prefer upstream changes by default unless your change intentionally overrides upstream logic. Resolve conflicts, then continue the rebase with `git rebase --continue`.

5. Squash commits and sign-off (repo-scoped exception)

This repository requires a single commit with a Developer Certificate of Origin sign-off. This is a scoped exception to the root AGENTS policy that otherwise forbids agent signoff automation. Add a single commit using an interactive rebase or squash strategy, then commit with signoff:

```sh
# Squash to a single commit (example using interactive rebase)
git rebase -i upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')

# Create the commit and add a sign-off
git commit -s -m "<storyid>-brief: <one-line summary>\n\nDetailed description..."
```

6. Push to origin only

Push your feature branch to your personal fork (origin). Do not push to upstream.

```sh
git push -u origin HEAD
```

If the remote rejects the push because the remote branch has diverged and you must update the remote branch, use a force-with-lease option only after explicit review and consent. By default, force pushes are forbidden.

```sh
# Allowed only when explicitly approved: safer force push
git push --force-with-lease origin HEAD
```

Checklist before creating the PR

- [ ] Working tree is clean (no uncommitted changes)
- [ ] `git fetch upstream` completed successfully
- [ ] Upstream default branch detected via:
  - `git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@'`
- [ ] Optional backup branch created
- [ ] Branch rebased onto upstream default and conflicts resolved
- [ ] Commits squashed into a single commit
- [ ] Commit created with `git commit -s` (repo-specific exception)
- [ ] Pushed to `origin` (no push to `upstream`)
- [ ] If force push required, used `--force-with-lease` with explicit approval

Notes

- This section explicitly permits using `git commit -s` as a repository-scoped exception to the global agent guidance that normally forbids automated sign-off. Use sign-off to certify contribution origin when creating the PR.
- Do not push directly to upstream. Always create the PR from your fork (origin).
- If `git symbolic-ref refs/remotes/upstream/HEAD` is not available, fail fast: stop, inspect remotes, and fix upstream configuration before continuing.

### Verification Commands

Use these to sanity-check the workflow before opening a PR:

```sh
# 1. Clean working tree and staged area
git status --porcelain && git diff --exit-code && git diff --cached --exit-code

# 2. Detect upstream default branch
git fetch upstream

# 3. Dry-run rebase preview (no changes)

# 4. Signoff verification (use allow-empty to avoid history changes)
git reset HEAD~

# 5. Push checks
# If PR branch already exists and needs updating after squash:
```

Remove the temporary empty commit immediately after step 4. Dry-run commands confirm that no unintended history rewrites occur and that force pushes use `--force-with-lease` only when explicitly required.
