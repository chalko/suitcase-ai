#!/usr/bin/env bash
# Source this file: source /home/luna-mayor-agent/luna/rigs/suitcase-ai/scripts/load_colt_env.sh

VAULT_CREDS="/home/luna-mayor-agent/luna/rigs/suitcase-ai/agent-keys/vault/colt-vault-credentials.json"

export VAULT_ADDR="http://10.82.0.5:8200"
export PROXMOX_VE_ENDPOINT="https://10.82.0.2:8006/"
export PROXMOX_VE_INSECURE="true"

# Unset legacy Fog mTLS cert overrides if present
unset VAULT_CLIENT_CERT VAULT_CLIENT_KEY VAULT_CACERT

if [ -f "$VAULT_CREDS" ]; then
    ROOT_TOKEN=$(jq -r '.root_token' "$VAULT_CREDS")
    export VAULT_TOKEN="$ROOT_TOKEN"
    
    # Retrieve Proxmox full token from Vault
    PVE_TOKEN=$(vault kv get -field=full_token secret/colt/proxmox 2>/dev/null || true)
    if [ -n "$PVE_TOKEN" ]; then
        export PROXMOX_VE_API_TOKEN="$PVE_TOKEN"
        echo "Loaded Proxmox VE API Token and Vault environment successfully."
    else
        echo "Warning: Could not fetch secret/colt/proxmox from Vault directly."
    fi
else
    echo "Warning: Vault credentials file not found at $VAULT_CREDS"
fi
