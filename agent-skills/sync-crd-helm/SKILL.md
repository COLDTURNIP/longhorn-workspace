---
name: sync-crd-helm
description: >
  Use when API types under longhorn-manager/pkg/apis/ were modified, CI fails with
  "crds.yaml out of sync", or a release requires updating deploy/longhorn.yaml.
metadata:
  repos: ["repo/longhorn-manager", "repo/longhorn"]
  impact: High (Cross-repo API consistency)
---

# Skill: Sync CRD and Helm Workflow

## Description

This skill automates the synchronization between `longhorn-manager` (the API source) and `longhorn` (the packaging target). It ensures that Go struct changes are correctly reflected in the final Helm charts and static YAML manifests.

## When to Use (Trigger)

- **Modified API Types**: You changed files in `@repo/longhorn-manager/pkg/apis/`.
- **Validation Error**: CI fails with "crds.yaml out of sync".
- **Release Prep**: You need to update `@repo/longhorn/deploy/longhorn.yaml` for a new feature.

## Core Command

Execute from workspace root:

```bash
bash agent-skills/sync-crd-helm/sync_crd_helm.sh
```

> The script now only warns if `upstream` remotes are missing or misconfigured so it can run right after cloning the workspace.

## The 3-Stage Logic (Internal Detail)

1. **Manager Stage:** Runs make generate in @repo/longhorn-manager to produce k8s/crds.yaml.
2. **Sync Stage:** Copies crds.yaml to @repo/longhorn/chart/templates/crds.yaml.
3. **Helm Stage:** Runs manifest generation in @repo/longhorn to update deploy/longhorn.yaml.

## Key Files

| Role | Path |
|------|------|
| Source (Go) | @repo/longhorn-manager/pkg/apis/longhorn/v1beta2/*.go |
| Intermediate | @repo/longhorn-manager/k8s/crds.yaml |
| Helm Target | @repo/longhorn/chart/templates/crds.yaml |
| Final Manifest | @repo/longhorn/deploy/longhorn.yaml |

## Troubleshooting

- **Permission Denied:** Ensure Docker, Docker Buildx, and Make are available for `make generate`.
- **ASCII Violation:** If the script fails the ASCII check, inspect the Go comments in the Manager repo for emojis or non-standard symbols.
