# Dewpoint Storage Architecture & Model Lifecycle Runbook

## 1. Architectural Overview

**Dewpoint** (`/mnt/dewpoint`) is the persistent, high-capacity **4 TB Btrfs storage pool** (`/dev/sda`) hosted on the **Camp Colt GPU accelerator node** (`colt-gpu-01` @ `10.82.0.3`, ASUS Ascent GX10 / NVIDIA Grace Blackwell GB10).

It acts as the primary cold-and-warm archive for validated sovereign AI model weights, container runtime snapshots, and pre-warmed Hugging Face/NGC model profiles.

```text
+-----------------------------------------------------------------------------------+
| ASUS Ascent GX10 (colt-gpu-01 / 10.82.0.3)                                        |
|                                                                                   |
|  [Fast Tier] 1TB NVMe SSD (/dev/nvme0n1p2 -> /workspace)                          |
|  ├── /workspace/models/nim-cache/                                                 |
|  │   ├── models--mistralai--Mistral-Small-24B-Instruct-2501  (Active Model)       |
|  │   └── tmp/nim_*                                                                |
|                                                                                   |
|  [Capacity Tier] 4TB Btrfs Storage Pool (/dev/sda -> /mnt/dewpoint)               |
|  ├── /mnt/dewpoint/nim-cache/current/                     (Btrfs Subvolume 256)   |
|  ├── /mnt/dewpoint/nim-cache/snapshots/                   (Btrfs Snapshots)       |
|  │   ├── nim-cache-pre-sync-nemotron49b-20260829_090641                           |
|  │   └── nim-cache-validated-nemotron49b-20260829_090641  (Validated Gold Master)  |
|  ├── /mnt/dewpoint/nims/validated/                        (Direct File Mirrors)   |
|  │   └── models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5/                  |
|  └── /mnt/dewpoint/nims/snapshots/                        (Hardlink Mirrors)      |
+-----------------------------------------------------------------------------------+
```

---

## 2. Standard Backup & Snapshot Lifecycle

When migrating, updating, or evicting large model profiles (e.g., Nemotron 49B, Mistral 24B, Llama 3.1 70B), follow this exact four-phase lifecycle:

### Phase 1: Graceful Pod Shutdown (GitOps)

Always scale the active inference deployment to `0` replicas before backing up or evicting cache to ensure all file descriptors are closed and no writing processes are active.

1. Set `replicas: 0` in the application manifest:

   ```yaml
   # provision/k8s/apps/inference/<model>.yaml
   spec:
     replicas: 0
   ```

2. Commit and reconcile via GitOps:

   ```bash
   git commit -am "chore(inference): scale <model> to 0 replicas"
   git push colt main
   ```

3. Confirm pod termination:

   ```bash
   kubectl get pods -n nim-system
   ```

---

### Phase 2: Dewpoint Pre-Sync Snapshot

Before writing new artifacts to the backup directory, take a point-in-time snapshot of the current state:

```bash
# Connect via SSH as colt-sysadmin-agent
ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.3

# Create timestamped pre-sync snapshot
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
sudo btrfs subvolume snapshot \
    /mnt/dewpoint/nim-cache/current \
    /mnt/dewpoint/nim-cache/snapshots/nim-cache-pre-sync-${MODEL_ID}-${TIMESTAMP}

sudo mkdir -p /mnt/dewpoint/nims/snapshots
sudo cp -al \
    /mnt/dewpoint/nims/validated/${MODEL_ID} \
    /mnt/dewpoint/nims/snapshots/pre-sync-${MODEL_ID}-${TIMESTAMP}
```

---

### Phase 3: Synchronize Validated Model Weights

Sync the active model directory from the NVMe workspace cache to Dewpoint with full attribute, hardlink, and ACL preservation (`rsync -aHEX`):

```bash
# Sync to validated directory
sudo rsync -aHAXv --delete \
    /workspace/models/nim-cache/ngc/hub/${MODEL_ID}/ \
    /mnt/dewpoint/nims/validated/${MODEL_ID}/

# Mirror to current Btrfs subvolume
sudo rsync -aHAXv \
    /workspace/models/nim-cache/ngc/hub/${MODEL_ID}/ \
    /mnt/dewpoint/nim-cache/current/ngc/hub/${MODEL_ID}/
```

---

### Phase 4: Post-Sync Snapshot

Capture the newly synchronized gold-master state in a post-sync snapshot:

```bash
sudo btrfs subvolume snapshot \
    /mnt/dewpoint/nim-cache/current \
    /mnt/dewpoint/nim-cache/snapshots/nim-cache-validated-${MODEL_ID}-${TIMESTAMP}

sudo cp -al \
    /mnt/dewpoint/nims/validated/${MODEL_ID} \
    /mnt/dewpoint/nims/snapshots/post-sync-${MODEL_ID}-${TIMESTAMP}
```

---

### Phase 5: NVMe Workspace Cache Eviction

Once the backup and snapshots are confirmed, evict the large model weights from the 1TB NVMe drive to make room for new workloads:

```bash
# Remove evicted model directory from NVMe
sudo rm -rf /workspace/models/nim-cache/ngc/hub/${MODEL_ID}

# Clean transient runtime profiling artifacts
sudo rm -rf /workspace/models/nim-cache/tmp/nim_*

# Verify available NVMe space
df -h /workspace /mnt/dewpoint
```

---

## 3. Rapid Zero-Download Restoration

To restore an evicted model profile back to NVMe without any internet downloads or WAN latency:

```bash
# 1. Ensure target directory exists on NVMe
sudo mkdir -p /workspace/models/nim-cache/ngc/hub/${MODEL_ID}

# 2. Fast local rsync from Dewpoint to NVMe
sudo rsync -aHAXv \
    /mnt/dewpoint/nims/validated/${MODEL_ID}/ \
    /workspace/models/nim-cache/ngc/hub/${MODEL_ID}/

# 3. Scale deployment back to 1 replica in GitOps
# provision/k8s/apps/inference/<model>.yaml -> replicas: 1
git commit -am "chore(inference): scale <model> to 1 replica" && git push colt main
```

---

## 4. Automated Backup Script (`scripts/dewpoint-nim-sync.sh`)

The repository includes a helper script [`scripts/dewpoint-nim-sync.sh`](../scripts/dewpoint-nim-sync.sh) that automates the entire snapshot -> rsync -> snapshot -> eviction/preservation sequence:

```bash
# 1. Live Backup (Preserves active model in NVMe workspace cache for serving):
sudo ./scripts/dewpoint-nim-sync.sh models--nim--nvidia--nemotron-3.5-lightning --keep-cache

# 2. Eviction Backup (Reclaims NVMe storage when migrating/switching models):
sudo ./scripts/dewpoint-nim-sync.sh models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5
```

1. Checks for Btrfs subvolume support on `/mnt/dewpoint`.
2. Generates timestamped pre-sync snapshots in `/mnt/dewpoint/nims/snapshots/`.
3. Performs an archive sync (`-aHEX`) of the validated model profile.
4. Generates post-sync snapshots.
5. If `--keep-cache` is specified, keeps NVMe cache intact; otherwise, reclaims NVMe storage by evicting the source profile from `/workspace`.
6. Prints storage telemetry and verification report.
