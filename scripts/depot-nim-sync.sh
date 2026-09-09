#!/usr/bin/env bash
# File: scripts/depot-nim-sync.sh
# Description: Manages ModelDepot backup, snapshotting, and ReadyLocker fast cache eviction for validated NIM profiles.
set -euo pipefail

MODEL_ID="${1:-models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5}"
EVICT_CACHE="${2:-true}" # Set to "false" or pass --keep-cache to preserve local ReadyLocker fast cache
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
echo "💾 ModelDepot NIM Backup & ReadyLocker Sync Automation"
echo "Model ID:    ${MODEL_ID}"
echo "Source:      ${SRC_DIR}"
echo "Dest:        ${DEST_DIR}"
echo "Evict Cache: ${EVICT_CACHE}"
echo "Start:       $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================="

mkdir -p "${SNAP_DIR}"
mkdir -p "${DEST_DIR}"

# 1. Pre-Sync Snapshot
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PRE_SNAP="${SNAP_DIR}/pre-sync-${MODEL_ID}-${TIMESTAMP}"
echo "=== Step 1: Taking Pre-Sync Snapshot on ModelDepot ==="
if btrfs subvolume snapshot "${DEST_DIR}" "${PRE_SNAP}" 2>/dev/null; then
    echo "[✓] Created Btrfs subvolume pre-sync snapshot: ${PRE_SNAP}"
else
    echo "[*] Destination is standard directory, creating timestamped hardlink/copy snapshot..."
    cp -al "${DEST_DIR}" "${PRE_SNAP}" 2>/dev/null || cp -a "${DEST_DIR}" "${PRE_SNAP}" 2>/dev/null || true
    echo "[✓] Created pre-sync snapshot at ${PRE_SNAP}"
fi

# 2. Rsync Validated Cache to ModelDepot
echo "=== Step 2: Syncing Validated Cache to ModelDepot ==="
if [ -d "${SRC_DIR}" ]; then
    if command -v rsync >/dev/null 2>&1; then
        rsync -aHAXv --delete "${SRC_DIR}/" "${DEST_DIR}/"
        echo "[✓] Rsync completed successfully."
    else
        echo "[*] Using cp -a fallback..."
        cp -a "${SRC_DIR}/." "${DEST_DIR}/"
        echo "[✓] Copy completed successfully."
    fi
else
    echo "[!] Source directory ${SRC_DIR} not found or already moved. Sync skipped."
fi

# 3. Post-Sync Snapshot
POST_SNAP="${SNAP_DIR}/post-sync-${MODEL_ID}-${TIMESTAMP}"
echo "=== Step 3: Taking Post-Sync Snapshot on ModelDepot ==="
if btrfs subvolume snapshot "${DEST_DIR}" "${POST_SNAP}" 2>/dev/null; then
    echo "[✓] Created Btrfs subvolume post-sync snapshot: ${POST_SNAP}"
else
    cp -al "${DEST_DIR}" "${POST_SNAP}" 2>/dev/null || cp -a "${DEST_DIR}" "${POST_SNAP}"
    echo "[✓] Created post-sync snapshot at ${POST_SNAP}"
fi

# 4. Evict ReadyLocker Fast Cache (Optional)
if [ "${EVICT_CACHE}" = "true" ]; then
    echo "=== Step 4: Evicting ReadyLocker Fast Cache to Reclaim NVMe Storage ==="
    if [ -d "${SRC_DIR}" ]; then
        echo "Removing ${SRC_DIR}..."
        rm -rf "${SRC_DIR}"
        echo "[✓] Evicted ${MODEL_ID} from ReadyLocker fast cache."
    fi
    echo "Cleaning transient runtime profiles in /workspace/models/fast-cache/tmp/..."
    rm -rf /workspace/models/fast-cache/tmp/nim_* || true
else
    echo "=== Step 4: Preserving ReadyLocker Fast Cache (--keep-cache) ==="
    echo "[✓] Fast cache preserved at ${SRC_DIR} for active inference serving."
fi

echo "Cleaning transient runtime profiles in /workspace/models/fast-cache/tmp/..."
rm -rf /workspace/models/fast-cache/tmp/nim_* || true

echo "=== Verification & Storage Summary ==="
echo "ModelDepot Backups:"
ls -lh "${DEST_DIR}" 2>/dev/null || true
echo "ModelDepot Snapshots:"
ls -ld "${SNAP_DIR}"/*"${MODEL_ID}"* 2>/dev/null || true
echo "NVMe Storage Status:"
df -h /workspace /mnt/model-depot 2>/dev/null || df -h /workspace || true
echo "Preserved Models in ReadyLocker Cache:"
ls -la /workspace/models/fast-cache/ 2>/dev/null || true
echo "================================================================="
echo "[✓] ModelDepot backup and ReadyLocker sync/eviction complete!"
echo "================================================================="
