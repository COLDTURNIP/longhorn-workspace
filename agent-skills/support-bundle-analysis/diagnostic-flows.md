# Diagnostic Flows Module

**Prerequisites**: You must have completed:
- Pre-Analysis Requirements (SKILL.md)
- Phase 0: Problem Classification (SKILL.md)
- Phase 1: Bundle Structure Overview (SKILL.md)

**This Module Contains**: Phase 2-3 diagnostic procedures and commands toolbox

---

## Phase 2: Quick Assessment

### Problem-Driven Targeted Scanning

**PRINCIPLE**: Do NOT scan all resources. Use problem description to guide investigation.

### For Pod Problems {#pod-quick-scan}

**Target files**:
- `yamls/[namespace]/kubernetes/pods.yaml`
- `logs/[namespace]/[pod-name]/*.log`

**Quick checks**:
1. Pod status (phase field)
2. Restart count
3. Last terminated reason and exit code
4. Container log error patterns

**Quick commands**:
```bash
# Find problematic pods
grep -l "CrashLoopBackOff\|ImagePullBackOff\|Pending\|Failed" yamls/*/kubernetes/pods.yaml

# Check specific pod status
grep -A 20 "name: <pod-name>" yamls/[namespace]/kubernetes/pods.yaml

# Search for errors in logs
grep -i "error\|fail\|panic" logs/[namespace]/[pod-name]/*.log
```

### For Node Problems {#node-quick-scan}

**Target files**:
- `yamls/cluster/kubernetes/nodes.yaml`
- `nodes/[node-name]/logs/messages`
- `nodes/[node-name]/logs/dmesg.log`

**Quick checks**:
1. Node conditions (Ready, MemoryPressure, DiskPressure)
2. Node system logs for errors
3. Kernel logs for hardware issues

**Quick commands**:
```bash
# Find NotReady nodes
grep -l "NotReady\|Unknown" yamls/cluster/kubernetes/nodes.yaml

# Check specific node status
grep -A 30 "name: <node-name>" yamls/cluster/kubernetes/nodes.yaml

# Search node system logs (last 200 lines)
tail -200 nodes/[node-name]/logs/messages

# Search kernel errors
grep -i "error\|bug\|hardware" nodes/[node-name]/logs/dmesg.log
```

### For Storage Problems {#storage-quick-scan}

**Target files**:
- `yamls/[namespace]/kubernetes/persistentvolumeclaims.yaml`
- `yamls/cluster/kubernetes/persistentvolumes.yaml`
- `nodes/[node-name]/hostinfos/proc_mounts`

**Quick checks**:
1. PVC phase and conditions
2. PV phase and status
3. Mount status

**Quick commands**:
```bash
# Find pending PVCs
grep -A 10 "phase: Pending" yamls/*/kubernetes/persistentvolumeclaims.yaml

# Check PV status
grep -A 20 "name: <pv-name>" yamls/cluster/kubernetes/persistentvolumes.yaml

# Check mount points on node
grep "<volume-name>" nodes/[node-name]/hostinfos/proc_mounts
```

### For Network Problems {#network-quick-scan}

**Target files**:
- `yamls/[namespace]/kubernetes/services.yaml`
- `yamls/[namespace]/kubernetes/endpoints.yaml`
- `nodes/[node-name]/logs/dmesg.log`

**Quick checks**:
1. Service selector matches
2. Endpoints ready
3. Kernel network errors

---

## Phase 3: Deep Diagnosis

### Multi-Layer Analysis Approach

**Diagnostic Layers**:
1. Application Layer - Container logs
2. Container Layer - Pod status, restarts
3. K8s Layer - Events, resources
4. Node Layer - Kubelet, system, kernel logs
5. Hardware Layer - dmesg, hardware errors

---

### Pod Problem Diagnosis Flow {#pod-diagnosis}

```
For each abnormal Pod:
  |
  +-- Step 1: Read Pod definition
  |     File: yamls/[namespace]/kubernetes/pods.yaml
  |     Extract: nodeName, image, resources.limits, restartCount, lastState, exitCode
  |
  +-- Step 2: Read container logs
  |     File: logs/[namespace]/[pod]/[container].log
  |     File: logs/[namespace]/[pod]/[container].log.1 (if restartCount > 0)
  |     Search: error patterns, stack traces, exceptions
  |
  +-- Step 3: Read node system logs
  |     From Step 1 nodeName, check:
  |     - nodes/[node-name]/logs/kubelet.log
  |       Search: "Failed to start container", "Volume.*failed", "Unable to mount"
  |     - nodes/[node-name]/logs/messages
  |       Search: "OOM killer", "I/O error", systemd failures
  |     - nodes/[node-name]/logs/dmesg.log
  |       Search: Kernel errors, hardware failures
  |
  +-- Step 4: Pattern matching
  |     Combine pod logs and node system logs to identify root cause
  |
  +-- Step 5: Correlation analysis
        Check related resources: PVCs, Services, ConfigMaps/Secrets
```

#### Common Pod Problem Patterns

**CrashLoopBackOff**:
- Check exit code: 1 (app error), 127 (cmd not found), 137 (OOMKilled), 139 (segfault)
- Read container logs for startup errors
- Check resource limits
- Verify liveness/readiness probes

**OOMKilled**:
- Check `spec.containers[].resources.limits.memory`
- Check `nodes/[node]/hostinfos/hostinfo` for node memory
- Search `grep "OOM killer" nodes/*/logs/messages`

**ImagePullBackOff**:
- Verify image name and tag in pod spec
- Check imagePullSecrets
- Check network connectivity from node

**Pending**:
- Check scheduler events: `yamls/*/kubernetes/events.yaml`
- Check node resources vs pod requests
- Check node selectors, taints, tolerations
- Check PVC binding status

---

### Node Problem Diagnosis Flow {#node-diagnosis}

```
For each abnormal Node:
  |
  +-- Step 1: Check node definition
  |     File: yamls/cluster/kubernetes/nodes.yaml
  |     Check: conditions (Ready, KubeletReady, NetworkUnavailable)
  |           allocatable vs capacity
  |
  +-- Step 2: Analyze Kubelet logs
  |     File: nodes/[node-name]/logs/kubelet.log
  |     Search: "Unable to update node status"
  |             "PLEG unhealthy"
  |             "Failed to start container"
  |             "Volume mount failed"
  |             "Disk pressure", "Memory pressure"
  |
  +-- Step 3: Analyze system logs
  |     File: nodes/[node-name]/logs/messages
  |     Search: "OOM killer"
  |             "I/O error"
  |             "segfault"
  |             systemd service failures
  |
  +-- Step 4: Analyze kernel logs
  |     File: nodes/[node-name]/logs/dmesg.log
  |     Search: "BUG:", "Call Trace"
  |             "Hardware Error", "MCE"
  |             "I/O error"
  |             Network errors
  |
  +-- Step 5: Check node resource info
  |     File: nodes/[node-name]/hostinfos/hostinfo
  |     Check: OS version, kernel version, CPU, memory
  |
  +-- Step 6: Check node processes
  |     File: nodes/[node-name]/hostinfos/processes_info
  |     Analyze: High CPU/memory processes, zombie processes
  |
  +-- Step 7: Synthesize findings
        Combine all layers to determine root cause
```

#### Common Node Problem Patterns

**NotReady - MemoryPressure**:
- Check node allocatable vs capacity
- Check pod memory requests on node
- Search for OOM killer events
- Analyze high memory processes

**NotReady - DiskPressure**:
- Check disk usage in hostinfo
- Search `grep "No space left" nodes/*/logs/messages`
- Search `grep "I/O error" nodes/*/logs/dmesg.log`

**NotReady - NetworkUnavailable**:
- Check CNI configuration in kubelet logs
- Check network interface status
- Check DNS resolution

**NotReady - KubeletNotReady**:
- Check kubelet logs for "PLEG unhealthy"
- Check container runtime errors
- Check systemd service status

---

### Storage Problem Diagnosis Flow {#storage-diagnosis}

```
For storage-related issues:
  |
  +-- Step 1: Check PVC status
  |     File: yamls/[namespace]/kubernetes/persistentvolumeclaims.yaml
  |     Check: phase, conditions
  |
  +-- Step 2: Check PV status
  |     File: yamls/cluster/kubernetes/persistentvolumes.yaml
  |     Check: phase, claimRef, nodeAffinity
  |
  +-- Step 3: Identify affected node
  |     From PV spec.nodeAffinity
  |
  +-- Step 4: Check node mount info
  |     File: nodes/[node-name]/hostinfos/proc_mounts
  |     Search: PV device path, mount status, filesystem type
  |
  +-- Step 5: Check node system logs
  |     File: nodes/[node-name]/logs/kubelet.log
  |     Search: "MountVolume.*failed"
  |             "Unable to mount"
  |             "Volume.*not found"
  |     File: nodes/[node-name]/logs/messages
  |     Search: "I/O error", "Device not ready"
  |     File: nodes/[node-name]/logs/dmesg.log
  |     Search: "EXT4-fs error", "XFS error", "device.*hung"
  |
  +-- Step 6: Check external bundle (if using Longhorn)
        File: external/longhorn-support-bundle-*.zip
        Check: volume and engine status
```

#### Common Storage Problem Patterns

**PVC Pending - No PV Available**:
- Check StorageClass configuration
- Check for existing PVs
- Check provisioner logs

**PVC Pending - Volume Binding Failed**:
- Check PV claimRef (already bound?)
- Check PV nodeAffinity (node match?)
- Check AccessMode compatibility

**Volume Mount Failed**:
- Check device availability
- Check filesystem type
- Check SELinux/AppArmor policies
- Check for filesystem corruption

---

### Network Problem Diagnosis Flow {#network-diagnosis}

```
For network-related issues:
  |
  +-- Step 1: Check Service/Ingress definitions
  |     File: yamls/[namespace]/kubernetes/services.yaml
  |     File: yamls/[namespace]/kubernetes/ingresses.yaml
  |     Check: configuration, selectors
  |
  +-- Step 2: Check Endpoints
  |     File: yamls/[namespace]/kubernetes/endpoints.yaml
  |     Verify: endpoints are ready
  |
  +-- Step 3: Check NetworkPolicy
  |     File: yamls/[namespace]/kubernetes/networkpolicies.yaml
  |     Check: if policy is blocking traffic
  |
  +-- Step 4: Check node network logs
  |     File: nodes/[node-name]/logs/dmesg.log
  |     Search: "eth.*down"
  |             "bridge.*error"
  |             "nf_conntrack"
  |             "TCP.*timeout", "TCP.*flood"
  |
  +-- Step 5: Check Kubelet network errors
  |     File: nodes/[node-name]/logs/kubelet.log
  |     Search: "NetworkPlugin.*failed"
  |             "CNI.*error"
  |             "SetupNetwork.*failed"
  |
  +-- Step 6: Check DNS configuration
        File: yamls/kube-system/kubernetes/pods.yaml (CoreDNS)
        File: logs/kube-system/[coredns-pod]/*.log
```

#### Common Network Problem Patterns

**DNS Resolution Failed**:
- Check CoreDNS pod status
- Check CoreDNS logs
- Check pod DNSPolicy
- Check node network

**Connection Timeout**:
- Check service endpoints ready
- Check network policies
- Check firewall rules
- Check node network interface

---

## Diagnostic Commands Toolbox

### Common grep Patterns

```bash
# Find all errors in longhorn-manager logs
grep -h "level=error" yamls/*/kubernetes/logs/longhorn-manager-*/*.log

# Find specific volume issues
grep -r "volume.*failed" yamls/*/kubernetes/events.yaml

# Find image pull errors
grep -r "ImagePullBackOff\|ErrImagePull" yamls/*/kubernetes/pods.yaml

# Find OOM killed pods
grep -r "OOMKilled" yamls/*/kubernetes/pods.yaml

# Find node system errors
grep -i "error\|fail" nodes/*/logs/messages | tail -100

# Find kernel errors
grep -i "bug\|error\|hardware" nodes/*/logs/dmesg.log

# Find network errors
grep -i "network\|dns\|timeout" nodes/*/logs/dmesg.log
```

### Common find Patterns

```bash
# Find all manager logs
find yamls/*/kubernetes/logs -path "*longhorn-manager*/*.log"

# Find all engine logs
find yamls/*/kubernetes/logs -path "*engine-image*/*.log"

# Find all pod definitions
find yamls -name "pods.yaml"

# Find all node log directories
find nodes -type d -name "logs"
```

### Dual-Mode Command Examples

**Standard Unix (Recommended)**:
```bash
find yamls/*/kubernetes/logs -path "*longhorn-manager*/*.log"
grep -h "level=error" yamls/*/kubernetes/logs/longhorn-manager-*/*.log
tail -100 nodes/[node-name]/logs/messages
```

**Alternative (if available)**:
- If `read_file()` function available: Use for reading specific files
- If `glob()` function available: Use for pattern matching
- **Priority**: Standard Unix > Environment-specific tools

---

## Next Steps

After completing Phase 2-3 diagnostics:

**Proceed to Phase 4**: Read `@patterns-library.md` for:
- Timeline reconstruction methodology
- 5 Whys root cause analysis
- Error patterns library
- Real-world examples

---

Updated 2026-01-16
