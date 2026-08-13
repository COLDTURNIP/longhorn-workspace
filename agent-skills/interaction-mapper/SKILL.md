---
name: interaction-mapper
description: >
  Use when modifying a CRD schema or gRPC proto definition to assess impact, when a
  K8s resource is stuck in an unexpected state and the responsible controller is unknown,
  or when tracing the call chain between Manager and Instance Manager.
compatibility: opencode
metadata:
  version: "1.0"
  impact: High (Architectural Awareness)
  tags: ["architecture", "crd", "grpc", "interaction", "mapping"]
---

# Skill: interaction-mapper

## Description
While LSP handles code-level symbols, this skill indexes the "glue" of Longhorn's microservices. It identifies which controllers reconcile which CRDs and maps gRPC service definitions to their cross-repo implementation logic.

## When to Use
- **Impact Analysis**: When changing a CRD schema or a gRPC proto definition.
- **Root Cause Analysis**: When a resource state (e.g., Volume 'Faulted') doesn't transition as expected, to find the responsible controller.
- **Onboarding**: When the Agent needs to understand the call chain from Manager to Instance Manager.

## Usage
Run from workspace root:
```bash
bash agent-skills/interaction-mapper/map_interactions.sh
```

> Remotes: The script now logs warnings instead of failing if the workspace lacks an `upstream` remote, so it is safe immediately after cloning.

## Expected Outcomes
- `context/indices/crd-interaction.json`: Map of CRDs to their primary reconciling logic.
- `context/indices/rpc-topology.json`: Map of gRPC services and their cross-repo caller relationships.
