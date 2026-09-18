# Storage Logistics Doctrine: ModelDepot & ReadyLocker

> [!IMPORTANT] > **Scope**: Mandatory across Camp Colt, Suitcase AI appliance clusters, and federated edge nodes (`colt-gpu-01`, `colt-cp-01`, `fog`).
> **Supersedes**: Legacy Dewpoint storage naming conventions (`/mnt/dewpoint`, `/workspace/models/nim-cache`).

---

## 1. Architectural Overview & Logistics Model

In sovereign edge AI deployments, large-parameter LLM weights (e.g., Nemotron 49B, Mistral 24B, Llama 3.1 70B) present significant I/O bottlenecks and memory fragmentation risks on Unified Memory Architectures (UMA) like the **NVIDIA Grace Blackwell GB10** (ASUS Ascent GX10).

This document establishes the standardized **two-tier storage hierarchy** and **three-phase pod lifecycle**:

1. **`ModelDepot` (Capacity Tier — `/mnt/model-depot`)**:
   The centralized, immutable, rear-echelon repository for validated sovereign AI model profiles, SafeTensors weights, and container snapshots. Stored on persistent high-capacity storage (e.g. Btrfs pool `/dev/sda` or TrueNAS NVMe/NFS).
2. **`ReadyLocker` (Fast Tier — `/workspace/models/fast-cache`)**:
   The tactical, low-latency, warm local NVMe cache (`/dev/nvme0n1p2`) mounted directly into inference engine pods (`/opt/nim/.cache`).
3. **UMA Host Buffer Management (`drop_caches`)**:
   Mandatory kernel page cache flushing prior to engine startup to ensure disk buffer pages do not lock out GPU tensor memory allocations on shared 128GB LPDDR5X UMA.

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CAMP COLT TIERED MODEL LOGISTICS                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. CAPACITY TIER: ModelDepot (Persistent Storage Pool)                      │
│    • Host Path: /mnt/model-depot/                                           │
│    • Layout:    /mnt/model-depot/nims/validated/                            │
│                 /mnt/model-depot/nims/snapshots/                            │
│                 /mnt/model-depot/huggingface/hub/                           │
│    • Role: Long-term, immutable gold-master store for verified models.      │
│                                  │                                          │
│                   (Phase 1A: depot-hydration-preflight)                     │
│                                  ▼                                          │
│ 2. FAST TIER: ReadyLocker (GX10 Local PCIe Gen 5 NVMe)                      │
│    • Host Path: /workspace/models/fast-cache/                               │
│    • Mount:     /opt/nim/.cache                                             │
│    • Role: Tactical, low-latency, warm local cache mounted into pods.       │
│                                  │                                          │
│                   (Phase 1C: drop_caches UMA flush)                         │
│                                  ▼                                          │
│ 3. ACTIVE RUNTIME: GB10 Unified System Memory (128GB LPDDR5X UMA)           │
│    • Execution: vLLM / NVIDIA NIM Engine (SM121 Tensor Cores @ 273 GB/s)    │
│    • Allocation: Max 0.70–0.75 UMA limit (32GB reserve for CPU/Kernel)      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Standardized 3-Phase Pod Lifecycle

Every inference deployment manifest (`Deployment`) on Camp Colt Grace Blackwell hardware implements this sequence:

```mermaid
sequenceDiagram
    autonumber
    participant K8s as K8s Kubelet
    participant P1A as Phase 1A: depot-hydration-preflight
    participant P1B as Phase 1B: download-model (profile check)
    participant P1C as Phase 1C: cache-flusher
    participant P2 as Phase 2: nemotron-engine

    K8s->>P1A: Launch Phase 1A (busybox:1.36)
    Note over P1A: Inspect ReadyLocker (/opt/nim/.cache).<br/>If missing, hydrate from ModelDepot (/mnt/model-depot).
    P1A->>P1A: sync filesystem
    P1A-->>K8s: Exit Code 0

    K8s->>P1B: Launch Phase 1B (NIM Engine Container)
    Note over P1B: Verify manifest integrity & profiles.<br/>Populates cache without starting CUDA runtime.
    P1B-->>K8s: Exit Code 0

    K8s->>P1C: Launch Phase 1C (Privileged busybox)
    Note over P1C: Execute: sync; echo 3 > /proc/sys/vm/drop_caches.<br/>Frees page tables for UMA memory pool.
    P1C-->>K8s: Exit Code 0

    K8s->>P2: Launch Phase 2 (Runtime NIM Inference Engine)
    Note over P2: Allocates clean GB10 UMA memory.<br/>Binds ports 8000 (API) & 8002 (Health).
```

### Phase Breakdown

1. **Phase 1A (`depot-hydration-preflight`)**:

   - Runs lightweight `busybox:1.36`.
   - Checks if the model exists in the ReadyLocker fast cache (`/opt/nim/.cache/ngc/hub/...`).
   - If absent, copies validated model assets from ModelDepot (`/mnt/model-depot/nims/validated/...`) to ReadyLocker.
   - Executes `sync` to flush pending writes to NVMe.

2. **Phase 1B (`download-model` / Profile Validation)**:

   - Uses the official NIM image with `download-to-cache` command.
   - Validates model profiles and verifies cryptographic hashes against local cache.
   - Zero WAN download if hydrated from ModelDepot.

3. **Phase 1C (`cache-flusher`)**:

   - Privileged container with `/proc` host mount.
   - Executes `sync && echo 3 > /proc/sys/vm/drop_caches`.
   - Purges page cache, dentries, and inodes resulting from heavy file copy operations during hydration, preventing UMA memory lockouts during CUDA memory allocation in Phase 2.

4. **Phase 2 (`nemotron-engine`)**:
   - Main inference server container running optimized TensorRT-LLM / vLLM runtime.
   - Loads weights directly from ReadyLocker into GB10 Unified Memory.

---

## 3. Kubernetes Volume Definitions & Mount Specifications

### Pod Volume Specifications

```yaml
volumes:
  - name: local-ready-cache
    hostPath:
      path: /workspace/models/fast-cache
      type: DirectoryOrCreate
  - name: model-depot-storage
    hostPath:
      path: /mnt/model-depot
      type: DirectoryOrCreate
  - name: dshm
    emptyDir:
      medium: Memory
      sizeLimit: 16Gi
  - name: proc
    hostPath:
      path: /proc
```

### Volume Mount Matrix

| Container                   | Volume Name           | Mount Path         | Purpose / Access                     |
| --------------------------- | --------------------- | ------------------ | ------------------------------------ |
| `depot-hydration-preflight` | `local-ready-cache`   | `/opt/nim/.cache`  | ReadWrite (target fast tier cache)   |
| `depot-hydration-preflight` | `model-depot-storage` | `/mnt/model-depot` | ReadOnly (source capacity tier)      |
| `download-model`            | `local-ready-cache`   | `/opt/nim/.cache`  | ReadWrite (manifest & profile cache) |
| `download-model`            | `dshm`                | `/dev/shm`         | ReadWrite (shared memory)            |
| `cache-flusher`             | `proc`                | `/proc`            | ReadWrite (drop_caches trigger)      |
| `nemotron-engine`           | `local-ready-cache`   | `/opt/nim/.cache`  | ReadWrite (runtime model cache)      |
| `nemotron-engine`           | `dshm`                | `/dev/shm`         | ReadWrite (inter-process IPC)        |

---

## 4. Hardware Capability Pinning & Node Selectors

Rather than pinning inference workloads to static hostnames (e.g. `colt-gpu-01`), manifests declare explicit capability requirements:

```yaml
nodeSelector:
  kubernetes.io/arch: arm64
  accelerator: gb10
  nvidia.com/gpu.present: "true"
```

This allows the Kubernetes scheduler to place workloads across any available Grace Blackwell node while ensuring correct architecture and accelerator targeting.

---

## 5. Migration Matrix (Dewpoint → ModelDepot / ReadyLocker)

| Legacy Concept / Path      | New Standard Concept           | New Path / Identifier                              | Description                                         |
| -------------------------- | ------------------------------ | -------------------------------------------------- | --------------------------------------------------- |
| **Capacity Tier**          | `ModelDepot`                   | `/mnt/model-depot`                                 | Long-term model archive & Btrfs snapshot store      |
| **Fast Cache Tier**        | `ReadyLocker`                  | `/workspace/models/fast-cache`                     | Local NVMe fast tier cache on GPU nodes             |
| **K8s Volume (Capacity)**  | `dewpoint-storage`             | `model-depot-storage`                              | hostPath: `/mnt/model-depot`                        |
| **K8s Volume (Fast Tier)** | `local-nvme-cache`             | `local-ready-cache`                                | hostPath: `/workspace/models/fast-cache`            |
| **InitContainer (1A)**     | `dewpoint-preflight`           | `depot-hydration-preflight`                        | Pre-flight hydration from ModelDepot to ReadyLocker |
| **Sync Script**            | `scripts/dewpoint-nim-sync.sh` | `scripts/depot-nim-sync.sh`                        | Btrfs snapshotting, sync, and cache eviction tool   |
| **Documentation**          | `docs/DEWPOINT.md`             | `docs/storage_tiering_model_depot_ready_locker.md` | Canonical storage logistics doctrine                |

---

## 6. Operational Synchronization Runbook

To synchronize, snapshot, or evict model weights using the new doctrine tooling:

```bash
# Live sync to ModelDepot while preserving ReadyLocker fast cache
sudo ./scripts/depot-nim-sync.sh models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5 --keep-cache

# Eviction sync (backs up to ModelDepot and reclaims ReadyLocker NVMe space)
sudo ./scripts/depot-nim-sync.sh models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5 --evict
```
