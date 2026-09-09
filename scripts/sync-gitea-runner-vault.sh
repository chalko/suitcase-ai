#!/usr/bin/env bash
# ==============================================================================
# scripts/sync-gitea-runner-vault.sh
# Syncs Gitea runner registration token to Vault and provisions K8s secret
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export VAULT_ADDR="${VAULT_ADDR:-https://10.82.0.5:8200}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"
export VAULT_CLIENT_CERT="${VAULT_CLIENT_CERT:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt}"
export VAULT_CLIENT_KEY="${VAULT_CLIENT_KEY:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key}"

echo "Authenticating to Vault..."
vault login -method=cert >/dev/null

echo "Retrieving Gitea admin token from Vault..."
ADMIN_TOKEN="$(vault kv get -field=admin_token secret/colt/gitea)"

echo "Fetching runner registration token from Gitea API..."
REG_TOKEN="$(curl -sk -H "Authorization: token ${ADMIN_TOKEN}" \
  -H "Accept: application/json" \
  https://gitea.colt.chalko.com/api/v1/orgs/colt/actions/runners/registration-token | jq -r '.token')"

if [ -z "${REG_TOKEN}" ] || [ "${REG_TOKEN}" = "null" ]; then
  echo "❌ Failed to retrieve runner registration token." >&2
  exit 1
fi

echo "Storing registration token in Vault (secret/colt/gitea_runner)..."
vault kv put secret/colt/gitea_runner \
  token="${REG_TOKEN}" \
  registration_token="${REG_TOKEN}" \
  instance_url="https://gitea.colt.chalko.com" \
  updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >/dev/null

echo "Provisioning Kubernetes Secret 'gitea-runner-secret' in namespace 'gitea'..."
kubectl create secret generic gitea-runner-secret \
  --namespace=gitea \
  --from-literal=token="${REG_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "✔ Successfully synced Gitea runner registration token to Vault and Kubernetes."
