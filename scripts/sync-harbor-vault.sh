#!/usr/bin/env bash
# ==============================================================================
# scripts/sync-harbor-vault.sh
# Generate & sync Harbor credentials to HashiCorp Vault and Kubernetes
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/colt-kubeconfig}"
export VAULT_ADDR="${VAULT_ADDR:-https://10.82.0.5:8200}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"
export VAULT_CLIENT_CERT="${VAULT_CLIENT_CERT:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt}"
export VAULT_CLIENT_KEY="${VAULT_CLIENT_KEY:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key}"

echo "Authenticating to Vault via TLS certificate..."
vault login -method=cert >/dev/null

TMP_DIR="$(mktemp -d /tmp/harbor-vault-XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Check if secrets already exist in Vault
if vault kv get secret/colt/harbor >/dev/null 2>&1; then
  echo "Existing Harbor secrets found in Vault secret/colt/harbor. Fetching..."
  ADMIN_PASSWORD="$(vault kv get -field=admin_password secret/colt/harbor)"
  DB_PASSWORD="$(vault kv get -field=database_password secret/colt/harbor)"
  SECRET_KEY="$(vault kv get -field=secret_key secret/colt/harbor)"
  CORE_SECRET="$(vault kv get -field=core_secret secret/colt/harbor)"
  JOBSERVICE_SECRET="$(vault kv get -field=jobservice_secret secret/colt/harbor)"
  REGISTRY_HTTP_SECRET="$(vault kv get -field=registry_http_secret secret/colt/harbor)"
  vault kv get -field=token_private_key secret/colt/harbor > "${TMP_DIR}/private_key.pem"
  vault kv get -field=token_public_cert secret/colt/harbor > "${TMP_DIR}/root.crt"
else
  echo "Generating new cryptographic keys and secrets for Harbor..."
  ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)"
  DB_PASSWORD="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)"
  SECRET_KEY="$(openssl rand -hex 8)" # 16 characters
  CORE_SECRET="$(openssl rand -hex 8)" # 16 characters
  JOBSERVICE_SECRET="$(openssl rand -hex 8)" # 16 characters
  REGISTRY_HTTP_SECRET="$(openssl rand -hex 8)" # 16 characters

  openssl genrsa -out "${TMP_DIR}/private_key.pem" 4096 >/dev/null 2>&1
  openssl req -new -x509 -key "${TMP_DIR}/private_key.pem" \
    -out "${TMP_DIR}/root.crt" -days 3650 \
    -subj "/CN=harbor-token-issuer" >/dev/null 2>&1

  echo "Storing secrets in Vault at secret/colt/harbor..."
  vault kv put secret/colt/harbor \
    admin_user="admin" \
    admin_password="${ADMIN_PASSWORD}" \
    database_user="postgres" \
    database_password="${DB_PASSWORD}" \
    database_name="registry" \
    secret_key="${SECRET_KEY}" \
    core_secret="${CORE_SECRET}" \
    jobservice_secret="${JOBSERVICE_SECRET}" \
    registry_http_secret="${REGISTRY_HTTP_SECRET}" \
    token_private_key="$(cat "${TMP_DIR}/private_key.pem")" \
    token_public_cert="$(cat "${TMP_DIR}/root.crt")" \
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >/dev/null
fi

echo "Ensuring namespace 'harbor' exists in Kubernetes..."
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Provisioning Kubernetes secret 'harbor-secret' in namespace 'harbor'..."
kubectl create secret generic harbor-secret \
  --namespace=harbor \
  --from-literal=HARBOR_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --from-literal=POSTGRESQL_PASSWORD="${DB_PASSWORD}" \
  --from-literal=POSTGRESQL_POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --from-literal=SECRET_KEY="${SECRET_KEY}" \
  --from-literal=CORE_SECRET="${CORE_SECRET}" \
  --from-literal=JOBSERVICE_SECRET="${JOBSERVICE_SECRET}" \
  --from-literal=REGISTRY_HTTP_SECRET="${REGISTRY_HTTP_SECRET}" \
  --from-literal=REGISTRY_SECRET="${CORE_SECRET}" \
  --from-file=private_key.pem="${TMP_DIR}/private_key.pem" \
  --from-file=root.crt="${TMP_DIR}/root.crt" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Copying wildcard TLS secret to namespace 'harbor' if present in ingress-nginx..."
if kubectl get secret colt-chalko-wildcard-tls -n ingress-nginx >/dev/null 2>&1; then
  kubectl get secret colt-chalko-wildcard-tls -n ingress-nginx -o json | \
    jq 'del(.metadata.namespace, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields)' | \
    kubectl apply -n harbor -f - >/dev/null
fi

echo "✔ Successfully synced Harbor credentials to HashiCorp Vault and Kubernetes secret 'harbor-secret'."
