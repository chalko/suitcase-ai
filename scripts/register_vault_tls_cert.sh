#!/usr/bin/env bash
set -euo pipefail

# Register Camp Colt TLS Client Certificate in HashiCorp Vault
# Usage:
#   export VAULT_TOKEN=$(pass show colt/vault/root_token)
#   bash scripts/register_vault_tls_cert.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Force HTTP endpoint for colt-vault (it listens on plain HTTP at 10.82.0.5:8200)
export VAULT_ADDR="http://10.82.0.5:8200"
unset VAULT_CACERT VAULT_CLIENT_CERT VAULT_CLIENT_KEY

CERT_PATH="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt"

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

if [ ! -f "$CERT_PATH" ]; then
    echo "Error: TLS certificate not found at $CERT_PATH"
    exit 1
fi

export VAULT_TOKEN

echo "Ensuring auth/cert is enabled in colt-vault ($VAULT_ADDR)..."
vault auth enable cert 2>/dev/null || echo "auth/cert already enabled."

echo "Writing colt-owner policy..."
vault policy write colt-owner - <<'EOF'
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
path "ssh/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

echo "Registering colt-sysadmin-agent certificate in auth/cert/certs/colt-sysadmin-agent..."
vault write auth/cert/certs/colt-sysadmin-agent \
    display_name="colt-sysadmin-agent" \
    policies="colt-owner" \
    certificate=@"$CERT_PATH" \
    ttl=24h

echo "Registration complete! You can now authenticate using:"
echo "  export VAULT_ADDR=\"$VAULT_ADDR\""
echo "  export VAULT_CLIENT_CERT=\"$CERT_PATH\""
echo "  export VAULT_CLIENT_KEY=\"\${CERT_PATH%.crt}.key\""
echo "  vault login -method=cert"
