# Camp Colt Proxmox VE Operations Runbook

**Target Hypervisor:** `colt-cp-01` (Minisforum MS-01) **Management IP:**
`10.82.0.2` **Web GUI & API:** `https://10.82.0.2:8006/` **Operating System:**
Proxmox VE 9.2.5 (Debian 12, Kernel 7.0.14-6-pve) **Primary Administrator:**
`colt-sysadmin` (`colt-sysadmin-agent`)

---

## 1. Authentication & Access

### OpenSSH CA Host Access

Administrative access to `colt-cp-01` is secured via OpenSSH CA certificates.
Passwordless `sudo` is enabled.

- **Convenience SSH Wrapper:**

  ```bash
  /home/luna-mayor-agent/luna/rigs/suitcase-ai/scripts/ssh_colt_cp.sh
  ```

- **Manual SSH:**

  ```bash
  ssh -i ~/.ssh/agents/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.2
  ```

### Proxmox VE API Token

Dedicated OpenTofu/automation token configured with full `Administrator` role on
`/`:

- **Token ID:** `colt-admin@pve!tofu`
- **Vault Secret Path:** `secret/colt/proxmox` on `http://10.82.0.5:8200`
- **Environment Loader:**

  ```bash
  source /home/luna-mayor-agent/luna/rigs/suitcase-ai/scripts/load_colt_env.sh
  ```

---

## 2. Infrastructure-as-Code (Terraform)

### Camp Colt Native Workloads (`provision/`)

Manages native Camp Colt Kubernetes nodes and security infrastructure:

- **`colt-vault`** (CT 9190 @ `10.82.0.5/24`)
- **`colt-control-01`** (VM 9110 @ `10.82.20.2/24`)
- **`colt-worker-01`** (VM 9120 @ `10.82.20.13/24`)

Execute plan/apply:

```bash
cd /home/luna-mayor-agent/luna/rigs/suitcase-ai/provision
source ../scripts/load_colt_env.sh
terraform plan
terraform apply
```

### Fog Workloads Hypervisor Allocation (`provision/fog/`)

Manages hypervisor-level resource allocations (CPU, RAM, disk, power state) for
legacy Fog nodes:

- **`k8s-control-01`** (VM 9010)
- **`k8s-worker-01`** (VM 9020)
- **`vault`** (CT 9090)

> **Operational Scope Boundary:** `colt-sysadmin` manages hypervisor uptime,
> virtual hardware allocations, and power states in `provision/fog/`. In-guest
> Talos operating systems and Kubernetes service workloads remain within the
> operational domain of `fog/kaylee`.

Execute plan:

```bash
cd /home/luna-mayor-agent/luna/rigs/suitcase-ai/provision/fog
source ../../scripts/load_colt_env.sh
terraform plan
```

---

## 3. Ansible Fleet Management

Ansible inventory is pre-configured at `provision/ansible/inventory/hosts.yaml`.
Run ping check:

```bash
ansible -i /home/luna-mayor-agent/luna/rigs/suitcase-ai/provision/ansible/inventory/hosts.yaml colt_fleet -m ping
```

---

## 4. Vault Lifecycle & Disaster Recovery

- **Vault Web UI & API:** `http://10.82.0.5:8200`
- **Credentials:**
  `/home/luna-mayor-agent/luna/rigs/suitcase-ai/agent-keys/vault/colt-vault-credentials.json`
- **Unseal Procedure (upon container or hypervisor reboot):**

  ```bash
  KEY=$(jq -r '.unseal_keys_b64[0]' /home/luna-mayor-agent/luna/rigs/suitcase-ai/agent-keys/vault/colt-vault-credentials.json)
  ssh -i ~/.ssh/agents/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.2 \
    "sudo pct exec 9190 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal $KEY"
  ```
