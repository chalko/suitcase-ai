# Phase 1: Camp Colt Kubernetes Networking, Node Readiness, and Ingress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a fully functional, healthy dual-node Talos Linux Kubernetes cluster (`camp-colt-k8s`) on `colt-cp-01`, deploy the ingress controller on `colt-worker-01`, and configure Vault Kubernetes authentication to enable sovereign workloads to retrieve secrets dynamically.

**Architecture:**

- Hypervisor: `colt-cp-01` (`10.82.0.2` Proxmox VE 9.2)
- Control Plane: `colt-control-01` (VM 9110 @ `10.82.0.10/24`, Talos v1.9.1, 2 vCPU, 2.5GB RAM, 30GB NVMe)
- Worker Node: `colt-worker-01` (VM 9120 @ `10.82.0.13/24`, Talos v1.9.1, 4 vCPU, 6GB RAM, 100GB NVMe)
- Ingress: Envoy / Ingress-NGINX DaemonSet on `colt-worker-01` (`10.82.0.13`)
- Secrets Engine: `colt-vault` (LXC 9190 @ `10.82.0.5:8200`) configured with `auth/kubernetes`

**Tech Stack:** Proxmox VE 9.2, Talos Linux v1.9.1, Kubernetes v1.32.0, Terraform, `talosctl`, `kubectl`, HashiCorp Vault 2.1.0, Helm / K8s manifests.

---

## Root Cause Analysis for Current Node Unreachability

During initial diagnostic screendumps of VM 9110 and VM 9120, Talos console reported:

```text
[talos] task haltIfInstalled (1/1): Talos is already installed to disk but booted from another media and talos.halt_if_installed kernel parameter is set. Please reboot from the disk.
```

Because `provision/colt_vms.tf` specifies `boot_order = ["ide2", "scsi0"]`, every VM power cycle boots into the live installation ISO (`ide2`) first. Since the OS is already installed on `/dev/sda` (`scsi0`), the ISO intentionally halts. Changing the boot order to `["scsi0"]` in Terraform and rebooting the VMs will allow Talos to boot from the installed disk, activate the node configurations, and bind to static IPs `10.82.0.10` and `10.82.0.13`.

---

## Tasks

### Task 1: Remediate Boot Order & Boot Talos Nodes from Disk

**Files:**

- `provision/colt_vms.tf`

- [x] **Step 1: Update VM boot order in Terraform**
      Changed `boot_order = ["ide2", "scsi0"]` to `boot_order = ["scsi0"]` in `provision/colt_vms.tf`.
- [x] **Step 2: Update Proxmox VM configs**
      Updated Proxmox VM boot configuration via `qm set 9110 -boot order=scsi0` and `qm set 9120 -boot order=scsi0`.
- [x] **Step 3: Reboot VM 9110 and VM 9120**
      Clean cold restart executed for VM 9110 and VM 9120 on `colt-cp-01`.
- [x] **Step 4: Verify console output via screendump**
      Confirmed via screendumps that Talos booted from `/dev/sda` disk into `Stage: Running`.

---

### Task 2: Network Reachability & Talos API Verification

**Files:**

- `colt-talosconfig`
- `provision/colt_talos.tf`

- [x] **Step 1: Test IP connectivity from hypervisor and host**
      Pinged `10.82.0.10` and `10.82.0.13` from `colt-cp-01` (0% packet loss, 0.14ms latency).
- [x] **Step 2: Verify Talos API with `talosctl`**
      Verified Talos API at `10.82.0.10` (`v1.9.2`, RBAC enabled).
- [x] **Step 3: Verify worker node via Talos API**
      Verified worker Talos API at `10.82.0.13` (`v1.9.2`, RBAC enabled).

---

### Task 3: Kubernetes Control Plane & Node Readiness

**Files:**

- `colt-kubeconfig`

- [x] **Step 1: Verify Kubernetes API connectivity**
      Updated server endpoint to `https://10.82.0.10:6443` and queried cluster.
- [x] **Step 2: Check node status**
      Both `talos-oxt-m16` (control-plane) and `talos-bvf-2i3` (worker) report status `Ready`.
- [x] **Step 3: Verify Core System Pods**
      All core pods (`coredns`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `kube-proxy`, `kube-flannel`) running cleanly.

---

### Task 4: Ingress Controller & Storage Baseline

**Files:**

- `provision/k8s/ingress/ingress-nginx.yaml`
- `provision/k8s/storage/local-path-storage.yaml`

- [x] **Step 1: Choose and define Ingress Controller manifest**
      Deployed Ingress-NGINX with `hostNetwork: true` on `colt-worker-01` (`10.82.0.13:80`, `10.82.0.13:443`).
- [x] **Step 2: Apply ingress controller to `camp-colt-k8s`**
      Applied manifests and privileged pod security standard to `ingress-nginx` namespace.
- [x] **Step 3: Verify Ingress Pods and HTTP binding**
      Verified `ingress-nginx-controller` is `1/1 Running` and `curl http://10.82.0.13/` returns HTTP 404 (NGINX default backend).
- [x] **Step 4: Deploy Local Path StorageClass**
      Deployed Rancher `local-path-provisioner` and verified `storageclass.storage.k8s.io/local-path` is active and ready.

---

### Task 5: Configure Vault Kubernetes Authentication Backend

**Files:**

- `provision/k8s/vault/vault-auth-rbac.yaml`
- `scripts/configure_vault_k8s_auth.sh`

- [x] **Step 1: Create Kubernetes ServiceAccount and Token for Vault**
      Created `vault-auth` ServiceAccount, ClusterRoleBinding to `system:auth-delegator`, and `vault-auth-token` Secret in `kube-system`.
- [x] **Step 2: Automation script for `auth/kubernetes` in `colt-vault`**
      Created `scripts/configure_vault_k8s_auth.sh` to configure Vault Kubernetes auth pointing to `https://10.82.0.10:6443` using the operator's Vault token.
- [ ] **Step 3: Execute `scripts/configure_vault_k8s_auth.sh` with operator token**
      Pending operator execution with local password store (`VAULT_TOKEN=$(pass show colt/vault/root_token)`).

---

### Task 6: Documentation & State Check-in

**Files:**

- `docs/PROXMOX_OPERATIONS.md`
- `README.md`

- [ ] **Step 1: Update documentation with verified node status and ingress endpoints**
- [ ] **Step 2: Run pre-commit hooks and commit changes cleanly**
