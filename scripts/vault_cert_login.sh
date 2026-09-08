#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Force plain HTTP for colt-vault at 10.82.0.5:8200
export VAULT_ADDR="http://10.82.0.5:8200"
unset VAULT_CACERT

export VAULT_CLIENT_CERT="${VAULT_CLIENT_CERT:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt}"
export VAULT_CLIENT_KEY="${VAULT_CLIENT_KEY:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key}"

echo "Authenticating to HashiCorp Vault at $VAULT_ADDR using TLS client certificate..."
vault login -method=cert
