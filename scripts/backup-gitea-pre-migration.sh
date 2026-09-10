#!/usr/bin/env bash
# ==============================================================================
# Camp Colt Sovereign Infrastructure — Gitea Pre-Migration Data Snapshot
# ==============================================================================
set -euo pipefail

BACKUP_DIR="${1:-/tmp/gitea-pre-migration-backup-$(date +%Y%m%d%H%M%S)}"
KUBECONFIG="${KUBECONFIG:-colt-kubeconfig}"
VAULT_ADDR="${VAULT_ADDR:-https://10.82.0.5:8200}"
export VAULT_SKIP_VERIFY=true

echo "[+] Starting Gitea Pre-Migration Data Snapshot..."
mkdir -p "${BACKUP_DIR}"

GITEA_POD=$(kubectl --kubeconfig "${KUBECONFIG}" get pod -n gitea -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
if [ -z "${GITEA_POD}" ]; then
  echo "[-] ERROR: Gitea pod not found in namespace gitea!"
  exit 1
fi
echo "[+] Found running Gitea pod: ${GITEA_POD}"

echo "[+] Backing up SQLite database..."
kubectl --kubeconfig "${KUBECONFIG}" exec -n gitea "${GITEA_POD}" -c gitea -- \
  sqlite3 /data/gitea/gitea.db ".backup '/tmp/gitea.db.bak'" 2>/dev/null || \
  kubectl --kubeconfig "${KUBECONFIG}" exec -n gitea "${GITEA_POD}" -c gitea -- \
  cp /data/gitea/gitea.db /tmp/gitea.db.bak

kubectl --kubeconfig "${KUBECONFIG}" cp -n gitea "${GITEA_POD}:/tmp/gitea.db.bak" "${BACKUP_DIR}/gitea.db" -c gitea
kubectl --kubeconfig "${KUBECONFIG}" exec -n gitea "${GITEA_POD}" -c gitea -- rm -f /tmp/gitea.db.bak

echo "[+] Backing up app.ini..."
kubectl --kubeconfig "${KUBECONFIG}" cp -n gitea "${GITEA_POD}:/data/gitea/conf/app.ini" "${BACKUP_DIR}/app.ini" -c gitea 2>/dev/null || true

echo "[+] Backing up Git repositories archive..."
kubectl --kubeconfig "${KUBECONFIG}" exec -n gitea "${GITEA_POD}" -c gitea -- \
  tar -czf /tmp/repos.tar.gz -C /data/git/repositories .
kubectl --kubeconfig "${KUBECONFIG}" cp -n gitea "${GITEA_POD}:/tmp/repos.tar.gz" "${BACKUP_DIR}/repositories.tar.gz" -c gitea
kubectl --kubeconfig "${KUBECONFIG}" exec -n gitea "${GITEA_POD}" -c gitea -- rm -f /tmp/repos.tar.gz

echo "[+] Verifying HashiCorp Vault secrets..."
if vault kv get secret/colt/gitea > /dev/null 2>&1; then
  echo "    ✔ Vault secret 'secret/colt/gitea' verified."
else
  echo "    ⚠ WARNING: Could not verify 'secret/colt/gitea'."
fi

if vault kv get secret/colt/gitea_runner > /dev/null 2>&1; then
  echo "    ✔ Vault secret 'secret/colt/gitea_runner' verified."
else
  echo "    ⚠ WARNING: Could not verify 'secret/colt/gitea_runner'."
fi

echo "[+] Calculating backup checksums..."
cd "${BACKUP_DIR}"
sha256sum * > SHA256SUMS

echo "[+] Gitea snapshot successfully created at: ${BACKUP_DIR}"
ls -lh "${BACKUP_DIR}"
cat "${BACKUP_DIR}/SHA256SUMS"
