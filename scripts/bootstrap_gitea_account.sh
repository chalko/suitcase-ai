#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Gitea Administrator, Organization, Access Token, and Vault Record
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/colt-kubeconfig}"

export VAULT_ADDR="https://10.82.0.5:8200"
export VAULT_SKIP_VERIFY="true"
export VAULT_CLIENT_CERT="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt"
export VAULT_CLIENT_KEY="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key"

echo "Authenticating to Vault via TLS certificate..."
vault login -method=cert >/dev/null

ADMIN_USER="colt-admin"
ADMIN_EMAIL="admin@colt.internal"
ADMIN_PASS="$(openssl rand -hex 16)"

echo "Checking if admin user $ADMIN_USER already exists in Gitea..."
if ! kubectl --kubeconfig "$KUBECONFIG" -n gitea exec deploy/gitea -c gitea -- gitea admin user list | grep -q "$ADMIN_USER"; then
    echo "Creating admin user $ADMIN_USER..."
    kubectl --kubeconfig "$KUBECONFIG" -n gitea exec deploy/gitea -c gitea -- \
        gitea admin user create --username "$ADMIN_USER" --password "$ADMIN_PASS" --email "$ADMIN_EMAIL" --admin
    echo "Admin user $ADMIN_USER created."
else
    echo "Admin user $ADMIN_USER already exists. Updating password..."
    kubectl --kubeconfig "$KUBECONFIG" -n gitea exec deploy/gitea -c gitea -- \
        gitea admin user change-password --username "$ADMIN_USER" --password "$ADMIN_PASS"
fi

echo "Generating personal access token for $ADMIN_USER..."
TOKEN_OUTPUT="$(kubectl --kubeconfig "$KUBECONFIG" -n gitea exec deploy/gitea -c gitea -- \
    gitea admin user generate-access-token --username "$ADMIN_USER" --token-name "colt-deploy-$(date +%s)" --scopes "all" --raw)"
ADMIN_TOKEN="$(echo "$TOKEN_OUTPUT" | tr -d '\r\n')"

echo "Creating 'colt' organization if not present..."
# Use Gitea REST API via curl inside or through Ingress
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: gitea.colt.internal" -H "Authorization: token $ADMIN_TOKEN" http://10.82.0.13/api/v1/orgs/colt || true)
if [ "$HTTP_STATUS" != "200" ]; then
    curl -s -f -X POST -H "Host: gitea.colt.internal" \
         -H "Authorization: token $ADMIN_TOKEN" \
         -H "Content-Type: application/json" \
         -d '{"username":"colt","full_name":"Camp Colt","description":"Camp Colt Sovereign Organization","visibility":"public"}' \
         http://10.82.0.13/api/v1/orgs >/dev/null
    echo "Organization 'colt' created."
else
    echo "Organization 'colt' already exists."
fi

echo "Storing Gitea credentials in HashiCorp Vault (secret/colt/gitea)..."
vault kv put secret/colt/gitea \
    admin_user="$ADMIN_USER" \
    admin_password="$ADMIN_PASS" \
    admin_token="$ADMIN_TOKEN" \
    http_url="http://gitea.colt.internal" \
    clone_url="http://10.82.0.13/colt/suitcase-ai.git" \
    updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >/dev/null

echo "Vault secret secret/colt/gitea successfully updated."
vault kv get -field=updated_at secret/colt/gitea
echo "Gitea account bootstrapping complete!"
