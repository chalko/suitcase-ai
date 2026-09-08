# Suitcase AI (Camp Colt)

Declarative infrastructure and operational tooling for an ultra-compact 10" mini-rack compute cluster running Proxmox VE, Talos Linux Kubernetes, and local LLM acceleration.

---

## 🧭 What This Project Is

This repository contains the Terraform manifests, Ansible playbooks, and security configurations used to manage **Camp Colt**—a self-contained homelab compute cluster built into an 8U 10-inch mini-rack.

The goal is a compact, power-efficient, and quiet homelab setup designed to run on a standard 120V / 15A household circuit while supporting:

- **Immutable Kubernetes:** Talos Linux nodes configured purely via API (no in-guest SSH or package managers).
- **Zero-Standing Secrets:** Host access via ephemeral OpenSSH CA client certificates signed by HashiCorp Vault.
- **Local AI Acceleration:** Dedicated NVIDIA Grace Blackwell node paired with low-power x86 hypervisor compute.

---

## 🛠️ Physical 10" Mini-Rack Layout

The cluster is housed in a 3D-printed 10-inch modular rack ([ButterflyRack](https://github.com/axiopaladin/ButterflyRack)):

```text
┌─────────────────────────────────────────────────────────────┐
│ 8U 10" Mini-Rack (axiopaladin/ButterflyRack w/ Metal Rails) │
├─────┬───────────────────────────────────────────────────────┤
│ 7-8U│ ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10, 128GB) │
│     │ + 4TB USB NVMe SSD (Local Model Weight Cache)         │
├─────┼───────────────────────────────────────────────────────┤
│ 6U  │ 14-Port Keystone Patch Panel                          │
├─────┼───────────────────────────────────────────────────────┤
│ 5U  │ 1G Managed Switch (10.82.0.0/16 Network Fabric)       │
├─────┼───────────────────────────────────────────────────────┤
│ 3-4U│ Minisforum UM760 Slim (AMD Ryzen 5 7640HS, 32GB DDR5) │
│     │ [ Proxmox VE 9.2 Hypervisor • colt-cp-01 ]            │
├─────┼───────────────────────────────────────────────────────┤
│ 1-2U│ [ Base Shelf / PDU Power Distribution & Bricks ]      │
└─────┴───────────────────────────────────────────────────────┘
```

### Physical Hardware Bill of Materials

| Component              | Hardware Model                                                | Key Specifications                                  | Physical Role                                          |   State   |
| :--------------------- | :------------------------------------------------------------ | :-------------------------------------------------- | :----------------------------------------------------- | :-------: |
| **Chassis**            | [ButterflyRack](https://github.com/axiopaladin/ButterflyRack) | 8U 10" mini-rack with metal rails                   | Structural enclosure                                   | 🟢 Active |
| **GPU Node**           | ASUS Ascent GX10                                              | NVIDIA Grace Blackwell GB10, 128GB unified RAM      | GPU inference host (`colt-gpu-01` @ `10.82.0.3`)       | 🟢 Active |
| **Model Storage**      | 4TB USB NVMe SSD                                              | USB 3.2 Gen2 (10Gbps) external drive                | High-throughput local model cache                      | 🟢 Active |
| **Patch Panel**        | 14-Port Keystone Panel                                        | Cat6 RJ-45 couplers                                 | Patching & service isolation                           | 🟢 Active |
| **Network Switch**     | 1G Managed Switch                                             | 8-port switch (`10.82.0.0/16`, gateway `10.82.0.1`) | Management & data underlay                             | 🟢 Active |
| **Hypervisor Host**    | Minisforum UM760 Slim                                         | AMD Ryzen 5 7640HS, 32GB DDR5, 1TB NVMe, 2.5GbE     | Proxmox VE 9.2 hypervisor (`colt-cp-01` @ `10.82.0.2`) | 🟢 Active |
| **Power Distribution** | PDU Shelf                                                     | Multi-outlet distribution + OEM power supplies      | AC power distribution (120V / 15A circuit)             | 🟢 Active |

---

### Bare-Metal Fleet Hosts

| Hostname          | Role                                                 | IP Address  | Access Method                      |  Status   |
| :---------------- | :--------------------------------------------------- | :---------- | :--------------------------------- | :-------: |
| **`colt-cp-01`**  | Proxmox VE 9.2 Hypervisor (Minisforum MS-01 / UM760) | `10.82.0.2` | OpenSSH CA (`colt-sysadmin-agent`) | 🟢 Active |
| **`colt-gpu-01`** | DGX OS / Inference Node (ASUS Ascent GX10 GB10)      | `10.82.0.3` | OpenSSH CA (`colt-sysadmin-agent`) | 🟢 Active |

---

All virtual infrastructure is provisioned declaratively on `colt-cp-01` via Terraform:

| ID            | Name              | Type           | Allocated Resources          | Network / Endpoint        | Role                                    |   State   |
| :------------ | :---------------- | :------------- | :--------------------------- | :------------------------ | :-------------------------------------- | :-------: |
| **CT 9190**   | `colt-vault`      | Debian 12 LXC  | 1 vCPU, 1GB RAM, 8GB disk    | `https://10.82.0.5:8200`  | HashiCorp Vault 2.1 (mTLS & OpenSSH CA) | 🟢 Active |
| **VM 9110**   | `colt-control-01` | Talos Linux VM | 2 vCPU, 2.5GB RAM, 30GB NVMe | `https://10.82.0.10:6443` | `camp-colt-k8s` Control Plane (v1.36.4) | 🟢 Active |
| **VM 9120**   | `colt-worker-01`  | Talos Linux VM | 4 vCPU, 6GB RAM, 100GB NVMe  | `10.82.0.13`              | Workload execution & Ingress (v1.36.4)  | 🟢 Active |
| **Baremetal** | `colt-gpu-01`     | DGX OS Arm64   | 20 CPU, 128GB Unified, GB10  | `10.82.0.3`               | `camp-colt-k8s` GPU Node (v1.36.4)      | 🟢 Active |

---

## 🔄 Sovereign GitOps Delivery (Flux CD & In-Cluster Gitea)

Cluster workloads, platform controllers, and ingress configurations are continuously reconciled via **Flux CD** pulling directly from the sovereign, in-cluster **Gitea** Git forge:

| Workload / Service  | Type              | Delivery Engine  | Endpoint / Access                  | Role & Storage                                    |   State   |
| :------------------ | :---------------- | :--------------- | :--------------------------------- | :------------------------------------------------ | :-------: |
| **`gitea`**         | K8s Deployment    | GitOps (Flux CD) | `http://10.82.0.13/colt` (`:3000`) | Sovereign Git Forge (20GB NVMe `local-path`)      | 🟢 Active |
| **`flux-system`**   | GitOps Controller | Self-Managed     | In-Cluster (`flux-system`)         | Continuous reconciliation of `clusters/camp-colt` | 🟢 Active |
| **`ingress-nginx`** | K8s DaemonSet     | GitOps (Flux CD) | `10.82.0.13` (Ports 80/443)        | Edge ingress pinned to `talos-64r-bft` worker     | 🟢 Active |

### Key GitOps Elements

- **Forge URL:** `http://10.82.0.13/colt/suitcase-ai.git` (in-cluster: `http://gitea.gitea.svc.cluster.local:3000/colt/suitcase-ai.git`)
- **CLI Management:** `tea` CLI configured with default `colt` profile
- **Source Sync:** `GitRepository/flux-system` polls in-cluster Gitea `main` branch
- **Root Manifests:** [`clusters/camp-colt/`](file:///home/luna-mayor-agent/luna/rigs/suitcase-ai/clusters/camp-colt/) and [`provision/k8s/`](file:///home/luna-mayor-agent/luna/rigs/suitcase-ai/provision/k8s/)

---

## 📐 Architecture & Core Design Decisions

1. **Immutable, API-Driven Cluster (Talos Linux):**
   - Cluster nodes run [Talos Linux](https://www.talos.dev/). There is no SSH daemon, bash shell, or package manager installed inside the virtual machines.
   - All lifecycle management, upgrades, and configuration changes are applied declaratively through `talosctl` and the Terraform Talos provider.
2. **Short-Lived CA Certificates for Host Access:**
   - Instead of distributing permanent SSH keys or root passwords across hosts, host administration uses short-lived OpenSSH certificates signed by HashiCorp Vault (`colt-vault`).
   - Root login over SSH is completely disabled; operations run under a dedicated service identity (`colt-sysadmin-agent`).
3. **Pragmatic Networking:**
   - Operates on an internal `10.82.0.0/16` network (gateway `10.82.0.1`) with DHCP constrained to `10.82.250.x` to prevent address collisions with static infrastructure.
   - Ingress uses `ingress-nginx` configured as a `hostNetwork` DaemonSet on the worker node, avoiding the overhead of external BGP/VIP load balancers on a small cluster.

---

## 🌫️ Fog Legacy Workloads (Co-located)

Personal homelab workloads that ideally belong on separate physical hardware, but are co-located on `colt-cp-01` to make the best use of available physical capacity:

- **Segregated Management:** Allocations are declared in [`provision/fog/`](file:///home/luna-mayor-agent/luna/rigs/suitcase-ai/provision/fog/) for hypervisor tracking, but in-guest OS configurations and application workloads are managed externally.
- **Network Isolation:** All Fog resources run on a dedicated, isolated VLAN (**VLAN 613** on `10.7.82.0/24`) and do not route into the Camp Colt `10.82.0.0/16` fabric.

| VMID        | Guest Name       | Type           | Allocated Resources          | Network                 | Role                         |
| :---------- | :--------------- | :------------- | :--------------------------- | :---------------------- | :--------------------------- |
| **CT 9090** | `vault`          | Debian 12 LXC  | 1 vCPU, 1GB RAM, 16GB disk   | `10.7.82.90` (VLAN 613) | Fog Vault & Root CA          |
| **VM 9010** | `k8s-control-01` | Talos Linux VM | 2 vCPU, 4GB RAM, 40GB disk   | `10.7.82.15` (VLAN 613) | Fog Kubernetes Control Plane |
| **VM 9020** | `k8s-worker-01`  | Talos Linux VM | 6 vCPU, 12GB RAM, 150GB disk | `10.7.82.16` (VLAN 613) | Fog Kubernetes Worker        |

---

## 🚀 Operations Quickstart

### Prerequisites

- Tools: `terraform`, `kubectl`, `talosctl`, `vault` CLI
- Network connectivity to the `10.82.0.0/16` management subnet

### 1. Load Environment

```bash
# Exports Proxmox VE API tokens and local Vault environment
source scripts/load_colt_env.sh
```

### 2. Manage Infrastructure via Terraform

```bash
# Check current planned state
terraform -chdir=provision plan

# Apply infrastructure changes (Hypervisor VMs, Vault LXC, Talos configs)
terraform -chdir=provision apply
```

### 3. Access Kubernetes Cluster

```bash
# Set kubeconfig to Camp Colt cluster
export KUBECONFIG="$(pwd)/colt-kubeconfig"

# Verify cluster status
kubectl get nodes -o wide
kubectl get pods -A
```

### 4. Administer Hypervisors via Ephemeral SSH Certificate

```bash
# Mint a 1-hour signed certificate from Vault
./scripts/sign_agent_cert.sh ~/.ssh/id_ed25519

# SSH to hypervisor using signed certificate
./scripts/ssh_colt_cp.sh
```

---

## 📂 Repository Layout

```text
├── AGENTS.md              # Operational roles, guidelines, and agent instructions
├── README.md              # Project overview, hardware layout, and quickstart
├── agent-keys/            # Public keys, OpenSSH CA certs, and identity records
│   ├── agents/            # Non-Human Identity public keys (colt-sysadmin)
│   └── vault/             # Vault SSH CA public keys
├── docs/                  # Operational runbooks and architecture deep-dives
│   ├── HARDWARE.md        # Physical packaging, CAD models, thermals, and power
│   ├── PROXMOX_OPERATIONS.md
│   └── SECURITY.md        # OpenSSH CA, Non-Human Identity, and trust configuration
├── plans/                 # Architecture implementation and cutover plans
│   └── completed/         # Archival of completed bootstrap runbooks
├── provision/             # Declarative Terraform manifests
│   ├── colt_talos.tf      # Talos Linux Kubernetes cluster definitions
│   ├── colt_vault.tf      # HashiCorp Vault LXC definition
│   ├── colt_vms.tf        # Proxmox QEMU virtual machine resources
│   ├── colt_variables.tf  # Network, VMID, and compute sizing variables
│   ├── ansible/           # Ansible playbooks and inventory
│   └── fog/               # Segregated hypervisor definitions for legacy Fog
└── scripts/               # Host onboarding, CA signing, and environment scripts
    ├── load_colt_env.sh   # Environment loader for Vault and Proxmox API
    ├── sign_agent_cert.sh # Parameterized OpenSSH CA certificate issuance tool
    └── ssh_colt_cp.sh     # Quick SSH jump script to colt-cp-01
```

---

## 📜 License

This project is licensed under the Apache 2.0 License.
