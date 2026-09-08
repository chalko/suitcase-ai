# Camp Colt Network IP Allocation Plan

This document formalizes the declarative IPv4 subnet tiering and VIP assignments for **Camp Colt**, the sovereign AI appliance operating under the `10.82.0.0/16` appliance network supernet (gateway `10.82.0.1`).

---

## 🌐 Master Subnet Architecture (`10.82.0.0/16`)

The Camp Colt appliance network is structured into functional `/24` tiers within the `10.82.0.0/16` boundary:

| Subnet Tier     | Purpose                 | Description                                                                                       |
| :-------------- | :---------------------- | :------------------------------------------------------------------------------------------------ |
| `10.82.0.0/24`  | **Physical Management** | Bare-metal hypervisors, bare-metal GPU accelerators, physical switches, out-of-band management    |
| `10.82.10.0/24` | **Platform & Vault**    | Core sovereign platform services, HashiCorp Vault, identity services                              |
| `10.82.20.0/24` | **K8s Node VMs**        | Talos Linux Kubernetes control plane and worker VMs                                               |
| `10.82.50.0/24` | **Ingress & VIP Tier**  | Highly-available virtual IPs (VIPs) for cluster Ingress, internal DNS, and load-balanced services |

---

## 📍 Detailed IP Allocations

### 1. Physical Management Tier (`10.82.0.0/24`)

| IP Address  | Hostname / Identifier  | Role / Description                                                   |
| :---------- | :--------------------- | :------------------------------------------------------------------- |
| `10.82.0.1` | `colt-gw`              | Gateway / Appliance Router                                           |
| `10.82.0.2` | `colt-cp-01` / `pve`   | Proxmox VE 8 Hypervisor (`vmbr0`)                                    |
| `10.82.0.3` | `colt-gpu-01` / `haze` | ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10, 128GB unified memory) |
| `10.82.0.4` | `colt-sw-01`           | Management Network Switch                                            |

---

### 2. Platform & Vault Tier (`10.82.10.0/24`)

| IP Address    | Hostname / Identifier | Role / Description                                                           |
| :------------ | :-------------------- | :--------------------------------------------------------------------------- |
| `10.82.0.5`\* | `colt-vault`          | Sovereign HashiCorp Vault (LXC 9190 on PVE, managed via mTLS & raft storage) |

_\*Note: `colt-vault` currently resides at `10.82.0.5` for historical bootstrap compatibility, mapped logically within the platform tier._

---

### 3. Kubernetes Node Tier (`10.82.20.0/24`)

| IP Address     | Hostname / Identifier               | Role / Description                               |
| :------------- | :---------------------------------- | :----------------------------------------------- |
| `10.82.0.10`\* | `talos-244-kbx` (`colt-control-01`) | Talos Linux Kubernetes Control Plane VM          |
| `10.82.0.13`\* | `talos-64r-bft` (`colt-worker-01`)  | Talos Linux Kubernetes General-Purpose Worker VM |

_\*Note: Initial bootstrap VMs reside in `10.82.0.10-10.82.0.20` range; future node expansions will map into `10.82.20.0/24`._

---

### 4. Ingress & VIP Tier (`10.82.50.0/24`)

Managed dynamically via Kubernetes L2 LoadBalancer (MetalLB / ARP advertisement):

| IP Address                  | DNS Name                  | Service            | Status     | Description                                                                                                                                                  |
| :-------------------------- | :------------------------ | :----------------- | :--------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `10.82.50.2`                | `dns01.colt.chalko.com`   | `coredns-colt`     | **Active** | Primary Local DNS Server (TCP/UDP port 53). Resolves all `*.colt.chalko.com` to Ingress VIP and forwards external queries to upstream gateway (`10.82.0.1`). |
| `10.82.50.3`                | `dns02.colt.chalko.com`   | `coredns-colt-ha1` | _Reserved_ | Secondary DNS VIP reserved for HA cross-node replica.                                                                                                        |
| `10.82.50.4`                | `dns03.colt.chalko.com`   | `coredns-colt-ha2` | _Reserved_ | Tertiary DNS VIP reserved for HA cross-node replica.                                                                                                         |
| `10.82.50.10`               | `ingress.colt.chalko.com` | `ingress-nginx`    | **Active** | Primary Ingress VIP (HTTP:80, HTTPS:443). Wildcard router for all `*.colt.chalko.com` hostnames (e.g. `litellm.colt.chalko.com`, `gitea.colt.chalko.com`).   |
| `10.82.50.11 - 10.82.50.50` | —                         | LoadBalancer Pool  | _Reserved_ | Dynamic IP pool for future platform LoadBalancer services.                                                                                                   |

---

## 🔒 DNS Resolution Conventions

All local workloads and clients configured with DNS `10.82.50.2` resolve:

- `*.colt.chalko.com` -> `10.82.50.10` (Ingress NGINX)
- `pve.colt.chalko.com` -> `10.82.0.2`
- `colt-gpu-01.colt.chalko.com` / `haze.colt.chalko.com` -> `10.82.0.3`
- `vault.colt.chalko.com` -> `10.82.0.5`
- `k8s.colt.chalko.com` -> `10.82.0.10`
- External queries -> Forwarded to upstream `10.82.0.1`.
