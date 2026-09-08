#!/usr/bin/env bash
# Source this file: source /home/luna-mayor-agent/luna/rigs/suitcase-ai/scripts/load_colt_env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export VAULT_ADDR="http://10.82.0.5:8200"
export PROXMOX_VE_ENDPOINT="https://10.82.0.2:8006/"
export PROXMOX_VE_INSECURE="true"

# Point to Camp Colt client certificate & private key for TLS cert auth
export VAULT_CLIENT_CERT="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt"
export VAULT_CLIENT_KEY="$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key"

# Auto-authenticate via TLS cert if certificate is registered, or use existing token
if [ -f "$VAULT_CLIENT_CERT" ] && [ -f "$VAULT_CLIENT_KEY" ]; then
    if vault login -method=cert >/dev/null 2>&1; then
        echo "Authenticated to colt-vault via TLS certificate ($VAULT_CLIENT_CERT)."
    fi
fi

if [ -n "${VAULT_TOKEN:-}" ] || [ -f "$HOME/.vault-token" ]; then
    PVE_TOKEN=$(vault kv get -field=full_token secret/colt/proxmox 2>/dev/null || true)
    if [ -n "$PVE_TOKEN" ]; then
        export PROXMOX_VE_API_TOKEN="$PVE_TOKEN"
        echo "Loaded Proxmox VE API Token and Vault environment successfully."
    fi
else
    echo "Vault environment configured ($VAULT_ADDR)."
fi
