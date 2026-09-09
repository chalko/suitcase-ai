# Tiered Storage Migration & ModelDepot Doctrine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Camp Colt sovereign AI appliance from legacy "Dewpoint" storage naming to the standardized two-tier `ModelDepot` (Capacity Tier) and `ReadyLocker` (Fast Tier) doctrine across documentation, Kubernetes inference manifests, and operational sync tooling, fulfilling bead `sa-etk`.

**Architecture:** Implement standardized storage logistics hierarchy where rear-echelon immutable model checkpoints reside in `ModelDepot` (`/mnt/model-depot`), forward-deployed local NVMe caching operates in `ReadyLocker` (`/workspace/models/fast-cache`), and compute deployments enforce a 3-phase pod lifecycle (`depot-hydration-preflight` -> `download-model` -> `cache-flusher` drop_caches) pinned via capability-based GPU node selectors (`accelerator: gb10`, `nvidia.com/gpu.present: "true"`).

**Tech Stack:** Kubernetes (Talos Linux / Proxmox VE), NVIDIA NIM (Nemotron 49B FP8 on Grace Blackwell GB10), Bash / rsync / Btrfs snapshot tooling, Flux GitOps.

**Spec:** [`scai/docs/storage_doctrine_model_depot_and_ready_locker.md`](../../../scai/docs/storage_doctrine_model_depot_and_ready_locker.md), Bead `sa-etk`, and FRAGO directive `lu-wisp-hj5vek`.

---

## Global Constraints

- **Storage Hierarchy:**
  - `ModelDepot` (Capacity Tier): `/mnt/model-depot` on host, volume name `model-depot-storage` (read-only mount).
  - `ReadyLocker` (Fast Tier): `/workspace/models/fast-cache` on host, volume name `local-ready-cache` (mapped to container `/opt/nim/.cache`).
- **Pod Lifecycle InitContainers:**
  - Phase 1A: `depot-hydration-preflight` (checks ReadyLocker fast cache, hydrates from ModelDepot if missing, runs `sync`).
  - Phase 1B: `download-model` (profile and integrity validation using `download-to-cache`).
  - Phase 1C: `cache-flusher` (privileged container executing `echo 3 > /proc/sys/vm/drop_caches` to prevent UMA memory fragmentation).
- **Workload Placement:**
  - Semantic node selector labels: `kubernetes.io/arch: arm64`, `accelerator: gb10`, `nvidia.com/gpu.present: "true"`.
  - Static hostname pinning (`kubernetes.io/hostname: colt-gpu-01`) is strictly prohibited.
- **Zero-Secret / Least Privilege:** No credentials or plaintext keys in manifests or logs.
- **GitOps Target:** Branch `main` on remote `colt`.

---

## Plan Overview & Task Breakdown

1. **Task 1: Core Storage Doctrine Documentation & Runbook Deprecation**

   - Author `docs/storage_tiering_model_depot_ready_locker.md` detailing the two-tier architecture, pod lifecycle, volume mount specifications, and deprecation matrix.
   - Create alias pointer `docs/MODEL_DEPOT.md`.
   - Update `docs/DEWPOINT.md` with deprecation banner and cross-reference.

2. **Task 2: Kubernetes Inference Manifest Refactoring (`nemotron-49b.yaml`)**

   - Rename volumes to `model-depot-storage` (`/mnt/model-depot`) and `local-ready-cache` (`/workspace/models/fast-cache`).
   - Refactor initContainer `dewpoint-preflight` -> `depot-hydration-preflight`.
   - Replace static node selector with GPU capability selectors (`accelerator: gb10`, `nvidia.com/gpu.present: "true"`).
   - Validate manifest syntax with `kubectl --dry-run=client`.

3. **Task 3: Operational Tooling Alignment (`scripts/depot-nim-sync.sh`)**

   - Create `scripts/depot-nim-sync.sh` implementing ModelDepot backup, snapshotting, and ReadyLocker eviction workflows.
   - Ensure executable permissions and test argument handling.

4. **Task 4: Verification, GitOps Push, Bead Closure, and Strategic Reporting**
   - Run end-to-end dry-run verification of Kubernetes manifests and documentation links.
   - Commit and push to `colt/main`.
   - Close bead `sa-etk` via `bd close`.
   - Send confirmation mail to `scai/peggy` via `gc mail send`.

---

## Detailed Tasks

### Task 1: Core Storage Doctrine Documentation & Runbook Deprecation

**Files:**

- Create: `docs/storage_tiering_model_depot_ready_locker.md`
- Create: `docs/MODEL_DEPOT.md`
- Modify: `docs/DEWPOINT.md`

**Interfaces:**

- Consumes: `scai/docs/storage_doctrine_model_depot_and_ready_locker.md`
- Produces: Definitive storage architecture guide for Camp Colt operators and agents.

- [ ] **Step 1: Write `docs/storage_tiering_model_depot_ready_locker.md`**

```markdown
# Storage Logistics Doctrine: ModelDepot & ReadyLocker

> [!IMPORTANT] > **Authority**: Promulgated by Margaret "Peggy" Carter (`scai/peggy` — Strategic Theater Director) & Direct Operator Directive.
> **Scope**: Mandatory across Camp Colt and `suitcase-ai` infrastructure (`colt-gpu-01`, `colt-cp-01`, and sovereign edge appliances).
> **Supersedes**: Legacy "Dewpoint" storage naming conventions (`docs/DEWPOINT.md`).

---

## 1. Architectural Hierarchy & Logistics Overview

In high-parameter sovereign edge AI deployments (e.g., Nemotron 49B, Mistral 24B, Llama 3.3 70B), high model loading latencies and memory fragmentation on Unified Memory Architectures (UMA) like the **NVIDIA Grace Blackwell GB10** require strict storage tiering.

Camp Colt implements a standardized **two-tier model logistics model**:

1. **`ModelDepot` (Capacity Tier)**: The central, immutable, rear-echelon repository for pre-validated model profiles, SafeTensors checkpoints, and NIM cache archives.
2. **`ReadyLocker` (Fast Tier)**: The tactical, high-speed, local NVMe cache residing directly on `colt-gpu-01`.
3. **UMA Host Buffer Management**: Mandatory kernel page cache flushing (`drop_caches`) post-hydration to prevent disk buffer pages from starving GPU tensor memory allocations.
   ...
```

- [ ] **Step 2: Create pointer `docs/MODEL_DEPOT.md`**

```markdown
# ModelDepot Architecture

Please refer to the master storage doctrine in [docs/storage_tiering_model_depot_ready_locker.md](storage_tiering_model_depot_ready_locker.md).
```

- [ ] **Step 3: Update `docs/DEWPOINT.md` with deprecation banner**

Prepend deprecation warning block at top of `docs/DEWPOINT.md`:

```markdown
> [!WARNING] > **DEPRECATION NOTICE (2026-09-09)**: The "Dewpoint" storage terminology and paths (`/mnt/dewpoint`, `/workspace/models/nim-cache`) have been deprecated and superseded by the **ModelDepot & ReadyLocker** storage logistics doctrine.
> Please refer to [docs/storage_tiering_model_depot_ready_locker.md](storage_tiering_model_depot_ready_locker.md) for current production architecture.
```

- [ ] **Step 4: Verify documentation links and markdown syntax**

Run: `test -f docs/storage_tiering_model_depot_ready_locker.md && test -f docs/MODEL_DEPOT.md`
Expected: Return 0

- [ ] **Step 5: Commit documentation updates**

```bash
git add docs/storage_tiering_model_depot_ready_locker.md docs/MODEL_DEPOT.md docs/DEWPOINT.md
git commit -m "docs(storage): establish ModelDepot and ReadyLocker doctrine and deprecate Dewpoint"
```

---

### Task 2: Kubernetes Inference Manifest Refactoring (`nemotron-49b.yaml`)

**Files:**

- Modify: `provision/k8s/apps/inference/nemotron-49b.yaml`

**Interfaces:**

- Consumes: Volume names `model-depot-storage` and `local-ready-cache`
- Produces: Flux-reconciled inference Deployment and Service conforming to storage doctrine

- [ ] **Step 1: Refactor `provision/k8s/apps/inference/nemotron-49b.yaml`**

Apply the following modifications:

1. Replace `nodeSelector`:

   ```yaml
   nodeSelector:
     kubernetes.io/arch: arm64
     accelerator: gb10
     nvidia.com/gpu.present: "true"
   ```

2. Refactor Phase 1A initContainer to `depot-hydration-preflight`:

   ```yaml
   - name: depot-hydration-preflight
     image: docker.io/library/busybox:1.36
     imagePullPolicy: IfNotPresent
     command:
       - /bin/sh
       - -c
       - |
         set -eu
         echo "==> [Phase 1A] Checking ReadyLocker fast cache for Nemotron-49B..."
         TARGET="/opt/nim/.cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
         SOURCE="/mnt/model-depot/nims/validated/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
         if [ ! -d "$TARGET" ] && [ -d "$SOURCE" ]; then
           echo "Hydrating fast tier from ModelDepot validated storage..."
           mkdir -p /opt/nim/.cache/ngc/hub
           cp -a "$SOURCE" "$TARGET"
         fi
         echo "Syncing filesystem and verifying directory structure..."
         sync
         echo "Phase 1A Pre-flight completed."
     volumeMounts:
       - name: local-ready-cache
         mountPath: /opt/nim/.cache
       - name: model-depot-storage
         mountPath: /mnt/model-depot
         readOnly: true
   ```

3. Update volume mounts in `download-model` and `nemotron-engine` containers to use `local-ready-cache`.
4. Update pod `volumes` definition:

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

- [ ] **Step 2: Validate Kubernetes manifest syntax**

Run: `kubectl apply --dry-run=client -f provision/k8s/apps/inference/nemotron-49b.yaml`
Expected: `deployment.apps/nemotron-49b-haze configured (dry run)`, `service/nemotron-49b configured (dry run)`

- [ ] **Step 3: Commit manifest changes**

```bash
git add provision/k8s/apps/inference/nemotron-49b.yaml
git commit -m "feat(inference): migrate nemotron-49b manifest to ModelDepot and ReadyLocker storage"
```

---

### Task 3: Operational Tooling Alignment (`scripts/depot-nim-sync.sh`)

**Files:**

- Create: `scripts/depot-nim-sync.sh`

**Interfaces:**

- Consumes: Model weights at `/workspace/models/fast-cache` and `/mnt/model-depot`
- Produces: CLI sync utility for sysadmins to stage and evict model profiles

- [ ] **Step 1: Write `scripts/depot-nim-sync.sh`**

```bash
#!/usr/bin/env bash
# File: scripts/depot-nim-sync.sh
# Description: Manages ModelDepot backup, snapshotting, and ReadyLocker cache eviction on colt-gpu-01.
set -euo pipefail

MODEL_ID="${1:-models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5}"
EVICT_CACHE="${2:-true}"
if [ "${MODEL_ID}" = "--keep-cache" ] || [ "${MODEL_ID}" = "--no-evict" ]; then
    echo "Usage: $0 <MODEL_ID> [--keep-cache|--evict]"
    exit 1
fi
if [ "${2:-}" = "--keep-cache" ] || [ "${2:-}" = "--no-evict" ]; then
    EVICT_CACHE="false"
fi

SRC_DIR="/workspace/models/fast-cache/ngc/hub/${MODEL_ID}"
DEST_DIR="/mnt/model-depot/nims/validated/${MODEL_ID}"
SNAP_DIR="/mnt/model-depot/nims/snapshots"

echo "================================================================="
echo "💾 ModelDepot & ReadyLocker NIM Backup & Snapshot Automation"
echo "Model ID:    ${MODEL_ID}"
echo "Source:      ${SRC_DIR}"
echo "Dest:        ${DEST_DIR}"
echo "Evict Cache: ${EVICT_CACHE}"
echo "Start:       $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================="
...
```

- [ ] **Step 2: Set executable permissions and test script syntax**

Run: `chmod +x scripts/depot-nim-sync.sh && bash -n scripts/depot-nim-sync.sh`
Expected: Return 0

- [ ] **Step 3: Commit sync script**

```bash
git add scripts/depot-nim-sync.sh
git commit -m "feat(scripts): add depot-nim-sync.sh for ModelDepot and ReadyLocker operations"
```

---

### Task 4: Verification, GitOps Push, Bead Closure, and Strategic Reporting

**Files:**

- Repository root & Beads issue tracking

- [ ] **Step 1: Run comprehensive pre-flight verification**

Run:

```bash
git status
kubectl apply --dry-run=client -k provision/k8s/apps/inference/
```

Expected: Clean working tree (or ready for final push) and dry-run success.

- [ ] **Step 2: Push changes to GitOps remote `colt/main`**

```bash
git push colt main
```

- [ ] **Step 3: Close bead `sa-etk`**

```bash
bd close sa-etk -r "Migrated storage architecture to ModelDepot and ReadyLocker doctrine across docs, manifests, and sync scripts"
```

- [ ] **Step 4: Send strategic confirmation mail to `scai/peggy`**

```bash
gc mail send scai/peggy --subject "RE: FRAGO: Formal Storage Doctrine Migration — ModelDepot & ReadyLocker" --body "Peggy,

The storage doctrine migration for Camp Colt and suitcase-ai (bead sa-etk) has been completed and pushed to colt/main:

1. Documentation: Authored docs/storage_tiering_model_depot_ready_locker.md and docs/MODEL_DEPOT.md, and updated docs/DEWPOINT.md with deprecation notices.
2. Inference Manifests: Updated provision/k8s/apps/inference/nemotron-49b.yaml with model-depot-storage (/mnt/model-depot), local-ready-cache (/workspace/models/fast-cache), depot-hydration-preflight, and semantic capability selectors (accelerator: gb10, nvidia.com/gpu.present: 'true').
3. Automation Tooling: Deployed scripts/depot-nim-sync.sh for operational snapshotting and ReadyLocker hydration/eviction.
4. GitOps Reconciled: Committed and pushed to colt/main (ready for Flux sync).

Bead sa-etk is closed."
```
