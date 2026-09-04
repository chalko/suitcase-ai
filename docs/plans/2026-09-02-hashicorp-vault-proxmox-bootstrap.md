# HashiCorp Vault Bootstrap on Proxmox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap and configure a production-hardened, zero-plaintext HashiCorp Vault instance on Proxmox VE for Camp Colt (`colt-vault` @ `10.82.0.5`), supporting KV secrets and OpenSSH dynamic certificate minting.

**Architecture:** HashiCorp Vault deployed either as a containerized workload (using the official `hashicorp/vault` Docker image) or native LXC service on Proxmox VE (`colt-cp-01` @ `10.82.0.2`), isolated on the `10.82.0.0/24` subnet, with persistent file-backed storage, Shamir unseal, KV v2 engine, and SSH CA signing engine.

**Tech Stack:** Proxmox VE 9.2, Docker / LXC container, HashiCorp Vault 2.1.0 (`hashicorp/vault`), OpenSSH CA Engine, Systemd, Bash / Python automation.

**Spec:** `/home/luna-mayor-agent/luna/rigs/scai/plans/0.1/ssh_vault_phase_0_1.md`

## Global Constraints
- Target Node: `colt-cp-01` (`10.82.0.2`) hosting `colt-vault` (LXC/VM 9190 @ `10.82.0.5`)
- Storage Backend: `/opt/vault/data` (persistent, mode `0700`, owned by `vault:vault` or container UID `100`)
- Security: Never expose or commit plaintext unseal keys, root tokens, or private keys to git (`agent-keys/` strictly gitignored, mode `0600`)
- Network: `10.82.0.5:8200` (API/UI), strictly bound to Camp Colt appliance network (`10.82.0.0/24`)
- Capabilities: If running in Docker/LXC, require `--cap-add=IPC_LOCK` or `disable_mlock = true`

---

### Task 1: Container Runtime & Storage Scaffolding

**Files:**
- Create: `/etc/vault.d/vault.hcl` on `colt-vault` (CT 9190)
- Create: `/opt/vault/data` and `/opt/vault/config` on `colt-vault`
- Modify: `/home/luna-mayor-agent/luna/rigs/suitcase-ai/.gitignore`

**Interfaces:**
- Consumes: SSH CA access to `colt-cp-01` (`10.82.0.2`)
- Produces: Persistent directory structure and HCL configuration

- [ ] **Step 1: Create storage directory structure and permissions**

```bash
ssh colt-sysadmin-agent@10.82.0.2 "sudo /usr/sbin/pct exec 9190 -- bash -c 'mkdir -p /opt/vault/data /opt/vault/config /etc/vault.d && chown -R vault:vault /opt/vault /etc/vault.d && chmod 700 /opt/vault/data'"
```

- [ ] **Step 2: Deploy declarative `vault.hcl` configuration**

```hcl
ui = true
disable_mlock = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://10.82.0.5:8200"
cluster_addr = "http://10.82.0.5:8201"
```

- [ ] **Step 3: Enable and start Vault daemon**

```bash
ssh colt-sysadmin-agent@10.82.0.2 "sudo /usr/sbin/pct exec 9190 -- bash -c 'systemctl enable --now vault && systemctl status vault --no-pager'"
```

---

### Task 2: Vault Initialization & Secret Unseal Automation

**Files:**
- Create: `suitcase-ai/agent-keys/vault/colt-vault-credentials.json` (mode `0600`, gitignored)
- Create: `suitcase-ai/scripts/unseal_vault.py`

**Interfaces:**
- Consumes: Running uninitialized Vault at `http://10.82.0.5:8200`
- Produces: Initialized and unsealed Vault with stored credentials

- [ ] **Step 1: Initialize Vault with single-share Shamir key**

```bash
ssh colt-sysadmin-agent@10.82.0.2 "sudo /usr/sbin/pct exec 9190 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator init -format=json -key-shares=1 -key-threshold=1" > agent-keys/vault/colt-vault-credentials.json
chmod 600 agent-keys/vault/colt-vault-credentials.json
```

- [ ] **Step 2: Unseal Vault using secure script**

```python
import json, subprocess
with open('agent-keys/vault/colt-vault-credentials.json') as f:
    unseal_key = json.load(f)['unseal_keys_b64'][0]
subprocess.run(['ssh', 'colt-sysadmin-agent@10.82.0.2', f'sudo /usr/sbin/pct exec 9190 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal {unseal_key}'], check=True)
```

- [ ] **Step 3: Verify unseal status**

```bash
ssh colt-sysadmin-agent@10.82.0.2 "sudo /usr/sbin/pct exec 9190 -- env VAULT_ADDR=http://127.0.0.1:8200 vault status"
```
Expected: `Initialized: true`, `Sealed: false`

---

### Task 3: Secrets Engine Configuration & SSH CA Minting

**Files:**
- Create: `suitcase-ai/agent-keys/vault/colt_vault_ssh_ca.pub`
- Create: `/etc/ssh/trusted-user-ca-keys.pem` on target nodes

**Interfaces:**
- Consumes: Unsealed Vault root token
- Produces: Enabled `secret/` (KV v2) and `ssh/` (SSH CA) engines, `agent-runner` role, `scai-agent-ssh` policy

- [ ] **Step 1: Enable KV-v2 and SSH Secrets Engines**

```bash
vault secrets enable -path=secret kv-v2
vault secrets enable -path=ssh ssh
vault write ssh/config/ca generate_signing_key=true
```

- [ ] **Step 2: Configure `agent-runner` signing role**

```json
{
  "key_type": "ca",
  "allow_user_certificates": true,
  "allowed_users": "agent-runner,colt-sysadmin-agent,sysadmin-agent,sysadmin",
  "allowed_domains": "colt.internal,scai.local,chalko.com",
  "allow_bare_domains": true,
  "allowed_extensions": "permit-pty,permit-user-rc",
  "default_extensions": {"permit-pty": "", "permit-user-rc": ""},
  "default_user": "colt-sysadmin-agent",
  "ttl": "1h",
  "max_ttl": "4h"
}
```

- [ ] **Step 3: Export Vault SSH CA public key and test ephemeral cert minting**

```bash
vault read -field=public_key ssh/config/ca > agent-keys/vault/colt_vault_ssh_ca.pub
vault write -field=signed_key ssh/sign/agent-runner public_key=@agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent.pub > /tmp/test-cert.pub
ssh-keygen -L -f /tmp/test-cert.pub
```
Expected: Valid OpenSSH certificate signed by Vault CA.

---

### Task 4: Docker Containerized Option (Alternative Deployment)

**Files:**
- Create: `suitcase-ai/docker/vault/docker-compose.yml`

**Interfaces:**
- Consumes: Docker engine with `IPC_LOCK` capability
- Produces: Portable containerized Vault instance matching official image specifications

- [ ] **Step 1: Write `docker-compose.yml` for official `hashicorp/vault` image**

```yaml
version: '3.8'
services:
  vault:
    image: hashicorp/vault:latest
    container_name: colt-vault
    restart: unless-stopped
    cap_add:
      - IPC_LOCK
    environment:
      VAULT_ADDR: 'http://0.0.0.0:8200'
      VAULT_API_ADDR: 'http://10.82.0.5:8200'
    volumes:
      - /opt/vault/config:/vault/config:ro
      - /opt/vault/data:/vault/file:rw
    ports:
      - "8200:8200"
      - "8201:8201"
    command: server
```

