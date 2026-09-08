#!/usr/bin/env bash
set -euo pipefail

# Create remote repository in Gitea and push current suitcase-ai repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export VAULT_ADDR="https://10.82.0.5:8200"
export VAULT_SKIP_VERIFY="true"
export VAULT_CLIENT_CERT="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt"
export VAULT_CLIENT_KEY="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key"

echo "Retrieving Gitea credentials from Vault..."
vault login -method=cert >/dev/null

ADMIN_TOKEN=$(vault kv get -field=admin_token secret/colt/gitea)
ADMIN_USER=$(vault kv get -field=admin_user secret/colt/gitea)

echo "Checking if repository colt/suitcase-ai exists..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: gitea.colt.internal" \
    -H "Authorization: token $ADMIN_TOKEN" \
    http://10.82.0.13/api/v1/repos/colt/suitcase-ai || true)

if [ "$HTTP_STATUS" != "200" ]; then
    echo "Creating repository colt/suitcase-ai..."
    curl -s -f -X POST \
        -H "Host: gitea.colt.internal" \
        -H "Authorization: token $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name":"suitcase-ai","description":"Camp Colt Sovereign Infrastructure & Workloads","private":false,"auto_init":false}' \
        http://10.82.0.13/api/v1/orgs/colt/repos >/dev/null
    echo "Repository colt/suitcase-ai created."
else
    echo "Repository colt/suitcase-ai already exists."
fi

echo "Configuring git remote 'colt'..."
if git -C "$REPO_ROOT" remote | grep -q "^colt$"; then
    git -C "$REPO_ROOT" remote set-url colt "http://10.82.0.13/colt/suitcase-ai.git"
else
    git -C "$REPO_ROOT" remote add colt "http://10.82.0.13/colt/suitcase-ai.git"
fi

echo "Pushing main branch to in-cluster Gitea..."
git -C "$REPO_ROOT" -c http.extraHeader="Authorization: token $ADMIN_TOKEN" push colt main -u

echo "Repository successfully synchronized to in-cluster Gitea!"
