---
Version: 2.1
Last Updated: 2026-01-18
Maintenance: Longhorn Development Team
Purpose: Multi-Repo Workspace Development Guidance for AI Coding Agents
Changelog: Integrated AGENTS.md and AGENTS.new.md with enhanced structure and verification procedures
---

<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

---

# PART 1: FOUNDATION AND POLICY

## Scope and Workspace Definition

This guide provides essential information for AI coding agents working on the Longhorn project in a multi-repository workspace environment.

### Applicability

- **Scope**: This document applies to the entire workspace
- **Workspace Root**: The folder containing THIS document and the common parent of `.opencode` and `openspec` directories
- **Applies To**: All AI agents, all repositories, all development workflows in this workspace

### Workspace Structure

The workspace follows a structured layout:

```
workspace-root/
  AGENTS.md                     (this file)
  .opencode/                    (local development state)
  openspec/                     (specification and documentation)
  context/:                     (Architectural indices)
  repo/                         (all project repositories)
    types/
    go-common-libs/
    longhorn-manager/
    [... additional repos ...]
  ticket/                       (task-specific workspace)
  [other workspace files]
```

### Workspace Setup

Initializing the workspace:
- **Mandatory Action**: Whenever the `repo/` directory is empty or missing required components, invoke the `repo-init` skill.
- **Dependency**: The skill relies on `repo/repo-list` as the source of truth for required repositories.
- **Interactive Setup**:
    - The agent MUST prompt the user for their GitHub username to distinguish between official code and personal forks.
    - If no username is provided, the agent will default to `upstream` (official) only.

Once repositories are cloned:
1. **Branch Alignment**: Verify that the local `upstream` branch tracks the correct default branch (e.g., `main` or `master`) identified by the initializer.
2. **Index Generation**: Immediately invoke `interaction-mapper` skill to refresh the architectural maps (`context/indices/*`) based on the newly pulled source code.

---

## Critical Policy: DO NOT COMMIT WORKSPACE AGENTS FILES

**MUST NOT commit to any repository:**

1. This file: `AGENTS.md` at workspace root
2. Sub-repo convenience files: If creating `AGENTS.md` under sub-repos for local reference, it MUST remain untracked and unstaged

**Before opening any PR, MUST confirm:**

```bash
git status                  # Verify AGENTS.md does NOT appear
git diff --cached           # Verify AGENTS.md is NOT staged
```

**Rationale**: This file contains workspace-local instructions and AI agent guidance that are NOT intended for repository history. It is environment-specific and should never be part of the canonical source repositories.

---

## Path Usage Convention (MUST FOLLOW)

All path references in documentation, comments, and AI interactions MUST use paths relative to workspace root.

### Identifying Workspace Root

Look for the parent directory containing **BOTH** `.opencode` and `openspec` folders. This is the workspace root for all AI agents.

### Path Format Rules

**CORRECT examples (workspace-relative):**

AGENTS.md
openspec/AGENTS.md
openspec/project.md
repo/longhorn-manager
repo/types
repo/longhorn-manager/controller/volume_controller.go

**INCORRECT examples (do NOT use):**

/home/username/path/to/workspace/AGENTS.md           (absolute path)
./repo/types                                         (unnecessary leading dot)
C:/Users/Developer/longhorn/AGENTS.md                (Windows absolute path)
${HOME}/workspace/AGENTS.md                          (variable expansion)

### Rationale

- Makes references portable and environment-independent
- Easier for AI agents to locate files consistently
- Avoids hardcoding absolute paths that may change between developers and CI systems
- Supports both local development and CI/CD pipelines

### When to Use Absolute Paths

ONLY in code that requires absolute paths at runtime:

- Go's `os.Open(filepath)` when the filepath comes from environment variables or user input
- Python's `open(filepath)` when reading configuration files from system locations
- Scripts that reference fixed system locations (e.g., `/etc/config`)

**In all other cases (documentation, comments, configuration files), use workspace-relative paths.**

---

## English ASCII-Only Enforcement (Entire Workspace)

**MANDATORY**: All files in this workspace MUST be written in English using ONLY ASCII characters (0x00-0x7F).

### Applies To

- Source code (Go, Python, JavaScript, Rust, etc.)
- Comments (inline, block, documentation comments)
- Commit messages
- Documentation (Markdown, text files, README files)
- Configuration files (YAML, JSON, TOML, Helm templates)
- Scripts (Bash, Shell, Makefile, Python, Dockerfile)
- Log messages and error strings

### Restrictions

**No exceptions. No Unicode characters, emojis, or non-ASCII symbols are allowed.**

Prohibited characters:
- Unicode letters (Mandarin, Japanese, Korean, Cyrillic, etc.)
- Emoji and symbols outside ASCII range
- Accented characters (e, o, n with tildes, etc.)
- Typographic quotes or dashes
- Mathematical or currency symbols beyond ASCII

### Verification Command

Before opening any PR, MUST scan changed files for non-ASCII characters:

# Check specific file for non-ASCII violations

```bash
grep -P -n '[^\x00-\x7F]' filepath
```

# If grep returns any output, you MUST fix those lines immediately

# Check all modified files in current branch

```bash
git diff --name-only | xargs -I {} sh -c 'echo "Checking {}:"; grep -P -n "[^\x00-\x7F]" {} || echo "  [OK]"'
```

# Find specific non-ASCII characters in a file

```bash
file=$(your-file-path)
grep -P -n '[^\x00-\x7F]' "$file" | while IFS=: read -r line_no content; do
  echo "Line $line_no: $content"
done
```

### Examples

**CORRECT (ASCII-only):**

```go
func helloWorld() {
    fmt.Println("hello world")
}
```

**INCORRECT (contains non-ASCII):**

```go
func helloWorld() {
    fmt.Println("你好，世界") // WRONG: message string is not in English ASCii
}
```

---

## go.mod Replace Policy

Go module replace directives are useful for local development but must be cleaned before submitting pull requests.

### Allowed During Development

Replace directives pointing to local paths are **ALLOWED during development**:

```
// Example go.mod
module github.com/longhorn/longhorn-manager

require github.com/longhorn/types v1.5.0

replace github.com/longhorn/types => ../types
```

**Rationale**: Allows local testing across multiple repos without publishing intermediate versions.

### BEFORE Opening Any PR

1. MUST remove all local replace directives
2. MUST restore proper module version references
3. MUST run `go mod tidy`
4. MUST verify `go.mod` and `go.sum` are clean

### Verification Procedure

```bash
# Navigate to repo root

cd repo/[repo-name]

# Check for local replace directives
grep "replace" go.mod
# Expected output: (empty, or only dev-only replaces if intentional)

# Clean module state
go mod tidy

# Verify go.mod shows no local paths
git diff go.mod
# Expected: shows only version number changes, no local paths

# Verify go.sum is consistent
git diff go.sum
# Expected: shows hash updates corresponding to go.mod changes
```

### Example: Cleaning Replace Directives

Before PR:

```
// BAD: contains local replace
replace github.com/longhorn/types => ../types
require github.com/longhorn/types v1.5.0
```

After cleaning:

```
// GOOD: contains version reference only
require github.com/longhorn/types v1.5.0
```

---

## Change-Scoped Hygiene Only (Pragmatic Approach)

Agents MUST keep diffs minimal and directly related to the requested change. This ensures clarity, reviewability, and reduces the risk of introducing unintended side effects.

### Scoping Rules

**Linting, formatting, and spell checking:**

- MUST be scoped to modified files and nearby lines only
- MAY apply additional minimal fixes outside the immediate change **ONLY when required to:**
  - Pass compilation
  - Satisfy linter rules and validation
  - Satisfy test suite
  - Satisfy ASCII-only policy
  - Fix broken build

- Any such additional fixes MUST be:
  - Minimal in scope
  - Clearly justified in the PR description
  - Separated logically from the primary change

### Example: Acceptable Minimal Fixes

**Scenario**: Fixing a typo in a function you are modifying

```go
// Original
func processVolume(vol *Volume) {
  // TODO: imploment logic here
  return
}

// Acceptable fix (part of change):
func processVolume(vol *Volume) {
  // TODO: implement logic here
  return
}
```

**Justification**: Typo fix is in the immediate vicinity of the modified function and improves code quality.

### Extra Restrictions for Upstream CSI Sidecar Clones

For upstream-derived repositories (`csi-*`, `livenessprobe`), apply stricter scoping:

**PROHIBITED:**
- No refactors or architectural changes
- No mechanical reformatting (e.g., gofmt applied repo-wide)
- No repo-wide lint or spell cleanups
- No dependency upgrades unless security-critical or version-bump required

**ALLOWED:**
- Only minimal, targeted changes directly related to explicit request
- Security patches and version bumps (with justification)
- Build fixes (when Dapper/toolchain incompatibility exists)

**Rationale**: These repos are upstream-derived. Minimizing local modifications reduces maintenance burden and makes it easier to rebase on upstream updates.

---

# PART 2: WORKSPACE STRUCTURE

## Repository Location and Organization

**CRITICAL**: All repositories listed in this document are located inside the `repo/` directory within the workspace root.

### Navigation Rules

When referencing or navigating to repositories:

- Use paths like `repo/longhorn-manager` or `repo/types`
- Do NOT look for repositories at the workspace root directly
- Always use workspace-relative paths from the workspace root
- Example: To access the Longhorn manager controller, use `repo/longhorn-manager/controller/` not `/longhorn-manager/controller/`

### Repository Structure

```
repo/
  backing-image-manager/      (Team-owned)
  cli/                        (Team-owned)
  longhorn-engine/            (Team-owned)
  longhorn-instance-manager/  (Team-owned)
  longhorn-manager/           (Team-owned)
  longhorn-share-manager/     (Team-owned)
  longhorn-spdk-engine/       (Team-owned)
  
  types/                      (Shared library)
  go-common-libs/             (Shared library)
  backupstore/                (Shared library)
  go-iscsi-helper/            (Shared library)
  go-spdk-helper/             (Shared library)
  sparse-tools/               (Shared library)
  
  csi-attacher/               (Upstream CSI)
  csi-node-driver-registrar/  (Upstream CSI)
  csi-provisioner/            (Upstream CSI)
  csi-resizer/                (Upstream CSI)
  csi-snapshotter/            (Upstream CSI)
  livenessprobe/              (Upstream CSI)
  
  longhorn/                   (Packaging)
  longhorn-ui/                (Packaging)
  longhorn-tests/             (Integration)
  
  dep-versions/               (Version coordination)
```

---

## Team-Owned Native Longhorn Component Repositories

These repositories are actively developed and maintained by the Longhorn team.

### Build Contract

**Entrypoint**: ALWAYS use `make`

**Constraint**: Do NOT run `go build`, `go test`, or `docker build` directly

**Mechanism**: The Makefile automatically invokes Dapper to run builds inside a consistent containerized environment. This ensures reproducible builds and consistent development environments.

### Repositories

- `repo/backing-image-manager` - Manages backing image lifecycle
- `repo/cli` - Longhorn command-line interface
- `repo/longhorn-engine` - Storage engine implementation
- `repo/longhorn-instance-manager` - Instance lifecycle management
- `repo/longhorn-manager` - Main orchestration and API server
- `repo/longhorn-share-manager` - Shared volume management
- `repo/longhorn-spdk-engine` - SPDK-based storage engine

### Build Commands

```bash
cd repo/[repo-name]

# Build the component
make

# Run tests
make test

# Run validation
make validate

# Common combined workflow
make clean && make && make test && make validate
```

---

## Shared Libraries and Helpers (High-Impact Allowlist)

These repositories are high-impact dependencies. Changes here commonly require coordinated validation and updates in dependent component repositories.

### Repository List

- `repo/types` - CRD definitions and API types
- `repo/go-common-libs` - Shared Go utilities and helpers
- `repo/backupstore` - Backup storage abstraction layer
- `repo/go-iscsi-helper` - iSCSI protocol helpers
- `repo/go-spdk-helper` - SPDK abstraction layer
- `repo/sparse-tools` - Sparse file handling utilities

### Impact Consideration

When modifying a shared library:

1. Dependent repositories will need to update their `go.mod` to pick up changes
2. May require coordinated releases (version bumps)
3. Integration testing across multiple components recommended
4. Document all downstream impacts in PR description

### Example Change Impact

Modified: repo/types (added new CRD field)
Downstream impacts:
  - repo/longhorn-manager: update go.mod, add controller handler
  - repo/longhorn-engine: update go.mod, add serialization logic
  - repo/longhorn-instance-manager: update go.mod if needed
Expected validation:
  - Full test suite for affected components
  - Integration tests with volume workflows

---

## Upstream Kubernetes CSI Sidecar Repositories

These repositories are upstream kubernetes-csi sidecar clones maintained by the Kubernetes community. They are included in the workspace to build and publish container images consumed by the Longhorn Helm chart as CSI driver dependencies.

### Repository List

- `repo/csi-attacher` - CSI volume attachment controller
- `repo/csi-node-driver-registrar` - Node driver registration sidecar
- `repo/csi-provisioner` - Volume provisioning sidecar
- `repo/csi-resizer` - Volume resizing sidecar
- `repo/csi-snapshotter` - Snapshot management sidecar
- `repo/livenessprobe` - Driver liveness probe

### Ownership and Change Policy

**Agents MUST treat these repositories as upstream-derived and minimize local modifications.**

**MUST NOT:**
- Perform feature work here unless explicitly requested
- Refactor code for code quality improvements
- Reformat code repo-wide
- Perform mechanical code changes as part of unrelated work

**MAY do when required:**
- Security patches and critical bug fixes
- Version bumps and dependency updates
- Build system fixes (Dapper incompatibility, etc.)
- Minimal patch deltas to fix Longhorn-specific issues
- **Always prefer upgrading to upstream version when possible**

### Build System

**Agents MUST NOT assume Dapper `scripts/` targets in these repositories.**

**Instead:**
- Use each repository's own Makefile or `release-tools/` flow
- Follow `repo/dep-versions/versions.json` for version coordination
- Treat this as vendor-like code; follow Change-Scoped Hygiene strictly

### Example Build Commands

```bash
cd repo/csi-attacher

# Check repo-specific build system
ls -la Makefile release-tools/

# Use repo-native flow (varies by sidecar)
make                        # if Makefile exists
./release-tools/build.sh    # if release-tools exists
```

---

## Integration and Packaging Repositories

### repo/longhorn (Helm Chart and Manifests)

- Purpose: Helm chart, deployment manifests, and design documents
- Toolchain: Not Go-based; uses templating and YAML
- See CRD Generation and Helm Chart Workflow section for operational steps
- Build command: `helm lint` or Helm-specific commands

### repo/longhorn-ui (Frontend Application)

- Purpose: Frontend web UI for Longhorn dashboard
- Toolchain: Node.js, not Go or Dapper
- Build command: `npm install && npm run build`
- Test command: `npm test`

### repo/longhorn-tests (E2E Test Suite)

- Purpose: End-to-end automated tests
- Toolchain: Python-based, not Go or Dapper
- Build command: Depends on test runner (`pytest`, custom runner, etc.)
- Purpose: Validates multi-component workflows

---

## Version Coordination Repository

### repo/dep-versions (Dependency Coordination)

Central location for version coordination across the workspace.

**Files:**
- `versions.json` - Version source of truth for external libraries and CSI sidecars
- `version` - Current workspace version

**Used by:**
- CI/CD pipelines for consistent version management
- Release workflows
- Dependency tracking

**When to update:**
- Upgrading external dependencies
- New CSI sidecar versions
- Workspace version bumps

---

## Build Contract and Toolchain Rules

### Native Longhorn Components (Dapper-Based)

| Repository | Build | Test | Validation | Notes |
|-----------|-------|------|-----------|-------|
| backing-image-manager | `make` | `make test` | `make validate` | Dapper containerized |
| cli | `make` | `make test` | `make validate` | Dapper containerized |
| longhorn-engine | `make` | `make test` | `make validate` | Dapper containerized |
| longhorn-instance-manager | `make` | `make test` | `make validate` | Dapper containerized |
| longhorn-manager | `make` | `make test` | `make validate` | Dapper containerized |
| longhorn-share-manager | `make` | `make test` | `make validate` | Dapper containerized |
| longhorn-spdk-engine | `make` | `make test` | `make validate` | Dapper containerized |

### CSI Sidecar Clones (Upstream Flow)

| Repository | Build | Test | Notes |
|-----------|-------|------|-------|
| csi-attacher | Check native Makefile | Check upstream docs | Upstream flow, minimal mods |
| csi-node-driver-registrar | Check native Makefile | Check upstream docs | Upstream flow, minimal mods |
| csi-provisioner | Check native Makefile | Check upstream docs | Upstream flow, minimal mods |
| csi-resizer | Check native Makefile | Check upstream docs | Upstream flow, minimal mods |
| csi-snapshotter | Check native Makefile | Check upstream docs | Upstream flow, minimal mods |
| livenessprobe | Check native Makefile | Check upstream docs | Upstream flow, minimal mods |

### Frontend and Integration Repositories

| Repository | Build | Test | Notes |
|-----------|-------|------|-------|
| longhorn | `helm lint` | Helm validation | YAML templates, not code |
| longhorn-ui | `npm install && npm run build` | `npm test` | Node.js toolchain |
| longhorn-tests | `pytest` or runner | Test suite | Python-based E2E tests |

---

## Dependency Hierarchy and Impact Analysis

### Layered Architecture

```
Foundation Layer
    repo/types
        ^
        |
Utility Layer
    repo/go-common-libs
        ^
        |
Helper Layer
    repo/backupstore
    repo/go-iscsi-helper
    repo/go-spdk-helper
    repo/sparse-tools
        ^
        |
Component Layer
    repo/longhorn-engine
    repo/longhorn-spdk-engine
        ^
        |
Orchestration Layer
    repo/longhorn-instance-manager
        ^
        |
Controller Layer
    repo/longhorn-manager
    repo/longhorn-share-manager
        ^
        |
Utility and CLI Layer
    repo/backing-image-manager
    repo/cli
        ^
        |
Packaging and Integration Layer
    repo/longhorn (Helm chart)
    repo/longhorn-ui (Frontend)
    repo/longhorn-tests (E2E tests)
```

External
    repo/csi-* (CSI sidecars - version coordinated)
    repo/dep-versions (Version coordination)

### Impact Rule for Lower-Layer Changes

**If you modify a lower-layer repository (e.g., types, go-common-libs, backupstore), you MUST acknowledge that upper-layer repositories will need to update their go.mod to pick up the changes.**

**Always mention this dependency explicitly in your summary with specific repository names.**

### Example Impact Documentation

## Change Summary
- Modified: repo/types (added BackupStatus.RetryCount field)

## Impact Analysis
- Direct dependents requiring go.mod update:
  - repo/longhorn-manager (implements BackupController)
  - repo/longhorn-engine (serializes Backup resources)
  - repo/longhorn-instance-manager (monitors backup state)

- Secondary impacts:
  - repo/longhorn-tests (E2E tests may require updates)
  - Helm chart manifests may need documentation updates

## Recommended Validation
- Full test suite in repo/longhorn-manager
- Integration tests in repo/longhorn-tests
- Manual backup workflow testing

---

## Non-Allowlisted Repositories

If a repository is **NOT listed above**, the agent MUST NOT assume:

- It uses Dapper
- It has a `scripts/` directory
- `make validate/test/build/ci` behaves like Native Longhorn repos

### Discovery Process for Non-Allowlisted Repos

**For any non-allowlisted repository, MUST first identify its toolchain:**

1. Check for build automation:
   - Look for Makefile
   - Check for scripts/ directory
   - Look for package.json (Node.js)
   - Look for setup.py or requirements.txt (Python)
   - Check for Cargo.toml (Rust)

2. Identify entrypoints and test runners:
   - Read the repository's README.md or CONTRIBUTING.md
   - Check CI configuration (.github/workflows/, .gitlab-ci.yml, etc.)
   - Examine Makefile targets or scripts

3. Run appropriate commands:
   - Do not assume `make` will work
   - Do not assume `go test` is the test runner
   - Follow repository-specific conventions

---

# PART 3: DEVELOPMENT WORKFLOW

## Code Investigation Navigation Strategy (MUST FOLLOW)

This section applies to **ALL engineering investigations**, including debugging, design changes, refactoring, and bug fixes.

The goal is to navigate efficiently through a large, distributed codebase without getting lost in irrelevant details.

### 1. Scope Focusing Strategy

**Phase 1: Architectural Navigation (Map First)**
- **Do NOT** start by reading files randomly or grepping blindly.
- **Do** use available skills (e.g., `repo-navigator`, `interaction-mapper`) to identify the architectural components first.
- **Goal**: Identify which CRD, Controller/Operator, or Service is responsible for the concern.

**Phase 2: Context Mapping**
- Draw the relationships between **Resource (CRD) <-> Controller <-> Service**.
- Explicitly identify:
  - Which component maintains the `Status` vs. `Spec`.
  - Where the resource is allowed to be modified.

**Phase 3: Targeted Investigation**
- When the scope has been narrowed to specific components (for example, "VolumeController"), collaborate with dedicated investigation agents (`explore`, `librarian`) to analyze and follow the relevant call chains.
- Only use broad/exhaustive scans as a last resort.

### 2. Resource Principles

- **Navigate first, detail later.**
- If the architectural map is unclear, revise the map before reading code.
- Avoid consuming agent context with irrelevant files.

### 3. Standard Investigation Protocol

When given a task (e.g., "Investigate BackingImages updates"):
1.  **Map**: List which controllers/operators relate to the resource. Identify entry points for update/monitor/write operations.
2.  **Focus**: Search deep patterns or call-chains *only* for the identified components.
3.  **Trace**: Synthesize findings and trace the minimal set of code paths in detail.
4.  **Validate**: Cross-reference with official docs or external sources if edge cases appear.

### Resource Investigation Principles

- Navigate first, detail later
- If the architectural map is unclear, revise the map before reading code
- Avoid consuming agent context with irrelevant files
- Focus on the narrow path for the requested change

### Example: BackingImage CR Update Workflow

```
User Request (API Call)
    |
    v
CRD: BackingImage (repo/types/pkg/apis/longhorn.io/v1beta2/backing_image.go)
    |
    +-- Spec: User-provided configuration
    |   (data source, size, etc.)
    |
    +-- Status: Managed by BackingImageController
        (current state, conditions, progress)
    |
    v
Controller: BackingImageController (repo/longhorn-manager/controller/backing_image_controller.go)
    |
    +-- Reconciliation Logic
    |   (compares desired vs actual state)
    |
    +-- Event Handling
    |   (watches resource changes, triggers actions)
    |
    v
Service Layer: BackingImageManager (repo/backing-image-manager)
    |
    +-- Disk Operations
    |   (download, cache, cleanup)
    |
    +-- Status Reporting
    |   (updates BackingImage status)
    |
    v
Supporting Libraries
    repo/go-common-libs (shared utilities)
    repo/types (CRD definitions)
    repo/sparse-tools (sparse file handling)
```

### Investigation Checklist

- [ ] Identified primary CRD(s) involved
- [ ] Located responsible controller(s)
- [ ] Mapped service layer components
- [ ] Identified entry point (API, webhook, reconciliation)
- [ ] Traced call chain from entry to completion
- [ ] Found error handling and edge cases
- [ ] Cross-referenced with documentation
- [ ] Validated understanding with teammates or existing tests

---

## Git Workflow Per Repository

Each repository in the workspace follows a consistent Git workflow.

### Remote Naming Convention

**Each repository SHOULD have the following remotes configured:**

| Remote | Points To | Purpose | Access |
|--------|-----------|---------|--------|
| `upstream` | `github.com/longhorn/repo` | Canonical Longhorn repository | Read-only for most developers |
| `origin` | `github.com/developer-account/repo` | Developer personal fork | Push target (write permission) |

**Configuration Example:**

```bash
cd repo/longhorn-manager

# Verify remotes are configured
git remote -v
# Expected output:
# origin    https://github.com/myaccount/longhorn-manager (fetch)
# origin    https://github.com/myaccount/longhorn-manager (push)
# upstream  https://github.com/longhorn/longhorn-manager (fetch)
# upstream  https://github.com/longhorn/longhorn-manager (push)
```

**Notes:**

- Do not assume a specific developer account name; treat `origin` as personal fork
- Protocol may be `https` or `git@github.com:`; both are acceptable
- If remotes are not configured, run:
    ```bash
    git remote add upstream https://github.com/longhorn/[repo-name]
    git remote add origin https://github.com/[your-account]/[repo-name]
    ```

---

### Upstream Default Branch Detection

Different repositories use different default branch names (`main` or `master`). Agents MUST detect the correct branch dynamically rather than assuming.

**Dynamic Detection Command:**

```bash
# Determine upstream default branch
git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@'

# Output will be either "main" or "master"
```

**Reference Table: Current Upstream Default Branches**

| Branch Name | Repositories |
|-----------|-------------|
| `master` | backing-image-manager, cli, longhorn-engine, longhorn-instance-manager, longhorn-manager, longhorn-share-manager, backupstore, go-iscsi-helper, sparse-tools, longhorn, longhorn-ui, longhorn-tests |
| `main` | longhorn-spdk-engine, types, go-common-libs, go-spdk-helper |

**Note**: Always verify dynamically; do not hard-code branch names in scripts.

---

### Feature Branch Naming Convention

Feature branches MUST follow the naming pattern: `storyid-brieftitle`

**Format:** `[numeric-id]-[brief-description]`

**Examples:**

- `12345-fix-volume-attach`
- `6789-add-backup-validation`
- `54321-improve-csi-error-handling`

**Rules:**

- Use lowercase letters and hyphens
- Include numeric story/issue ID at start
- Keep description concise (40 characters max after ID)
- Use hyphens to separate words

---

### Development Workflow

Follow this workflow for all development on repositories.

#### Step 1: Create Feature Branch from Upstream

```bash
cd repo/[repo-name]

# Fetch latest upstream branches
git fetch upstream

# Create feature branch from upstream default
git switch -c storyid-brieftitle upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')
```

#### Step 2: Develop on Feature Branch

- Make commits incrementally
- MUST NOT commit directly to `main`, `master`, or `upstream` branches
- Use clear, descriptive commit messages
- Verify changes work locally before pushing

#### Step 3: Rebase Before Pushing

Before pushing, rebase onto the latest upstream changes to avoid conflicts:

```bash
# Fetch latest upstream changes
git fetch upstream

# Rebase feature branch onto upstream default
git rebase upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')

# If conflicts occur, resolve and continue
# git add <resolved-files>
# git rebase --continue
```

#### Step 4: Push Feature Branch to Origin

```bash
# Push to personal fork (origin)
git push -u origin storyid-brieftitle

# Verify push succeeded
git log --oneline -5 origin/storyid-brieftitle
```

#### Step 5: Create Pull Request

**User manually curates commit history and opens PR on GitHub.**

Agent SHOULD NOT force-push, amend, or squash unless explicitly requested by user.

**User is responsible for:**
- Reviewing commit history
- Squashing/reordering commits if needed
- Writing PR title and description
- Initiating the PR on GitHub

---

### Git Safety Rules (MUST NOT)

Agents MUST NOT perform these operations without explicit user request:

- **Add, remove, or rename git remotes** unless explicitly requested
  - Remotes configuration is user-specific
  - Incorrect setup breaks local workflows

- **Force-push to any branch** (`git push --force`) unless explicitly requested
  - Rewrites history and breaks other developers' branches
  - Only safe in personal feature branches, not in shared branches

- **Push directly to upstream remote**
  - All pushes go to `origin` (personal fork)
  - Pull requests merge upstream

- **Rebase or modify shared/protected branches** (`main`, `master`, `v1.x.x`) unless explicitly requested
  - These branches are managed by release workflows
  - Rewriting history on these branches breaks the repository state

- **Create or merge PRs automatically**
  - User handles PR submission and merging
  - Automatic PR creation bypasses code review process

- **Use git commit signing** (`git commit -s` or `--signoff`)
  - Commit signing is the user's responsibility
  - User curates commits before pushing
  - Signing should be done during manual squashing if needed

---

# PART 4: QUALITY ASSURANCE

## Pre-Pull Request Verification: Definition of Done

**Before telling the user the task is finished, you MUST verify all four criteria below.**

This checklist ensures code quality, compliance, and buildability before submission.

---

## Verification 1: Clean Mod Files

**Ensure no local Go module replace directives remain.**

### Verification Command

```bash
cd repo/[repo-name]

# Check for local replace directives
grep "replace" go.mod

# Expected output: (empty, or only dev-only replaces if explicitly approved)

# Clean module state
go mod tidy

# Verify changes are only version updates
git diff go.mod go.sum
```

### Success Criteria

- No local `replace` directives using relative paths (e.g., `replace ... => ../types`)
- All dependencies specified by version number (e.g., `v1.5.0`)
- `go mod tidy` produces no changes
- `git diff go.mod go.sum` shows only version updates

### Common Issues and Fixes

**Issue**: go.mod contains local replace

```
// BAD
replace github.com/longhorn/types => ../types
```

**Fix**: Remove and run `go mod tidy`

```bash
# Edit go.mod to remove replace line, then:
go mod tidy

# Verify upstream version is used
grep "github.com/longhorn/types" go.mod
# Should show: require github.com/longhorn/types v1.5.0
```

---

## Verification 2: ASCII Safe (English Only, No Non-ASCII Characters)

**Scan all modified files for non-ASCII characters.**

### Verification Command


```bash
# Check specific file
grep -P -n '[^\x00-\x7F]' filepath

# Expected output: (empty)

# Check ALL modified files in branch
git diff --name-only | xargs -I {} sh -c \
  'echo "Checking {}:"; \
   grep -P -n "[^\x00-\x7F]" {} || echo "  [OK]"'
```

### Success Criteria

- `grep` command returns no output
- All modified files contain only ASCII characters (0x00-0x7F)
- No Unicode, emoji, or accented characters in any file

### Finding and Fixing Non-ASCII Characters

```bash
# Identify line and character
file="repo/longhorn-manager/main.go"
grep -P -n '[^\x00-\x7F]' "$file"
# Output: Line 42: // Volumestatuts - check and fix this line

# View the problematic line
sed -n '42p' "$file"

# Fix: Replace non-ASCII character with ASCII equivalent
# Example: "Volumestatuts" should be "VolumeStatus" (no special chars)

# Verify fix
grep -P -n '[^\x00-\x7F]' "$file"
# Output: (empty, success)
```

### Common Non-ASCII Issues

| Issue | Example | Fix |
|-------|---------|-----|
| Curly quotes | `"hello"` (curly) | Use straight quotes `"hello"` |
| Accented letters | `Soren` (with accent) | Use `Soren` (no accent) |
| Emoji | `Done!` | Remove emoji, use text `Done!` |
| Typographic dashes | `A-B` (en-dash) | Use hyphen `A-B` |
| Currency symbols | `$100 USD` | Use ASCII `$100 USD` |
| Foreign languages | Chinese characters | Use English description instead |

---

## Verification 3: No Ghost Files (AGENTS.md Not Staged)

**Verify AGENTS.md is NOT in the git staging area.**

### Verification Command

```bash
# Check git status
git status

# Expected: AGENTS.md should NOT appear in output

# Check git staging area
git diff --cached

# Expected: AGENTS.md should NOT appear in output

# Additional safety check
git ls-files --cached | grep "AGENTS.md"

# Expected output: (empty)
```

### Success Criteria

- AGENTS.md does NOT appear in `git status` output
- AGENTS.md is not staged (not in `git diff --cached`)
- AGENTS.md remains untracked and unstaged
- File exists locally but is not tracked by Git

### Common Issues and Fixes

**Issue**: AGENTS.md was accidentally added

```bash
# Check if staged
git status | grep AGENTS.md

# Remove from staging
git reset AGENTS.md

# Verify it's unstaged
git status
```

**Issue**: AGENTS.md appears in `git ls-files`

```bash
# File was previously committed (mistake)
git rm --cached AGENTS.md
git commit -m "Remove AGENTS.md from tracking"

# Ensure .gitignore prevents re-adding
echo "AGENTS.md" >> .gitignore
git add .gitignore
git commit -m "Add AGENTS.md to .gitignore"
```

---

## Verification 4: Builds Pass

**Verify the repository builds successfully.**

### Build Command

```bash
cd repo/[repo-name]

# Determine repository type and run appropriate build

# For Native Longhorn repos (uses Dapper):
make
# or
make clean && make

# For CSI sidecar repos:
make                        # Check native Makefile

# For Node.js repos (longhorn-ui):
npm install && npm run build

# For Python repos (longhorn-tests):
pytest                      # or repository-specific test runner
```

### Success Criteria

- Build completes without errors
- No compilation errors or warnings (unless pre-existing)
- Test suite passes (if tests were added/modified)
- No new failing tests introduced

### Build Verification Checklist

```bash
# Full verification for Longhorn component repo
cd repo/longhorn-manager

# Step 1: Clean build
make clean

# Step 2: Build
make
# Expected: Successful completion, no errors

# Step 3: Test
make test
# Expected: Tests pass

# Step 4: Validation
make validate
# Expected: Validation passes (lint, vet, etc.)

# Step 5: Verify no uncommitted changes (except expected)
git status
# Expected: Only expected modified files

# Step 6: Verify binary was created
ls -la bin/
# Expected: Binary exists and is recent
```

### Common Build Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| `go: cannot find module` | Missing `go mod tidy` | Run `go mod tidy` |
| `dapper: not found` | Not using `make` | Use `make` instead of `go build` |
| `npm: command not found` | Node.js environment | Run in correct environment or `make` |
| Compilation errors | Syntax or import errors | Check error messages, verify code changes |
| Test failures | New tests fail or old tests broken | Review test output, fix code |

---

## Complete Pre-PR Checklist

**Before submitting work, verify ALL of the following:**

### Code Quality

- [ ] **Changes are minimal and scoped** - Only changes related to requested work
- [ ] **ASCII-safe** - All files contain only ASCII characters (verified via grep)
- [ ] **No debug code** - No console.log, print statements, or TODO markers left
- [ ] **Error handling** - Errors are properly handled and logged
- [ ] **Comments added** - Complex logic has explanatory comments

### Git and Repository

- [ ] **Clean Mod Files** - No local `replace` directives, `go mod tidy` run
- [ ] **No Ghost Files** - AGENTS.md not staged
- [ ] **Correct branch** - Feature branch created from upstream default
- [ ] **Commits squashed** - Logical commit history (if requested)
- [ ] **Rebase applied** - Rebased onto latest upstream default branch

### Build and Tests

- [ ] **Builds Pass** - `make` completes successfully
- [ ] **Tests Pass** - All tests pass locally
- [ ] **No new warnings** - No new compilation warnings introduced
- [ ] **Validation succeeds** - `make validate` passes (lint, vet, etc.)

### Documentation and Communication

- [ ] **Dependency impacts documented** - If lower-layer change, upper-layer impacts listed
- [ ] **Commit messages clear** - Each commit has clear, descriptive message
- [ ] **Path references correct** - All paths use workspace-relative format
- [ ] **Related tests updated** - Tests added or updated if behavior changed

### Final Checks

- [ ] **Ready for review** - Code is ready for peer review
- [ ] **PR template completed** - Title, description, impacts, testing details
- [ ] **Reviewers assigned** - Code review requested from appropriate team members

---

# PART 5: QUICK REFERENCE

## Common Development Commands

### Repository Setup

```bash
# Clone and configure repository
git clone https://github.com/[account]/longhorn-manager.git
cd longhorn-manager

# Add upstream remote
git remote add upstream https://github.com/longhorn/longhorn-manager

# Verify remote configuration
git remote -v

### Branch and Feature Development

# Detect default branch
git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@'

# Create feature branch
git fetch upstream
git switch -c 12345-feature-name upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')

# Make changes...

# Rebase before push
git fetch upstream
git rebase upstream/$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')

# Push to personal fork
git push -u origin 12345-feature-name
```

### Verification Commands

```bash
# Check for non-ASCII characters
git diff --name-only | xargs -I {} sh -c 'echo "{}:"; grep -P -n "[^\x00-\x7F]" {} || echo "  [OK]"'

# Clean Go modules
go mod tidy
grep "replace" go.mod  # Should return nothing

# Verify no AGENTS.md staging
git status | grep AGENTS.md  # Should return nothing

# Full build and test
cd repo/longhorn-manager
make clean && make && make test && make validate
```

---

## Troubleshooting Quick Reference

| Issue | Likely Cause | Solution |
|-------|-------------|----------|
| Repository not found | Wrong path or repo not in `repo/` | Verify path: `repo/longhorn-manager`, not root |
| Build fails: `dapper: not found` | Not using `make` | Use `make` instead of `go build` directly |
| Build fails: `go: cannot find module` | Missing `go mod tidy` | Run `go mod tidy` and verify go.mod |
| Non-ASCII character error | Unicode in comments or strings | Use `grep -P -n '[^\x00-\x7F]'` to find and fix |
| AGENTS.md appears in git status | File was tracked accidentally | Run `git reset AGENTS.md` and add to .gitignore |
| Can't push to upstream | Trying to push directly to upstream | Push to `origin` instead: `git push origin branch-name` |
| Rebase conflicts | Other changes on upstream branch | Resolve conflicts, then `git rebase --continue` |
| Unclear which repo to modify | Architecture not clear | Use Code Investigation Strategy (Phases 1-4) |
| Don't know default branch | Branch is `main` or `master` | Detect dynamically: `git symbolic-ref refs/remotes/upstream/HEAD` |
| Tests pass locally but fail in CI | Environment mismatch | Ensure `make test` uses Dapper consistency |

---

## Repository Quick Lookup

Quick reference for where to make common modifications:

### API and Data Model Changes

- **CRD and API types**: `repo/types`
- **Custom resource definitions**: `repo/types/pkg/apis/longhorn.io/`

### Core Logic Changes

- **Volume orchestration**: `repo/longhorn-manager/controller/volume_controller.go`
- **Engine operations**: `repo/longhorn-engine`
- **Instance management**: `repo/longhorn-instance-manager`
- **BackingImage handling**: `repo/backing-image-manager`, `repo/longhorn-manager/controller/backing_image_controller.go`

### Utility and Library Changes

- **Common helpers**: `repo/go-common-libs`
- **iSCSI integration**: `repo/go-iscsi-helper`
- **SPDK integration**: `repo/go-spdk-helper`
- **Backup storage**: `repo/backupstore`
- **Sparse file handling**: `repo/sparse-tools`

### Infrastructure and Integration

- **Helm charts and manifests**: `repo/longhorn`
- **UI frontend**: `repo/longhorn-ui`
- **E2E tests**: `repo/longhorn-tests`
- **Version coordination**: `repo/dep-versions`

---

## Path Examples and Format

### Workspace Root

Workspace root is `/path/to/workspace/` (contains `.opencode` and `openspec`)

### Correct Workspace-Relative Paths

```
AGENTS.md
repo/types
repo/longhorn-manager
repo/longhorn-manager/controller/volume_controller.go
repo/longhorn-manager/controller/volume_controller_test.go
openspec/AGENTS.md
openspec/project-structure.md
.opencode/dev-config
```

### Incorrect Paths (DO NOT USE)

```
/path/to/workspace/AGENTS.md                (absolute path)
./repo/types                                (unnecessary dot)
/home/user/workspace/AGENTS.md              (home-based absolute)
C:/Users/Developer/workspace/AGENTS.md      (Windows absolute)
${HOME}/workspace/AGENTS.md                 (variable expansion)
repo/types (at workspace non-root)          (missing context when not at root)
```

