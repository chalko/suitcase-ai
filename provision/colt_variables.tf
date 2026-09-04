variable "colt_vault_config" {
  type = object({
    vmid     = number
    hostname = string
    ip       = string
    gateway  = string
    dns      = list(string)
    domain   = string
    cores    = number
    memory   = number
    swap     = number
    disk     = number
  })
  default = {
    vmid     = 9190
    hostname = "colt-vault"
    ip       = "10.82.0.5/24"
    gateway  = "10.82.0.1"
    dns      = ["10.5.110.3", "10.82.0.1"]
    domain   = "colt.internal"
    cores    = 1
    memory   = 1024
    swap     = 512
    disk     = 8
  }
  description = "Configuration parameters for the Camp Colt Vault LXC container"
}

variable "colt_k8s_nodes" {
  type = map(object({
    vmid      = number
    node_type = string
    cores     = number
    memory    = number
    disk      = number
    ip        = string
    gateway   = string
    dns       = list(string)
    mac       = string
  }))
  default = {
    "colt-control-01" = {
      vmid      = 9110
      node_type = "controlplane"
      cores     = 2
      memory    = 2560
      disk      = 30
      ip        = "10.82.20.2/24"
      gateway   = "10.82.20.1"
      dns       = ["10.5.110.3", "10.82.20.1"]
      mac       = "BC:24:11:82:20:02"
    }
    "colt-worker-01" = {
      vmid      = 9120
      node_type = "worker"
      cores     = 4
      memory    = 6144
      disk      = 100
      ip        = "10.82.20.13/24"
      gateway   = "10.82.20.1"
      dns       = ["10.5.110.3", "10.82.20.1"]
      mac       = "BC:24:11:82:20:13"
    }
  }
  description = "Map of Camp Colt Kubernetes nodes to deploy on Proxmox"
}

variable "proxmox_node" {
  type        = string
  default     = "colt-cp-01"
  description = "Target Proxmox node name"
}

variable "vm_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Network bridge for VMs and LXCs"
}
