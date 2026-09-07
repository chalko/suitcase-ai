# Camp Colt Proxmox VE Operations Runbook

**Target Hypervisor:** `colt-cp-01` (Minisforum MS-01 / UM760 Slim)
**Management IP:** `10.82.0.2/16`
**Web GUI & API:** `https://10.82.0.2:8006/`
**Operating System:** Proxmox VE 9.2.5 (Debian 12, Kernel 7.0.14-6-pve)
**Primary Administrator:** `colt-sysadmin` (`colt-sysadmin-agent`)

---

## 1. Authentication & Access

### OpenSSH CA Host Access

Administrative access to `colt-cp-01` is secured via OpenSSH CA certificates signed by Vault. Passwordless `sudo` is enabled for the service identity.

- **Convenience SSH Wrapper:**

  ```bash
  ./scripts/ssh_colt_cp.sh
  ```

- **Manual SSH:**

  ```bash
  ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent \
      -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent-cert.pub \
      colt-sysadmin-agent@10.82.0.2
  ```

### Proxmox VE API Token

Dedicated automation token configured with the `Administrator` role on `/`:

- **Token ID:** `colt-admin@pve!tofu`
- **Vault Secret Path:** `secret/colt/proxmox` on `http://10.82.0.5:8200`
- **Environment Loader:**

  ```bash
  source ./scripts/load_colt_env.sh
  ```

---

## 2. Infrastructure-as-Code (Terraform)

### Camp Colt Native Workloads (`provision/`)

Manages native Camp Colt Kubernetes nodes and security infrastructure:

- **`colt-vault`** (CT 9190 @ `10.82.0.5/16`)
- **`colt-control-01`** (VM 9110 @ `10.82.20.10/16`)
- **`colt-worker-01`** (VM 9120 @ `10.82.20.13/16`)

Execute plan/apply:

```bash
source ./scripts/load_colt_env.sh
terraform -chdir=provision plan
terraform -chdir=provision apply
```

### Fog Workloads Hypervisor Allocation (`provision/fog/`)

Manages hypervisor-level resource allocations (CPU, RAM, disk, power state) for legacy Fog nodes:

- **`k8s-control-01`** (VM 9010 @ VLAN 613)
- **`k8s-worker-01`** (VM 9020 @ VLAN 613)
- **`vault`** (CT 9090 @ VLAN 613)

> **Operational Scope Boundary:** `colt-sysadmin` manages hypervisor uptime, virtual hardware allocations, and power states in `provision/fog/`. In-guest Talos operating systems and service workloads are managed externally.

Execute plan:

```bash
source ./scripts/load_colt_env.sh
terraform -chdir=provision/fog plan
```

---

## 3. Ansible Fleet Management

Ansible inventory is configured at `provision/ansible/inventory/hosts.yaml`. Run connectivity check:

```bash
ansible -i provision/ansible/inventory/hosts.yaml colt_fleet -m ping
```

---

## 4. Vault Lifecycle & Disaster Recovery

- **Vault Web UI & API:** `http://10.82.0.5:8200`
- **Secrets Storage:** Operator local password store (`pass colt/vault/*`). No credentials or unseal keys are stored in this repository or appliance filesystems.
- **Unseal Procedure (upon container or hypervisor reboot):**

  Operator runs unseal directly from workstation:

  ```bash
  export VAULT_ADDR="http://10.82.0.5:8200"
  pass show colt/vault/unseal_key_1 | vault operator unseal -
  ```

  Or via SSH to `colt-cp-01`:

  ```bash
  KEY=$(pass show colt/vault/unseal_key_1)
  ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent \
      -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent-cert.pub \
      colt-sysadmin-agent@10.82.0.2 \
      "sudo /usr/sbin/pct exec 9190 -- env VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal $KEY"
  ```
