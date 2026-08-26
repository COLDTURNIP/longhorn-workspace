# Longhorn Multi-Repository Workspace

A comprehensive development workspace for the Longhorn distributed block storage
system for Kubernetes, designed for use with compatible coding-agent harnesses.

## Overview

This workspace provides a unified environment for developing across Longhorn's
multiple repositories. Longhorn is a lightweight, reliable, and powerful
distributed block storage system designed for Kubernetes.

The workspace combines shared agent skills, repository-management scripts, and
workspace policies so that an active coding harness can help with code
navigation, repository initialization, build-system management, and related
development tasks.

## TL;DR: Quick Start

Follow [QUICKSTART.md](QUICKSTART.md) for a quick setup guide. Select the
harness you use when installing skills, then use the direct workspace scripts
described below.

## Required Toolchain

The workspace uses the following tools:

- Git
- Docker (for Dapper-based builds)
- Go 1.20+ (for native Go development)
- Node.js and npm (for longhorn-ui)
- Python 3.x (for longhorn-tests)
- Make
- Helm (for chart validation)

## Workspace Structure

The workspace is organized as follows:

```
workspace-root/
  README.md                     (this file)
  AGENTS.md                     (workspace policy; may be committed locally, never pushed)
  agent-skills/                 (maintained source for shared skills)
    ascii-scanner/              (each skill contains SKILL.md)
    ...
  scripts/                      (direct workspace tool interface)
    init-workspace.sh
    repo-init.sh
    yaml-duplicate-key-check.sh
  .agents/skills/               (generated universal project skill cache)
  repo/                         (all Longhorn repositories)
    repo-list.example.json      (example repository configuration)
    repo-list.json              (local repository configuration)
    backing-image-manager/      (team-owned component)
    cli/                        (team-owned component)
    longhorn-engine/            (team-owned component)
    longhorn-instance-manager/  (team-owned component)
    longhorn-manager/           (team-owned component)
    longhorn-share-manager/     (team-owned component)
    longhorn-spdk-engine/       (team-owned component)
    types/                      (shared library)
    go-common-libs/              (shared library)
    backupstore/                (shared library)
    go-iscsi-helper/            (shared library)
    go-spdk-helper/             (shared library)
    sparse-tools/               (shared library)
    csi-attacher/               (upstream CSI)
    csi-node-driver-registrar/  (upstream CSI)
    csi-provisioner/            (upstream CSI)
    csi-resizer/                (upstream CSI)
    csi-snapshotter/            (upstream CSI)
    livenessprobe/              (upstream CSI)
    longhorn/                   (packaging - Helm chart)
    longhorn-ui/                (packaging - frontend)
    longhorn-tests/             (integration tests)
    dep-versions/               (version coordination)
  ticket/                       (task-specific workspace for case studies)
```

## Initialization

Clone the workspace repository:

```bash
git clone https://github.com/COLDTURNIP/longhorn-workspace.git
cd longhorn-workspace
```

Install the project skills immediately after cloning:

```bash
npx skills add ./agent-skills
```

In the interactive prompts, choose only the skills you need, select your active
harness, and keep the installation at project scope. The CLI stages local-source
content in the universal `.agents/skills` cache and may create harness-specific
links. Installed content is not linked back to the maintained `agent-skills/`
source, so rerun the same add command after source changes.

### Configure Repository Sources

Before running any initialization prompt or command, configure
`repo/repo-list.json`. This file is the source of truth for each repository's
required `upstream` remote and optional `origin` remote.

Quick start tip: copy the example file and then edit it for your own fork URLs.

```bash
cp repo/repo-list.example.json repo/repo-list.json
# edit repo/repo-list.json for your environment
```

Use this format for `repo/repo-list.json`:

```json
{
  "longhorn-manager": {
    "upstream": "https://github.com/longhorn/longhorn-manager.git",
    "origin": "git@github.com:your-github-id/longhorn-manager.git"
  },
  "types": {
    "upstream": "https://github.com/longhorn/types.git"
  },
  "csi/external-attacher": {
    "upstream": "https://github.com/longhorn/csi-attacher.git"
  }
}
```

Format notes:

- JSON key = target path under `repo/`.
- `upstream` is required and must be a full git URL.
- `origin` is optional and should point to your writable fork URL.

### Using an AI Coding Harness

From the workspace root, ask your active harness to initialize the workspace:

```
initialize the workspace
```

The harness should run `bash scripts/init-workspace.sh`. This script:

1. Clones all component source repositories from `repo/repo-list.json` into
   `repo/`.
2. Configures each repository with an `upstream` remote pointing to the
   official Longhorn repository.
3. Configures the local `upstream` branch to track the upstream default branch
   (main or master).
4. Configures an optional `origin` remote when one is specified.
5. Generates architectural indices (currently `interaction-mapper`) under
   `context/indices/` so the harness can understand cross-repository
   architecture for navigation and implementation tasks.

The initialization script applies remotes from `repo/repo-list.json`. Update
that file first whenever you need to change upstream or personal fork (`origin`)
URLs.

### Manual Initialization

Run the scripts directly when you prefer to initialize without an AI harness:

```bash
bash scripts/init-workspace.sh --dry-run  # Preview actions
bash scripts/init-workspace.sh            # Execute (default)
```

## Working with Skills

The workspace maintains shared skills under `agent-skills/`. Install selected
skills into `.agents/skills` as described above, then ask the active harness to
use them for common development tasks. Mention a skill by name or describe the
task you want to accomplish; no product-specific setup is required.

### Available Scripts

These scripts are direct workspace tools:

- `bash scripts/init-workspace.sh`: Initialize repositories from
  `repo/repo-list.json`, configure `upstream` and optional `origin` remotes and
  local `upstream` branches, then generate architectural indices. Use
  `--dry-run` to preview actions and `--json` when machine-readable output is
  needed.
- `bash scripts/repo-init.sh`: Initialize and clone repositories with upstream
  configuration. Use `--dry-run` to preview actions and `--json` when
  machine-readable output is needed.
- `bash scripts/yaml-duplicate-key-check.sh <yaml-file>`: Detect duplicate YAML
  keys in one or more files. This is read-only and exits non-zero when
  violations are found. Use `--dry-run` to preview checks.

### Available Skills

#### Workspace and Repository Operations

- **interaction-mapper**: Generate architectural maps showing component
  interactions.
  - Example: "map the interactions between components"
- **repo-navigator**: Navigate and search across multiple repositories.
  - Example: "find the VolumeController implementation"
- **verify-setup**: Verify local workspace and toolchain readiness before
  implementation.
  - Example: "verify the workspace prerequisites"

#### Build, API, and Integration Workflows

- **go-import-check**: Check changed Go files against the workspace import
  convention.
  - Example: "check imports for the changed Go files"
- **jenkins-ops**: Safely list, trigger, monitor, inspect, and troubleshoot the
  approved Longhorn Jenkins jobs.
  - Example: "review the regression job parameters"
- **longhorn-build-system**: Provide build-system expertise for Longhorn
  toolchains, validation, packaging, Buildx, and Dapper flows.
  - Example: "build longhorn-manager using the Longhorn build workflow"
- **sync-crd-helm**: Synchronize CRD definitions with Helm charts.
  - Example: "update the Helm chart with the latest CRDs"

#### Documentation and Issue Workflows

- **design-qa-verification-steps**: Draft or review Longhorn issue verification
  steps and manual test plans.
  - Example: "draft verification steps for this issue"
- **longhorn-user-docs**: Assist with Longhorn operational documentation,
  installation, upgrades, settings, and troubleshooting.
  - Example: "update the documentation for this setting"
- **support-bundle-analysis**: Analyze Longhorn support bundles and diagnose
  cluster issues.
  - Example: "analyze this support bundle"
- **ticket-sanitizer**: Validate and sanitize ticket information.
  - Example: "validate this issue description"

#### Quality and Change Safeguards

- **ascii-scanner**: Scan changed files and enforce the ASCII-only policy.
  - Example: "scan the changed files for non-ASCII characters"
- **check-test-diff**: Guard against accidental risky changes to Go test files
  in a diff.
  - Example: "review test-file changes in repo/longhorn-manager"
- **commit-message**: Draft and review Longhorn commit messages according to
  repository requirements.
  - Example: "review this commit message"

#### Jenkins Environment Cautions

Before using `jenkins-ops`, create or update the workspace-root `.env` file:

```bash
JENKINS_URL=https://jenkins.example.com
JENKINS_USER=your-jenkins-user
JENKINS_TOKEN=your-jenkins-api-token
JENKINS_NOTIFY_SLACK_CHANNEL=your-slack-channel-id
JENKINS_SSH_IDENTITY_FILE=~/.ssh/your-private-key
JENKINS_SSH_USER=your-remote-user
```

- `JENKINS_URL`, `JENKINS_USER`, and `JENKINS_TOKEN` are required for Jenkins
  API operations. The token needs Job/Read and Job/Build.
- `JENKINS_NOTIFY_SLACK_CHANNEL` is optional. When it is nonempty, every
  approved job trigger automatically sets `SEND_SLACK_NOTIFICATION=true` and
  passes the channel through `NOTIFY_SLACK_CHANNEL`.
- `JENKINS_SSH_IDENTITY_FILE` and `JENKINS_SSH_USER` are required only for
  job-host SSH troubleshooting.
- Keep `.env` local and never commit or share its contents. Restrict its
  permissions with `chmod 600 .env`.
- Restart the active harness after changing `.env` so new processes inherit the
  updated values.

### Tips for Using Skills

1. **Direct skill invocation**: Mention the skill name in your prompt.
   - "use [skill-name] skill to [task]"
   - "invoke [skill-name] for [purpose]"
2. **Task-based requests**: Describe what you want to accomplish. The active
   harness can select an appropriate skill.
   - Example: "initialize the workspace"
3. **Multiple skills**: Ask for a task that combines their purposes.
   - Example: "initialize the workspace and analyze the architecture"
4. **Skill documentation**: Each skill has documentation in
   `agent-skills/<skill-name>/SKILL.md`.
   - Example: "show me the repo-navigator skill documentation"

## Additional Resources

- **Longhorn Documentation**: https://longhorn.io/docs/
- **GitHub Organization**: https://github.com/longhorn
- **Community**: https://longhorn.io/community/

---

**Note**: This workspace includes `AGENTS.md` policy instructions. Policy files
may be committed locally when needed, but must never be pushed.
