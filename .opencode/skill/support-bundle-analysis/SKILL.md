---
name: support-bundle-analysis
description: Systematic problem-driven approach to analyze Rancher/Longhorn support bundles
compatibility: opencode
metadata:
  version: "2.0"
  architecture: modular
---

# Support Bundle Analysis

## What I do

Systematic methodology to analyze Rancher/Longhorn support bundles for root cause identification through problem-driven multi-layer diagnosis (K8s resources, pod logs, node system logs).

## When to use me

Troubleshooting cluster issues: backing image download, volume attachment, pod crashes, node unavailability, storage/network problems.

---

## Pre-Analysis Requirements (MANDATORY)

<mandatory_requirements>

<confirmation_1>
<requirement>Bundle Extraction Location</requirement>
<ask_user>
Where should I extract the support bundle?
- Temporary (recommended): /tmp/sb-analysis-TIMESTAMP
- Custom path: [provide path]
- Already extracted: [provide path]
</ask_user>
<failure_mode>CANNOT proceed without confirmed bundle location</failure_mode>
</confirmation_1>

<confirmation_2>
<requirement>Problem Description (CRITICAL)</requirement>
<critical>Problem-driven analysis is CORE. Without this, analysis cannot proceed.</critical>
<ask_user>
Describe the problem:
- What issue/error are you experiencing?
- Which components affected? (Pod/Node/Storage/Network)
- What symptoms?
- Relevant timestamps/events?

Example: "Backing image 'ubuntu' download stuck at 0% after network disconnection"
</ask_user>
<failure_mode>CANNOT proceed without problem description</failure_mode>
</confirmation_2>

</mandatory_requirements>

<blocking>DO NOT proceed until BOTH confirmations completed</blocking>

---

## Phase 0: Problem Understanding

<problem_classification>
<pod_issues>CrashLoopBackOff, ImagePullBackOff, Pending, OOMKilled -> @diagnostic-flows.md#pod-diagnosis</pod_issues>
<node_issues>NotReady, MemoryPressure, DiskPressure -> @diagnostic-flows.md#node-diagnosis</node_issues>
<storage_issues>PVC Pending, Volume mount failures, I/O errors -> @diagnostic-flows.md#storage-diagnosis</storage_issues>
<network_issues>DNS failures, Connection timeouts -> @diagnostic-flows.md#network-diagnosis</network_issues>
</problem_classification>

Extract from user's problem description: Problem type, Affected resources, Symptoms, Timestamps

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

### Decision Tree

```
START -> [Pre-Analysis] Confirm bundle + problem -> [Phase 0] Classify -> [Phase 1] Structure
  -> [Phase 2-3] READ @diagnostic-flows.md -> [Phase 4] READ @patterns-library.md -> END
```

### Quick Links

**Diagnosis**: @diagnostic-flows.md#pod-diagnosis | #node-diagnosis | #storage-diagnosis | #network-diagnosis  
**Patterns**: @patterns-library.md#patterns-library | #examples | #quick-reference  
**Methods**: @patterns-library.md#timeline-reconstruction | #5-whys-method | #evidence-based-analysis

<when_to_read>
<diagnostic_flows>Phase 2-3: Deep diagnosis needed</diagnostic_flows>
<patterns_library>Phase 4: Root cause analysis or pattern reference needed</patterns_library>
</when_to_read>

---

**Commands**: Standard Unix (grep, find, tail, cat) preferred for compatibility  
**Next**: Complete Pre-Analysis + Phase 0-1, then READ @diagnostic-flows.md for Phase 2-3

---
Architecture 2.0 | Updated 2026-01-16
