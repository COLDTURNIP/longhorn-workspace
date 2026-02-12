# Longhorn Multi-Repository Workspace

A comprehensive development workspace for the Longhorn distributed block storage system for Kubernetes, designed for development with **OpenCode plus Oh-My-OpenCode agents**.

## Overview

This workspace provides a unified environment for developing across Longhorn's multiple repositories. Longhorn is a lightweight, reliable, and powerful distributed block storage system designed for Kubernetes.

The workspace integrates AI-powered development tools through OpenCode and Oh-My-OpenCode, providing intelligent assistance for code navigation, repository initialization, build system management, and more.

**Note:** Though the workspace is optimized for use with OpenCode and Oh-My-OpenCode agents, the `AGENTS**.md` files, skills, and commands, are still available for other agentic development tools like Codex and Claude Code. Just create a soft link from `AGENTS.md` and `.opencode` to the appropriate agent instruction file for your tool of choice.

## TL;DR: Quick Start

Follow [QUICKSTART.md](QUICKSTART.md) for a quick setup guide to get started with OpenCode and the Longhorn workspace.

## Required Toolchain

**For OpenCode + Oh-My-OpenCode:**

- [OpenCode](https://opencode.ai/docs) (AI-powered development assistant)
- [Oh-My-OpenCode](https://github.com/code-yeongyu/oh-my-opencode) plugin (provides additional agent design capabilities for OpenCode)

**For Longhorn Development:**

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
  AGENTS.md                     (AI agent instructions - not for commit)
  .opencode/                    (local development state)
    commands/                   (OpenCode slash commands)
      init-workspace.md         (/init-workspace command template)
      init-workspace.sh         (Executable command script)
      repo-init.md              (/repo-init command template)
      repo-init.sh              (Executable command script)
      yaml-duplicate-key-check.md   (/yaml-duplicate-key-check command template)
      yaml-duplicate-key-check.sh   (Executable command script)
    skills/                     (AI skills)
      ascii-scanner/            (ASCII policy enforcement)
      check-test-diff/          (Go test diff guard)
      interaction-mapper/       (Architectural mapping)
      longhorn-build-system/    (Build system expertise)
      longhorn-user-docs/       (Documentation assistance)
      plan-gate/                (Plan contract linting)
      repo-navigator/           (Code navigation)
      support-bundle-analysis/  (Diagnostics)
      sync-crd-helm/            (CRD/Helm synchronization)
      ticket-sanitizer/         (Ticket validation)
      verify-setup/             (Workspace setup verification)
  repo/                         (all Longhorn repositories)
    repo-list                   (List of repositories to clone - used by /init-workspace command)
    backing-image-manager/      (Team-owned component)
    cli/                        (Team-owned component)
    longhorn-engine/            (Team-owned component)
    longhorn-instance-manager/  (Team-owned component)
    longhorn-manager/           (Team-owned component)
    longhorn-share-manager/     (Team-owned component)
    longhorn-spdk-engine/       (Team-owned component)
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
    longhorn/                   (Packaging - Helm chart)
    longhorn-ui/                (Packaging - Frontend)
    longhorn-tests/             (Integration tests)
    dep-versions/               (Version coordination)
  ticket/                       (task-specific workspace for case studies)
```

## Initialization

Clone the workspace repository.

```bash
git clone https://github.com/COLDTURNIP/longhorn-workspace.git
cd longhorn-workspace
```

### Starts with AI Agent

The fastest way to initialize the workspace is using the AI agent. Launch OpenCode in the root of the workspace:

```bash
opencode .
```

**Initialization Prompt:**

```
initialize the workspace
```

Or, use a direct command explicitly:

```
/init-workspace
```

When you provide this prompt to the AI agent:

1. The agent automatically runs the `/init-workspace` command to set up the Git source code repositories based on the list in `repo/repo-list`
2. All component source repositories from `repo/repo-list` are cloned into the `repo/` directory
3. Each repository is configured with:
   - `upstream` remote pointing to the official Longhorn repository
   - Local `upstream` branch tracking the upstream default branch (main or master)
4. The command runs index generation (currently `interaction-mapper`) under `context/indices/` so the agent can understand cross-repo architecture for navigation and implementation tasks.

**Note:** The `/init-workspace` command sets up upstream remotes and local upstream branches. You are responsible for managing your personal fork configuration if you plan to contribute code.

### Manual Initialization (Alternative)

If you prefer manual setup:

```bash
# Initialize repositories using the /init-workspace command
bash .opencode/commands/init-workspace.sh --dry-run  # Preview actions
bash .opencode/commands/init-workspace.sh            # Execute (default)
```

To add your personal fork to a repository:

```bash
cd repo/[repo-name]
git remote add origin https://github.com/[your-account]/[repo-name]
git fetch origin
```

## Working with Skills

The workspace includes specialized AI skills under `.opencode/skills/` that automate common development tasks. You can ask the agent to use these skills for various operations:

### Available Commands

- **/init-workspace**: Initialize all repositories from `repo/repo-list`, configure `upstream` remotes and local `upstream` branches, then generate architectural indices (execute by default; use `--dry-run` and `--json` as needed)
  - Example: "/init-workspace --dry-run" or "run /init-workspace to prepare this workspace"

- **/repo-init**: Initialize and clone all repositories with upstream configuration (execute by default; use `--dry-run` and `--json` as needed)
  - Example: "/repo-init --dry-run" or "run /repo-init when you only want repository setup"

- **/yaml-duplicate-key-check**: Detect duplicate YAML keys in one or more files (read-only; exits non-zero when violations are found)
  - Example: "/yaml-duplicate-key-check repo/longhorn/chart/values.yaml" or "run /yaml-duplicate-key-check --dry-run repo/longhorn/chart/values.yaml"

### Available Skills

- **ascii-scanner**: Scan and enforce ASCII-only policy
  - Example (repo/\*): "use ascii-scanner on changed files under repo/<repo-name>, excluding vendor/generated"
  - Example (non-repo): "use ascii-scanner to check specific files outside repo/"

- **check-test-diff**: Guard against accidental risky changes to Go test files in git diff
  - Example: "use check-test-diff to review test-file changes in repo/longhorn-manager"

- **interaction-mapper**: Generate architectural maps showing component interactions
  - Example: "map the interactions between components" or "use interaction-mapper to analyze the architecture"

- **longhorn-build-system**: Build system expertise for various toolchains
  - Example: "use longhorn-build-system skill to build longhorn-manager"

- **longhorn-user-docs**: Assist with user documentation
  - Example: "use longhorn-user-docs skill to update documentation"

- **plan-gate**: Lint execution plans for required step contract fields
  - Example: "use plan-gate to validate .sisyphus/plans/my-plan.md"

- **repo-navigator**: Navigate and search across multiple repositories
  - Example: "use repo-navigator to find VolumeController implementation"

- **support-bundle-analysis**: Analyze Longhorn support bundles
  - Example: "use support-bundle-analysis to diagnose this support bundle"

- **sync-crd-helm**: Synchronize CRD definitions with Helm charts
  - Example: "use sync-crd-helm to update Helm chart with latest CRDs"

- **ticket-sanitizer**: Validate and sanitize ticket information
  - Example: "use ticket-sanitizer to validate this issue description"

- **verify-setup**: Verify local workspace/toolchain readiness before implementation
  - Example: "use verify-setup to validate workspace prerequisites"

### Tips for Using Skills

1. **Direct skill invocation**: Mention the skill name in your prompt
   - "use [skill-name] skill to [task]"
   - "invoke [skill-name] for [purpose]"

2. **Task-based requests**: Describe what you want to accomplish
   - The agent will automatically select appropriate automation
   - Example: "initialize the workspace" will trigger `/init-workspace`

3. **Multiple skills**: The agent can chain multiple skills
   - Example: "init workspace and analyze the architecture" will run `/init-workspace`

4. **Skill documentation**: Each skill has documentation in `.opencode/skills/[skill-name]/SKILL.md`
   - Example: "show me the repo-navigator skill documentation"

## Additional Resources

- **Longhorn Documentation**: https://longhorn.io/docs/
- **GitHub Organization**: https://github.com/longhorn
- **Community**: https://longhorn.io/community/

---

**Note**: This workspace includes an `AGENTS.md` file with instructions for AI coding agents. This file should never be committed to any repository - it's workspace-local only.
