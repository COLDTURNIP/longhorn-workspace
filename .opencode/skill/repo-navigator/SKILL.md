---
name: repo-navigator
description: High-level architectural navigator that combines LSP capabilities with pre-generated interaction maps to locate logic across multiple Longhorn repositories.
compatibility: opencode
metadata:
  version: "1.0"
  impact: High (Efficiency)
  tags: ["navigation", "architecture", "lsp", "context-aware"]
---

# Skill: repo-navigator

## Description
This skill acts as the entry point for code exploration. Instead of full-text searching, it consults architectural indices (`crd-interaction.json` and `rpc-topology.json`) to find the "Anchor File" and then uses LSP for fine-grained navigation.

## Reasoning Flow
When asked "Where is the logic for X?", follow this hierarchy:
1. **Identify Category**: Is it a K8s Resource (CRD) or a gRPC Communication (RPC)?
2. **Consult Maps**:
   - If CRD: Query `context/indices/crd-interaction.json`.
   - If RPC: Query `context/indices/rpc-topology.json`.
3. **LSP Exploration**: Once the file is found, use LSP `find-definition` or `find-references` on key symbols like `syncHandler` or `Reconcile`.

## Usage
Run the helper script to query indices:
```bash
# Find controller for a CRD
bash .opencode/skill/repo-navigator/repo_navigator.sh --crd Volume

# Find topology for a gRPC Service
bash .opencode/skill/repo-navigator/repo_navigator.sh --rpc InstanceServiceClient
