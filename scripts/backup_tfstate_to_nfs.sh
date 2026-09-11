#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Camp Colt Terraform State Backup & Dual-Recipient Encryption
# ==============================================================================
# Encrypts provision/terraform.tfstate for both:
#   1. Operator YubiKey: nick@chalko.com
#   2. Appliance Sysadmin: colt-sysadmin@colt.chalko.com
# And stages the encrypted snapshot on the appliance NFS backup storage.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TFSTATE_FILE="$REPO_ROOT/provision/terraform.tfstate"
export GNUPGHOME="$REPO_ROOT/agent-keys/gnupg"
SSH_KEY="$REPO_ROOT/agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent"
REMOTE_HOST="10.82.0.2"
REMOTE_DEST="/local-fast-zfs/colt/backups/tfstate"

if [ ! -f "$TFSTATE_FILE" ]; then
    echo "[-] Error: Terraform state file not found at $TFSTATE_FILE"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TMP_DIR=$(mktemp -d /tmp/tfstate_backup_XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

SNAP_FILE="$TMP_DIR/terraform-tfstate-${TIMESTAMP}.json.gpg"
SHA_FILE="${SNAP_FILE}.sha256"

echo "=== Camp Colt Terraform State Encrypted Backup ==="
echo "[+] Target state: $TFSTATE_FILE"
echo "[+] Using Rig GNUPGHOME: $GNUPGHOME"

# 1. Dual-Recipient GPG Encryption
echo "[+] Encrypting state for: nick@chalko.com and colt-sysadmin@colt.chalko.com..."
gpg --batch --yes --trust-model always --encrypt \
    --recipient "nick@chalko.com" \
    --recipient "colt-sysadmin@colt.chalko.com" \
    --output "$SNAP_FILE" \
    "$TFSTATE_FILE"

# 2. Compute SHA256 Checksum
echo "[+] Computing SHA256 checksum..."
(cd "$TMP_DIR" && sha256sum "$(basename "$SNAP_FILE")" > "$SHA_FILE")

echo "[✓] Encrypted snapshot ready ($(du -h "$SNAP_FILE" | cut -f1))"

# 3. Stage to Appliance NFS Backup Storage on colt-cp-01
echo "[+] Staging snapshot to appliance storage ($REMOTE_HOST:$REMOTE_DEST)..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
    "$SNAP_FILE" "$SHA_FILE" \
    "colt-sysadmin-agent@$REMOTE_HOST:$REMOTE_DEST/"

echo "[✓] State successfully staged to $REMOTE_DEST on colt-cp-01."
echo "[✓] Backup cycle complete."
