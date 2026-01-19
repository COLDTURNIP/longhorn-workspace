# Patterns Library Module

**Prerequisites**: You should have:
- Completed Phase 2-3 diagnostics (@diagnostic-flows.md)
- Collected evidence and observations from bundle analysis

**This Module Contains**: Root cause analysis methods, error patterns, and real-world examples

---

## Phase 4: Root Cause Analysis

### Timeline Reconstruction Method {#timeline-reconstruction}

**Purpose**: Build chronological event timeline across all diagnostic layers to identify trigger events.

**Step 1: Extract all timestamps**

```bash
# Extract K8s events
find yamls -name "events.yaml" -exec grep -h "lastTimestamp\|firstTimestamp" {} \; | sort

# Extract pod logs (timestamps at line start)
grep -h "^[0-9]" logs/*/*/*.log | sort

# Extract node kubelet logs
grep -h "^[0-9]" nodes/*/logs/kubelet.log | sort

# Extract node system logs
grep -h "^[0-9]" nodes/*/logs/messages | sort

# Extract node kernel logs
grep -h "^[0-9]" nodes/*/logs/dmesg.log | sort
```

**Step 2: Merge and sort events chronologically**

Create unified timeline across layers:
- Kernel layer (dmesg.log)
- System layer (messages)
- Kubelet layer (kubelet.log)
- K8s API layer (events.yaml)
- Container layer (pod status)
- Application layer (container logs)

**Step 3: Identify trigger event**

Find first occurrence of problem symptoms and trace back to root cause.

**Example Timeline**:
```
13:20:16 [Kernel] nvme nvme3: failed to connect socket: -111
13:20:41 [System] Buffer I/O error on dev dm-1
13:21:07 [K8s API] BackingImageDataSource created
13:21:20 [Application] BackingImageManager initialized
         Root Cause: NVMe hardware failure at 13:20:16
```

---

### 5 Whys Method {#5-whys-method}

**Purpose**: Iteratively ask "Why?" to drill down from symptom to root cause.

**Structure**:
```
Problem: [Describe observable symptom]

1. Why does this happen? -> [Direct cause]
2. Why? -> [Underlying cause 1]
3. Why? -> [Underlying cause 2]
4. Why? -> [Underlying cause 3]
5. Why? -> [Root cause]

Final Root Cause: [Summary with evidence]
```

**Example**:
```
Problem: Backing Image download stuck at 0% progress

1. Why is progress 0%?
   -> BackingImageDataSource status is empty, no download started

2. Why did download not start?
   -> Node NVMe hardware failure prevents storage access

3. Why did NVMe fail?
   -> NVMe device connection refused (-111) repeatedly

4. Why was connection refused?
   -> Hardware/firmware issue or network fabric problem

5. Why is this happening now?
   -> Hardware degradation or intermittent failure

Final Root Cause: Node NVMe hardware failure causing storage inaccessibility,
preventing BackingImageManager from initializing download.
```

---

### Evidence-Based Analysis {#evidence-based-analysis}

**Principles**:
1. All conclusions MUST have supporting evidence
2. Cite specific files, line numbers, timestamps
3. Avoid speculation - use facts from logs and YAMLs
4. Cross-reference findings across multiple layers
5. Identify inconsistencies if any

**Evidence Format**:
```
Finding: [What you discovered]

Evidence:
  - File: [path/to/file]
    Line: "[exact log line or YAML excerpt]"
    Timestamp: [when it occurred]
  
  - File: [another/file]
    Line: "[supporting evidence]"
    Timestamp: [when it occurred]

Correlation:
  [How events relate to each other]

Conclusion: [Root cause based on evidence]
```

**Example**:
```
Finding: NVMe connection failures preventing BackingImage download

Evidence:
  - File: nodes/ip-10-0-1-166/logs/dmesg.log
    Line: "nvme nvme3: failed to connect socket: -111"
    Timestamp: 13:20:16 - 13:20:41

  - File: nodes/ip-10-0-1-166/logs/messages
    Line: "Buffer I/O error on dev dm-1"
    Timestamp: 13:20:41

  - File: yamls/longhorn-system/longhorn.io/v1beta2/backingimagedatasources.yaml
    Resource: download-ubuntu (UUID: 3b344500)
    Status: currentState: "", progress: 0
    Timestamp: 2025-09-12T13:21:07Z

Correlation:
  NVMe failures at 13:20:16 -> Buffer I/O error at 13:20:41
  -> BackingImageDataSource created at 13:21:07 with empty status
  -> No download progress

Conclusion: NVMe hardware failure is the root cause.
```

---

## Diagnostic Patterns Library {#patterns-library}

### Pod Problem Patterns

#### Pattern: CrashLoopBackOff

**Symptoms**:
- Pod status: CrashLoopBackOff
- Restart count: High (usually > 3)

**Common Causes**:
1. Application crash on startup
2. Missing dependencies (database, config file)
3. Resource limits too low (OOMKilled)
4. Liveness/readiness probe failures
5. Incorrect command or arguments

**Diagnostic Steps**:
1. Check exit code from pod YAML
2. Read container logs for error messages
3. Check resource limits
4. Verify liveness/readiness probe configuration
5. Check node system logs for OOM killer

**Exit Code Reference**:
| Exit Code | Meaning | Common Fix |
|-----------|---------|-------------|
| 1 | Application error | Fix application code |
| 127 | Command not found | Check entrypoint |
| 137 | OOMKilled | Increase memory limit |
| 139 | Segmentation fault | Debug application |

#### Pattern: OOMKilled

**Symptoms**:
- Exit code: 137
- Last terminated reason: OOMKilled

**Diagnostic Steps**:
1. Check pod memory limits: `spec.containers[].resources.limits.memory`
2. Check node memory usage: `nodes/[node]/hostinfos/hostinfo`
3. Check for OOM killer: `grep "OOM killer" nodes/*/logs/messages`
4. Analyze processes: `nodes/[node]/hostinfos/processes_info`

**Evidence to Collect**:
- Pod memory limit vs actual usage
- Node memory capacity vs allocatable
- OOM killer timestamp and killed process

#### Pattern: ImagePullBackOff

**Symptoms**:
- Pod status: ImagePullBackOff
- Event: "Failed to pull image"

**Diagnostic Steps**:
1. Check image name and tag in pod spec
2. Verify image registry accessibility
3. Check imagePullSecrets configuration
4. Check network connectivity from node
5. Verify TLS certificates (private registry)

**Error Patterns**:
| Error Message | Common Cause |
|---------------|---------------|
| "no matching manifest" | Wrong image tag |
| "permission denied" | Image pull secret issue |
| "connection refused" | Registry not accessible |
| "certificate" | TLS configuration error |

#### Pattern: Pending State

**Symptoms**:
- Pod status: Pending
- Pod not being scheduled

**Diagnostic Steps**:
1. Check scheduler events: `yamls/*/kubernetes/events.yaml`
2. Check node resources: `yamls/cluster/kubernetes/nodes.yaml`
3. Check node selectors and taints
4. Check resource requests vs allocatable
5. Check for PVC binding

**Common Causes**:
- Insufficient node resources
- Node selector mismatch
- Taints without tolerations
- PVC not bound

---

### Node Problem Patterns

#### Pattern: NotReady - MemoryPressure

**Symptoms**:
- Node status: NotReady
- Condition: MemoryPressure: True

**Diagnostic Steps**:
1. Check node allocatable vs capacity
2. Check pod memory requests on node
3. Check for OOM killer: `grep "OOM killer" nodes/*/logs/messages`
4. Analyze high memory processes: `nodes/[node]/hostinfos/processes_info`

**Common Fixes**:
- Delete or resize high-memory pods
- Increase node memory
- Add more nodes

#### Pattern: NotReady - DiskPressure

**Symptoms**:
- Node status: NotReady
- Condition: DiskPressure: True

**Diagnostic Steps**:
1. Check disk usage: `nodes/[node]/hostinfos/hostinfo`
2. Check for disk full: `grep "No space left" nodes/*/logs/messages`
3. Check for I/O errors: `grep "I/O error" nodes/*/logs/dmesg.log`

**Common Fixes**:
- Clean up disk space
- Move data to external storage
- Add more storage

#### Pattern: NotReady - KubeletNotReady

**Symptoms**:
- Node status: NotReady
- Condition: KubeletReady: False

**Diagnostic Steps**:
1. Check Kubelet logs: `nodes/[node]/logs/kubelet.log`
2. Check for "PLEG unhealthy"
3. Check container runtime errors
4. Check systemd service status

**Common Causes**:
- PLEG (Pod Lifecycle Event Generator) unhealthy
- Container runtime failure
- Kubelet crash or restart

---

### Storage Problem Patterns

#### Pattern: PVC Pending - No PV Available

**Symptoms**:
- PVC status: Pending
- Event: "no persistent volumes available"

**Diagnostic Steps**:
1. Check StorageClass: `yamls/cluster/kubernetes/storageclasses.yaml`
2. Check for existing PVs: `yamls/cluster/kubernetes/persistentvolumes.yaml`
3. Check provisioner logs

**Common Causes**:
- Wrong StorageClass
- Provisioner failure
- Resource quota exceeded

#### Pattern: Volume Mount Failed

**Symptoms**:
- Pod event: "VolumeMount failed"
- Container not starting

**Diagnostic Steps**:
1. Check node mount info: `nodes/[node]/hostinfos/proc_mounts`
2. Check device availability
3. Check filesystem type
4. Check kubelet logs: `grep "MountVolume" nodes/[node]/logs/kubelet.log`
5. Check dmesg: `grep "EXT4-fs\|XFS" nodes/[node]/logs/dmesg.log`

**Common Causes**:
- Device not ready
- Permission denied
- Filesystem corruption

---

### Network Problem Patterns

#### Pattern: DNS Resolution Failed

**Symptoms**:
- Error: "lookup ... on ... no such host"
- Service not accessible

**Diagnostic Steps**:
1. Check CoreDNS pod: `yamls/kube-system/kubernetes/pods.yaml`
2. Check CoreDNS logs: `logs/kube-system/[coredns-pod]/*.log`
3. Check pod DNSPolicy
4. Check node network: `grep "network" nodes/*/logs/dmesg.log`

**Common Causes**:
- CoreDNS not running
- Network partition
- Wrong DNS server configuration

#### Pattern: Connection Timeout

**Symptoms**:
- Error: "connection timeout"
- Error: "dial tcp ... i/o timeout"

**Diagnostic Steps**:
1. Check service endpoints: `yamls/*/kubernetes/endpoints.yaml`
2. Check network policies: `yamls/*/kubernetes/networkpolicies.yaml`
3. Check node network interface
4. Check for conntrack issues: `grep "nf_conntrack" nodes/*/logs/dmesg.log`

**Common Causes**:
- Service not ready
- Network policy blocking
- Firewall blocking
- Connection tracking table full

---

## Real-World Examples {#examples}

### Example 1: Backing Image Download Stuck {#example-1}

**Problem Description**: Backing Image download stuck after network disconnection

**Pre-Analysis**:
- Bundle path: `/tmp/sb-analysis-1234567890`
- Affected: BackingImageDataSource "download-ubuntu"
- Symptoms: Progress stuck at 0%, state empty
- Timeline: After network disconnection

**Phase 0: Problem Classification**
- Type: Storage problem (backing image)
- Affected resources: BackingImageDataSource "download-ubuntu"

**Phase 1: Bundle Structure**
- Confirmed standard structure

**Phase 2-3: Deep Diagnosis**

**Pod Level**:
- Checked BackingImageManager pod logs
- Found successful initialization, no errors

**Node Level**:
```bash
# Check node dmesg
tail -500 nodes/ip-10-0-1-166/logs/dmesg.log
```
Found: NVMe connection failures
```
13:20:16 | nvme nvme3: failed to connect socket: -111
13:20:18 | Failed reconnect attempt 3/15
13:20:20 | Failed reconnect attempt 4/15
```

```bash
# Check node messages
tail -500 nodes/ip-10-0-1-166/logs/messages
```
Found: Buffer I/O error
```
13:20:41 | Buffer I/O error on dev dm-1
```

**Phase 4: Root Cause Analysis**

**Timeline**:
```
13:20:16 [Kernel] NVMe connection failures start
13:20:41 [System] Buffer I/O error
13:21:07 [K8s] download-ubuntu BackingImageDataSource created
13:21:20 [App] BackingImageManager initialized
```

**5 Whys**:
1. Why is download stuck?
   -> BackingImageDataSource status empty, progress 0

2. Why status empty?
   -> BackingImageManager cannot access storage

3. Why can't access storage?
   -> NVMe device not available (connection failures)

4. Why connection failed?
   -> NVMe device connection refused (-111) repeatedly

5. Why is this happening?
   -> Hardware/firmware issue with NVMe controller

**Final Root Cause**: Node NVMe hardware failure causing storage inaccessibility, preventing BackingImageManager from initializing download.

**Evidence**:
- File: nodes/ip-10-0-1-166/logs/dmesg.log
  Lines: "nvme nvme3: failed to connect socket: -111" (repeated)
- File: nodes/ip-10-0-1-166/logs/messages
  Line: "Buffer I/O error on dev dm-1"
- File: yamls/longhorn-system/longhorn.io/v1beta2/backingimagedatasources.yaml
  Resource: download-ubuntu with empty status

---

### Example 2: Pod CrashLoopBackOff {#example-2}

**Problem Description**: Pod keeps restarting with CrashLoopBackOff

**Pre-Analysis**:
- Bundle path: `/tmp/sb-analysis-9876543210`
- Affected: Pod "my-app" in namespace "default"
- Symptoms: CrashLoopBackOff, restart count: 5
- Error: "Cannot connect to database"

**Phase 2-3: Deep Diagnosis**

**Container Level**:
```bash
# Check pod status
grep -A 20 "name: my-app" yamls/default/kubernetes/pods.yaml
```
Result: restartCount=5, exitCode=1

```bash
# Read container logs
cat logs/default/my-app/my-app.log
```
Found: "Error: Cannot connect to database: Connection refused"

**Node Level**:
- Checked kubelet logs: Normal, no errors
- Checked network: No issues
- Conclusion: Application error, not infrastructure

**Phase 4: Root Cause Analysis**

**5 Whys**:
1. Why is pod crashing?
   -> Application cannot connect to database on startup

2. Why can't connect?
   -> Database service not ready or DNS resolution failure

3. Why not ready?
   -> Database pod not running or service misconfigured

4. Why not configured?
   -> Missing environment variable or wrong service name

5. Why is it wrong?
   -> Deployment manifest has incorrect database connection string

**Final Root Cause**: Incorrect database connection string in deployment manifest

**Evidence**:
- File: logs/default/my-app/my-app.log
  Line: "Error: Cannot connect to database: Connection refused"
- File: yamls/default/kubernetes/pods.yaml
  Resource: my-app with restartCount=5, exitCode=1

---

## Quick Reference {#quick-reference}

### Problem Type to Priority Files

| Problem | Primary Files | Secondary Files | Key Search Terms |
|---------|---------------|------------------|-------------------|
| Pod Issues | pods.yaml, logs/*/*.log | events.yaml | CrashLoopBackOff, exitCode, restartCount |
| Node Issues | nodes.yaml | nodes/*/logs/*.log | NotReady, MemoryPressure, DiskPressure |
| Storage Issues | pvs.yaml, pvcs.yaml | proc_mounts, dmesg.log | Pending, Bound, MountFailed, I/O error |
| Network Issues | services.yaml, endpoints.yaml | dmesg.log | DNS, timeout, unreachable |

### Common Error Keywords by Layer

**Pod Logs**:
- `error`, `fail`, `panic`, `fatal`, `timeout`, `connection refused`, `permission denied`

**Node System Logs**:
- `OOM killer`, `segfault`, `I/O error`, `BUG:`, `Call Trace`, `Hardware Error`

**Node Kernel Logs**:
- `nvme.*failed`, `EXT4-fs error`, `XFS error`, `TCP.*timeout`, `bridge.*error`

### File Path Quick Reference

```bash
# Pod issues
yamls/[namespace]/kubernetes/pods.yaml
logs/[namespace]/[pod]/*.log

# Node issues
yamls/cluster/kubernetes/nodes.yaml
nodes/[node-name]/logs/kubelet.log
nodes/[node-name]/logs/messages
nodes/[node-name]/logs/dmesg.log

# Storage issues
yamls/[namespace]/kubernetes/persistentvolumeclaims.yaml
yamls/cluster/kubernetes/persistentvolumes.yaml
nodes/[node-name]/hostinfos/proc_mounts

# Network issues
yamls/[namespace]/kubernetes/services.yaml
yamls/[namespace]/kubernetes/endpoints.yaml
nodes/[node-name]/logs/dmesg.log
```

---

Updated 2026-01-16
