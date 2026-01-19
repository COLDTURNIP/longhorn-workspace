---
name: interaction-mapper
description: Maps high-level architectural relationships, including K8s CRD-to-Controller watches and cross-repo gRPC communication flows.
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
bash .opencode/skill/interaction-mapper/map_interactions.sh
```

## Expected Outcomes
- `context/indices/crd-interaction.json`: Map of CRDs to their primary reconciling logic.
- `context/indices/rpc-topology.json`: Map of gRPC services and their cross-repo caller relationships.
