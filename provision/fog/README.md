# Fog Hypervisor VM & LXC Definitions

This directory contains OpenTofu / Terraform manifests managing the **hypervisor-level** resource allocation (CPU cores, RAM limits, disk volumes, power states, network bridge attachment) for Fog guest workloads running on `colt-cp-01` (formerly `misty`):

- **VMID 9010**: `k8s-control-01` (Talos K8s Control Plane)
- **VMID 9020**: `k8s-worker-01` (Talos K8s Worker)
- **VMID 9090**: `vault` (Fog HashiCorp Vault & CA LXC)

### Operational Scope Boundary:
`colt-sysadmin` is responsible for hypervisor uptime, host networking, and container/VM allocations here. In-guest OS configurations, Kubernetes workloads, and service deployments within these VMs are managed by `fog/kaylee`.
