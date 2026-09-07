#!/usr/bin/env bash
# Source this file: source /home/luna-mayor-agent/luna/rigs/suitcase-ai/scripts/load_colt_env.sh

export VAULT_ADDR="http://10.82.0.5:8200"
export PROXMOX_VE_ENDPOINT="https://10.82.0.2:8006/"
export PROXMOX_VE_INSECURE="true"

# Unset legacy Fog mTLS cert overrides if present
unset VAULT_CLIENT_CERT VAULT_CLIENT_KEY VAULT_CACERT

if [ -n "$VAULT_TOKEN" ]; then
    # Retrieve Proxmox full token from Vault using provided VAULT_TOKEN
    PVE_TOKEN=$(vault kv get -field=full_token secret/colt/proxmox 2>/dev/null || true)
    if [ -n "$PVE_TOKEN" ]; then
        export PROXMOX_VE_API_TOKEN="$PVE_TOKEN"
        echo "Loaded Proxmox VE API Token and Vault environment successfully."
    else
        echo "Vault address set ($VAULT_ADDR). Could not fetch secret/colt/proxmox from Vault."
    fi
else
    echo "Vault environment set ($VAULT_ADDR)."
    echo "Note: VAULT_TOKEN not exported. Provide VAULT_TOKEN (e.g. from local password store) to fetch Proxmox credentials."
fi
