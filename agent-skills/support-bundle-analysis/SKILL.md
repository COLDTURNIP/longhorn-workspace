---
name: support-bundle-analysis
description: >
  Use when the user provides a Rancher or Longhorn support bundle and needs root cause
  analysis for cluster issues: volume attachment failures, pod crashes, backing image
  errors, node unavailability, or storage/network problems.
compatibility: opencode
metadata:
  version: "2.0"
  architecture: modular
---

# Support Bundle Analysis

---

## Pre-Analysis Requirements (MANDATORY)

<mandatory_requirements>

<step_1>
<requirement>Bundle Extraction Location</requirement>
<ticket_scope>
If analysis is under `ticket/*`, read `ticket/AGENTS.md` and follow its authoritative per-archive rule. Extract each archive to `logs/extracted/[archive_name_no_ext]/`; if it is already there, use that directory. Do not ask the user to confirm this location.
</ticket_scope>
<outside_ticket_scope>
If analysis is outside `ticket/*`, ask the user to confirm where to extract the support bundle:
- Temporary (recommended): /tmp/sb-analysis-TIMESTAMP
- Custom path: [provide path]
- Already extracted: [provide path]
</outside_ticket_scope>
</step_1>

<step_2>
<requirement>Problem Description (CRITICAL)</requirement>
<critical>Problem-driven analysis is CORE. A usable problem description is mandatory.</critical>
<ticket_scope>
If analysis is under `ticket/*` and `description.md` exists, read and use it as the problem description. Ask the user only if it is absent or insufficient.
</ticket_scope>
<outside_ticket_scope>
If analysis is outside `ticket/*`, use a problem description already supplied by the user when it is sufficient; if not, ask the user to provide one.
</outside_ticket_scope>
<ask_user_when_needed>
Use this prompt only when the applicable description source is absent or insufficient:
Describe the problem:
- What issue/error are you experiencing?
- Which components are affected? (Pod/Node/Storage/Network)
- What symptoms are present?
- What relevant timestamps or events are known?
</ask_user_when_needed>
<failure_mode>Do not proceed to diagnosis without a usable problem description.</failure_mode>
</step_2>

</mandatory_requirements>

<decision_gate>Proceed to Phase 0 only after the applicable extraction-location branch is resolved and a usable problem description is available.</decision_gate>

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

### Decision Tree

```
START
  -> [Scope] Under `ticket/*`: read `ticket/AGENTS.md` and use `logs/extracted/[archive_name_no_ext]/`
             Outside `ticket/*`: ask the user to confirm the extraction location
  -> [Description] Under `ticket/*`: read `description.md` when present; ask only if absent or insufficient
                  Outside `ticket/*`: use supplied details; ask only if absent or insufficient
  -> [Phase 0] Classify -> [Phase 1] Structure
  -> [Phase 2-3] READ @diagnostic-flows.md
  -> [Phase 4] READ @patterns-library.md -> END
```

### Quick Links

**Diagnosis**: @diagnostic-flows.md#pod-diagnosis | #node-diagnosis | #storage-diagnosis | #network-diagnosis  
**Patterns**: @patterns-library.md#patterns-library | #examples | #quick-reference  
**Methods**: @patterns-library.md#timeline-reconstruction | #5-whys-method | #evidence-based-analysis

<when_to_read>
<diagnostic_flows>Phase 2-3: Deep diagnosis needed</diagnostic_flows>
<patterns_library>Phase 4: Root cause analysis or pattern reference needed</patterns_library>
</when_to_read>

