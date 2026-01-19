# Longhorn Multi-Repository Workspace

A comprehensive development workspace for the Longhorn distributed block storage system for Kubernetes.

## Overview

This workspace provides a unified environment for developing across Longhorn's multiple repositories. Longhorn is a lightweight, reliable, and powerful distributed block storage system designed for Kubernetes.

### What is Longhorn?

Longhorn is a cloud-native distributed block storage solution that provides:
- Highly available persistent storage for Kubernetes
- Backup and disaster recovery capabilities
- Volume snapshots and cloning
- Cross-cluster volume migration
- Storage tiering with backing images

## Workspace Structure

The workspace is organized as follows:

```
workspace-root/
  README.md                     (this file)
  AGENTS.md                     (AI agent instructions - not for commit)
  .opencode/                    (local development state)
  repo/                         (all Longhorn repositories)
    [component repositories]
  ticket/                       (task-specific workspace)
```

### Repository Organization

Repositories are organized under the `repo/` directory by category:

#### Core Components (Team-Owned)
- **longhorn-manager** - Main orchestration and API server
- **longhorn-engine** - Storage engine implementation
- **longhorn-instance-manager** - Instance lifecycle management
- **backing-image-manager** - Backing image lifecycle management
- **longhorn-share-manager** - Shared volume management
- **longhorn-spdk-engine** - SPDK-based storage engine
- **cli** - Command-line interface

#### Shared Libraries
- **types** - CRD definitions and API types (Foundation layer)
- **go-common-libs** - Shared Go utilities and helpers
- **backupstore** - Backup storage abstraction
- **go-iscsi-helper** - iSCSI protocol helpers
- **go-spdk-helper** - SPDK abstraction layer
- **sparse-tools** - Sparse file handling utilities

#### CSI Sidecars (Upstream)
- **csi-attacher** - Volume attachment controller
- **csi-node-driver-registrar** - Node driver registration
- **csi-provisioner** - Volume provisioning
- **csi-resizer** - Volume resizing
- **csi-snapshotter** - Snapshot management
- **livenessprobe** - Driver liveness probe

#### Integration & Packaging
- **longhorn** - Helm chart and deployment manifests
- **longhorn-ui** - Frontend web dashboard
- **longhorn-tests** - End-to-end test suite

#### Version Management
- **dep-versions** - Dependency version coordination

## Getting Started

### Prerequisites

- Git
- Docker (for Dapper-based builds)
- Go 1.20+ (for native Go development)
- Node.js and npm (for longhorn-ui)
- Python 3.x (for longhorn-tests)
- Make
- Helm (for chart validation)

### Initial Setup

1. **Clone the workspace repository**:
   ```bash
   git clone https://github.com/your-account/longhorn-workspace.git
   cd longhorn-workspace
   ```

2. **Initialize repositories**:
   The workspace uses a `repo/repo-list` file as the source of truth for required repositories. You'll need to clone the repositories listed there into the `repo/` directory.

3. **Configure Git remotes**:
   For each repository you plan to contribute to:
   ```bash
   cd repo/[repo-name]
   
   # Add upstream (canonical Longhorn repository)
   git remote add upstream https://github.com/longhorn/[repo-name]
   
   # Add origin (your personal fork)
   git remote add origin https://github.com/[your-account]/[repo-name]
   
   # Verify configuration
   git remote -v
   ```

## Development Workflow

### Creating a Feature Branch

Different repositories use different default branches (`main` or `master`). Always detect dynamically:

```bash
cd repo/[repo-name]

# Fetch latest upstream changes
git fetch upstream

# Detect default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/upstream/HEAD | sed 's@refs/remotes/upstream/@@')

# Create feature branch from upstream
git switch -c 12345-feature-description upstream/$DEFAULT_BRANCH
```

### Branch Naming Convention

Use the format: `[story-id]-[brief-description]`

Examples:
- `12345-fix-volume-attach`
- `6789-add-backup-validation`
- `54321-improve-csi-error-handling`

### Making Changes

1. **Make your changes** in the feature branch
2. **Build and test** your changes (see Build Commands below)
3. **Commit** with clear, descriptive messages
4. **Rebase** onto latest upstream before pushing:
   ```bash
   git fetch upstream
   git rebase upstream/$DEFAULT_BRANCH
   ```
5. **Push** to your fork:
   ```bash
   git push -u origin 12345-feature-description
   ```
6. **Create Pull Request** on GitHub from your fork to upstream

## Build Commands

### Native Longhorn Components (Dapper-based)

For repositories like longhorn-manager, longhorn-engine, etc.:

```bash
cd repo/[repo-name]

# Build
make

# Test
make test

# Validation (lint, vet, etc.)
make validate

# Combined workflow
make clean && make && make test && make validate
```

**Important**: Always use `make` - do NOT run `go build`, `go test`, or `docker build` directly. The Makefile invokes Dapper for consistent containerized builds.

### Frontend (longhorn-ui)

```bash
cd repo/longhorn-ui

npm install
npm run build
npm test
```

### Helm Chart (longhorn)

```bash
cd repo/longhorn

helm lint chart/
```

### E2E Tests (longhorn-tests)

```bash
cd repo/longhorn-tests

# Follow repository-specific instructions
pytest  # or custom test runner
```

## Quality Standards

### Code Standards

1. **ASCII-Only**: All code, comments, and documentation must use only ASCII characters (0x00-0x7F)
   - No Unicode, emoji, or special characters
   - English language only

2. **Minimal Changes**: Keep changes focused and minimal
   - Only modify what's necessary for the feature/fix
   - Avoid refactoring unrelated code

3. **Clean Dependencies**: Before submitting PR
   - Remove local `go.mod` replace directives
   - Run `go mod tidy`
   - Ensure no local paths remain

### Pre-Pull Request Checklist

Before submitting a PR, verify:

- [ ] **ASCII-safe**: No non-ASCII characters in modified files
  ```bash
  git diff --name-only | xargs -I {} sh -c 'grep -P -n "[^\x00-\x7F]" {} || echo "{}: [OK]"'
  ```

- [ ] **Clean Go modules**: No local replace directives
  ```bash
  grep "replace" go.mod  # Should return nothing or approved directives only
  go mod tidy
  ```

- [ ] **No AGENTS.md staged**: Workspace files not in commit
  ```bash
  git status | grep AGENTS.md  # Should return nothing
  ```

- [ ] **Builds pass**: Build completes successfully
  ```bash
  make clean && make && make test && make validate
  ```

## Dependency Hierarchy

Understanding the dependency hierarchy helps predict impact:

```
Foundation
  |
  v
types (CRD definitions)
  |
  v
Utilities
  |
  v
go-common-libs
  |
  v
Helpers
  |
  v
backupstore, go-iscsi-helper, go-spdk-helper, sparse-tools
  |
  v
Components
  |
  v
longhorn-engine, longhorn-spdk-engine
  |
  v
Orchestration
  |
  v
longhorn-instance-manager
  |
  v
Controllers
  |
  v
longhorn-manager, longhorn-share-manager
  |
  v
Utilities & CLI
  |
  v
backing-image-manager, cli
  |
  v
Packaging
  |
  v
longhorn (Helm), longhorn-ui, longhorn-tests
```

**Impact Rule**: When modifying lower-layer repositories (types, go-common-libs), upper-layer repositories will need to update their `go.mod` dependencies.

## Common Tasks

### Finding Code

Use workspace-relative paths from the workspace root:

```bash
# Good: workspace-relative
repo/longhorn-manager/controller/volume_controller.go

# Bad: absolute paths
/home/user/workspace/repo/longhorn-manager/...
```

### Searching Across Repositories

```bash
# Find files by pattern
find repo/ -name "*.go" -type f | grep volume

# Search for code patterns
grep -r "VolumeController" repo/longhorn-manager/

# Search across all repos
grep -r "BackingImage" repo/*/
```

### Working with Local Dependencies

During development, you can use local replace directives:

```go
// In go.mod
replace github.com/longhorn/types => ../types
```

**Remember**: Remove all local replaces before submitting PR!

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Build fails: `dapper: not found` | Use `make` instead of `go build` directly |
| Build fails: `go: cannot find module` | Run `go mod tidy` |
| Can't push to upstream | Push to `origin` (your fork), not `upstream` |
| Non-ASCII character error | Find and fix: `grep -P -n '[^\x00-\x7F]' filename` |
| AGENTS.md in git status | Remove: `git reset AGENTS.md` |

### Getting Help

- **Documentation**: Check repository-specific README files
- **Issues**: Search GitHub issues in the specific repository
- **Community**: Join Longhorn Slack or community forums
- **Design Docs**: Review design documents in `repo/longhorn/`

## Best Practices

### Code Investigation

When investigating code:
1. **Map first**: Identify which CRD, Controller, or Service is involved
2. **Understand flow**: Trace the path from API call to implementation
3. **Check dependencies**: Understand which libraries are used
4. **Review tests**: Look at existing tests for usage examples

### Pull Requests

1. **Keep focused**: One feature or fix per PR
2. **Write tests**: Add tests for new functionality
3. **Update docs**: Update relevant documentation
4. **Clean commits**: Use clear commit messages
5. **Rebase regularly**: Keep your branch up to date with upstream

### Testing

1. **Test locally first**: Always test before pushing
2. **Run relevant tests**: Focus on affected areas
3. **Check integration**: For library changes, test dependent components
4. **Validate builds**: Ensure clean builds across affected repositories

## Path Conventions

Always use workspace-relative paths in documentation and references:

**Correct**:
```
repo/longhorn-manager
repo/types/pkg/apis/longhorn.io/
```

**Incorrect**:
```
/home/user/workspace/repo/longhorn-manager
./repo/types
C:/Users/Developer/workspace/...
```

## Contributing

1. Fork the relevant repository under your GitHub account
2. Clone into the workspace `repo/` directory
3. Create feature branch from upstream default branch
4. Make changes following quality standards
5. Test thoroughly
6. Submit PR to upstream repository

## Additional Resources

- **Longhorn Documentation**: https://longhorn.io/docs/
- **GitHub Organization**: https://github.com/longhorn
- **Community**: https://longhorn.io/community/

## License

Longhorn is licensed under the Apache License 2.0. See individual repositories for license details.

---

**Note**: This workspace includes an `AGENTS.md` file with instructions for AI coding agents. This file should never be committed to any repository - it's workspace-local only.
