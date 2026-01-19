# Longhorn Multi-Repository Workspace

A comprehensive development workspace for the Longhorn distributed block storage system for Kubernetes, designed for development with **OpenCode plus Oh-My-OpenCode agents**.

## Overview

This workspace provides a unified environment for developing across Longhorn's multiple repositories. Longhorn is a lightweight, reliable, and powerful distributed block storage system designed for Kubernetes.

The workspace integrates AI-powered development tools through OpenCode and Oh-My-OpenCode, providing intelligent assistance for code navigation, repository initialization, build system management, and more.

## Required Toolchain

**For OpenCode + Oh-My-OpenCode:**
- OpenCode extension (AI-powered development assistant)
- Oh-My-OpenCode plugin (provides additional agent design capabilities for OpenCode)

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
    skill/                      (Oh-My-OpenCode AI skills)
      repo-init/                (Repository initialization)
      interaction-mapper/       (Architectural mapping)
      repo-navigator/           (Code navigation)
      longhorn-build-system/    (Build system expertise)
      sync-crd-helm/            (CRD/Helm synchronization)
      ascii-scanner/            (ASCII policy enforcement)
      ticket-sanitizer/         (Ticket validation)
      support-bundle-analysis/  (Diagnostics)
      longhorn-user-docs/       (Documentation assistance)
  repo/                         (all Longhorn repositories)
    repo-list                   (List of repositories to clone - used by repo-init skill)
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
  ticket/                       (task-specific workspace)
```

## Initialization

### Quick Start with AI Agent

The fastest way to initialize the workspace is using the AI agent:

**Initialization Prompt:**
```
init workspace
```

When you provide this prompt to the OpenCode AI agent:
1. The agent automatically invokes the `repo-init` skill
2. All repositories from `repo/repo-list` are cloned into the `repo/` directory
3. Each repository is configured with:
   - `upstream` remote pointing to the official Longhorn repository
   - Local `upstream` branch tracking the upstream default branch (main or master)
4. The agent then invokes `interaction-mapper` to generate architectural indices

**Note:** The `repo-init` skill only sets up upstream remotes. You are responsible for managing your personal fork configuration if you plan to contribute code.

### Manual Initialization (Alternative)

If you prefer manual setup:

```bash
# Clone the workspace repository
git clone https://github.com/your-account/longhorn-workspace.git
cd longhorn-workspace

# Initialize repositories using the repo-init skill
bash .opencode/skill/repo-init/repo_init.sh
```

To add your personal fork to a repository:
```bash
cd repo/[repo-name]
git remote add origin https://github.com/[your-account]/[repo-name]
```

## Working with OpenCode Skills

The workspace includes specialized AI skills under `.opencode/skill/` that automate common development tasks. You can ask the OpenCode agent to use these skills for various operations:

### Available Skills

- **repo-init**: Initialize and clone all repositories with upstream configuration
  - Example: "init workspace" or "use repo-init skill to set up repositories"

- **interaction-mapper**: Generate architectural maps showing component interactions
  - Example: "map the interactions between components" or "use interaction-mapper to analyze the architecture"

- **repo-navigator**: Navigate and search across multiple repositories
  - Example: "use repo-navigator to find VolumeController implementation"

- **longhorn-build-system**: Build system expertise for various toolchains
  - Example: "use longhorn-build-system skill to build longhorn-manager"

- **sync-crd-helm**: Synchronize CRD definitions with Helm charts
  - Example: "use sync-crd-helm to update Helm chart with latest CRDs"

- **ascii-scanner**: Scan and enforce ASCII-only policy
  - Example: "use ascii-scanner to check for non-ASCII characters"

- **ticket-sanitizer**: Validate and sanitize ticket information
  - Example: "use ticket-sanitizer to validate this issue description"

- **support-bundle-analysis**: Analyze Longhorn support bundles
  - Example: "use support-bundle-analysis to diagnose this support bundle"

- **longhorn-user-docs**: Assist with user documentation
  - Example: "use longhorn-user-docs skill to update documentation"

### Tips for Using Skills

1. **Direct skill invocation**: Mention the skill name in your prompt
   - "use [skill-name] skill to [task]"
   - "invoke [skill-name] for [purpose]"

2. **Task-based requests**: Describe what you want to accomplish
   - The agent will automatically select appropriate skills
   - Example: "initialize the workspace" will trigger repo-init

3. **Multiple skills**: The agent can chain multiple skills
   - Example: "init workspace and analyze the architecture" will use repo-init and interaction-mapper

4. **Skill documentation**: Each skill has documentation in `.opencode/skill/[skill-name]/SKILL.md`
   - Example: "show me the repo-init skill documentation"

## Additional Resources

- **Longhorn Documentation**: https://longhorn.io/docs/
- **GitHub Organization**: https://github.com/longhorn
- **Community**: https://longhorn.io/community/

---

**Note**: This workspace includes an `AGENTS.md` file with instructions for AI coding agents. This file should never be committed to any repository - it's workspace-local only.
