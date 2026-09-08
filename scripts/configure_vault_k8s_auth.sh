#!/usr/bin/env bash
set -euo pipefail

# Configure HashiCorp Vault Kubernetes Authentication Backend for Camp Colt
# Usage:
#   export VAULT_TOKEN=$(pass show colt/vault/root_token)
#   bash scripts/configure_vault_k8s_auth.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Always use colt-kubeconfig by default
KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/colt-kubeconfig}"
if [ ! -f "$KUBECONFIG" ] && [ -f "$REPO_ROOT/colt-kubeconfig" ]; then
    KUBECONFIG="$REPO_ROOT/colt-kubeconfig"
fi

# Force HTTP endpoint for colt-vault (it listens on plain HTTP at 10.82.0.5:8200)
export VAULT_ADDR="http://10.82.0.5:8200"
unset VAULT_CACERT VAULT_CLIENT_CERT VAULT_CLIENT_KEY

if [ -z "${VAULT_TOKEN:-}" ]; then
    if command -v pass >/dev/null 2>&1; then
        VAULT_TOKEN=$(pass show colt/vault/root_token 2>/dev/null || true)
    fi
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: VAULT_TOKEN is not set and could not be retrieved from pass."
    echo "Run: export VAULT_TOKEN=\$(pass show colt/vault/root_token)"
    exit 1
fi

if [ ! -f "$KUBECONFIG" ]; then
    echo "Error: Kubeconfig not found at $KUBECONFIG"
    exit 1
fi

echo "Ensuring vault-auth RBAC is applied in camp-colt-k8s..."
kubectl --kubeconfig "$KUBECONFIG" apply -f "$REPO_ROOT/provision/k8s/vault/vault-auth-rbac.yaml"

echo "Retrieving cluster CA and vault-auth token from camp-colt-k8s..."
K8S_CA_CERT="$(kubectl --kubeconfig "$KUBECONFIG" get secret vault-auth-token -n kube-system -o jsonpath='{.data.ca\.crt}' | base64 -d)"
TOKEN_REVIEWER_JWT="$(kubectl --kubeconfig "$KUBECONFIG" get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)"

export VAULT_TOKEN

echo "Enabling auth/kubernetes in colt-vault ($VAULT_ADDR)..."
vault auth enable kubernetes 2>/dev/null || echo "auth/kubernetes already enabled."

echo "Configuring auth/kubernetes/config pointing to https://10.82.0.10:6443..."
vault write auth/kubernetes/config \
    kubernetes_host="https://10.82.0.10:6443" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    disable_iss_validation=true

echo "Writing colt-workload policy..."
vault policy write colt-workload - <<'EOF'
path "secret/data/colt/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/colt/*" {
  capabilities = ["read", "list"]
}
EOF

echo "Creating auth/kubernetes/role/colt-workload..."
vault write auth/kubernetes/role/colt-workload \
    bound_service_account_names="*" \
    bound_service_account_namespaces="default,kube-system" \
    policies="colt-workload" \
    ttl=24h

echo "Successfully configured Vault Kubernetes auth for camp-colt-k8s."
