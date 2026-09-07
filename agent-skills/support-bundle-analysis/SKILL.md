---
name: support-bundle-analysis
description: >
  Use when the user provides a Rancher or Longhorn support bundle and needs root cause
  analysis for cluster issues: volume attachment failures, pod crashes, backing image
  errors, node unavailability, or storage/network problems.
metadata:
  version: "2.0"
  architecture: modular
---

# Support Bundle Analysis

---

## Pre-Analysis Requirements (MANDATORY)

Resolve the extraction location before starting Phase 0:

- **Under `ticket/*`**: Read `ticket/AGENTS.md` and follow its per-archive rule.
  Extract each archive to `logs/extracted/<archive-name-without-extension>/`.
  Reuse that directory when it already exists. Keep archives isolated; never
  merge bundles or place extracted contents directly in `logs/`.
- **Outside `ticket/*`**: Use an explicit destination supplied by the user when
  it resolves as an absolute or workspace-relative path. Use a supplied
  already-extracted directory when it exists. Ask for a location only when no
  destination or extracted directory is specified, or the supplied path cannot
  be resolved.

Require a usable problem description before diagnosis:

- Under `ticket/*`, read `description.md` when present and ask only when it is
  absent or insufficient.
- Outside `ticket/*`, use the user's supplied description when sufficient; ask
  otherwise.
- Capture the issue or error, affected components or resources, symptoms, and
  relevant timestamps when known.

When a description is missing or insufficient, ask:

```text
Describe the problem:
- What issue/error are you experiencing?
- Which components are affected? (Pod/Node/Storage/Network)
- What symptoms are present?
- What relevant timestamps or events are known?
```

Proceed to Phase 0 only after the extraction location is resolved and a usable
problem description is available.

---

## Phase 0: Problem Understanding

<problem_classification>
<pod_issues>CrashLoopBackOff, ImagePullBackOff, Pending, OOMKilled -> @diagnostic-flows.md#pod-diagnosis</pod_issues>
<node_issues>NotReady, MemoryPressure, DiskPressure -> @diagnostic-flows.md#node-diagnosis</node_issues>
<storage_issues>PVC Pending, Volume mount failures, I/O errors -> @diagnostic-flows.md#storage-diagnosis</storage_issues>
<network_issues>DNS failures, Connection timeouts -> @diagnostic-flows.md#network-diagnosis</network_issues>
</problem_classification>

Extract from the problem description: Problem type, Affected resources, Symptoms, Timestamps

---

## Phase 1: Bundle Structure Overview

Key directories:
```
supportbundle_*/
  yamls/cluster/kubernetes/          - nodes.yaml, events.yaml, persistentvolumes.yaml
  yamls/namespaced/[ns]/kubernetes/  - pods.yaml, services.yaml, pvcs.yaml
  logs/[ns]/[pod]/                   - Container logs
  nodes/[node]/
    hostinfos/                       - hostinfo, proc_mounts
    logs/                            - dmesg.log, kubelet.log, messages
```

Priority files by problem type:

| Problem | Primary Files | Key Search Terms |
|---------|---------------|------------------|
| Pod | pods.yaml, logs/*/*.log | CrashLoopBackOff, exitCode, restartCount |
| Node | nodes.yaml, nodes/*/logs/*.log | NotReady, MemoryPressure, DiskPressure |
| Storage | pvs.yaml, pvcs.yaml, proc_mounts | Pending, MountFailed, I/O error |
| Network | services.yaml, endpoints.yaml, dmesg.log | DNS, timeout, unreachable |

---

## Resource Map

| Module | Load When | Contains |
|--------|-----------|----------|
| **SKILL.md** (HERE) | Always (Entrypoint) | Pre-Analysis + Phase 0-1 + Navigation |
| **@diagnostic-flows.md** | Phase 2-3 | Quick Assessment, Deep Diagnosis, Commands Toolbox |
| **@patterns-library.md** | Phase 4 | Timeline, 5 Whys, Error Patterns, Examples |

### Quick Links

**Diagnosis**: @diagnostic-flows.md#pod-diagnosis | #node-diagnosis | #storage-diagnosis | #network-diagnosis
**Patterns**: @patterns-library.md#patterns-library | #examples | #quick-reference
**Methods**: @patterns-library.md#timeline-reconstruction | #5-whys-method | #evidence-based-analysis

<when_to_read>
<diagnostic_flows>Phase 2-3: Deep diagnosis needed</diagnostic_flows>
<patterns_library>Phase 4: Root cause analysis or pattern reference needed</patterns_library>
</when_to_read>
