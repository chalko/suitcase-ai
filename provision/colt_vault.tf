resource "random_password" "colt_vault_root_password" {
  length  = 24
  special = true
}

resource "proxmox_virtual_environment_container" "colt_vault" {
  node_name    = var.proxmox_node
  vm_id        = var.colt_vault_config.vmid
  unprivileged = true
  description  = "Camp Colt Sovereign Vault & OpenSSH CA - Managed by Terraform"
  tags         = ["colt", "vault", "security", "terraform"]

  initialization {
    hostname = var.colt_vault_config.hostname

    ip_config {
      ipv4 {
        address = var.colt_vault_config.ip
        gateway = var.colt_vault_config.gateway
      }
    }

    dns {
      domain  = var.colt_vault_config.domain
      servers = var.colt_vault_config.dns
    }

    user_account {
      password = random_password.colt_vault_root_password.result
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.vm_bridge
  }

  memory {
    dedicated = var.colt_vault_config.memory
    swap      = var.colt_vault_config.swap
  }

  cpu {
    cores = var.colt_vault_config.cores
  }

  disk {
    datastore_id = "local-fast-zfs"
    size         = var.colt_vault_config.disk
  }

  features {
    nesting = true
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template.id
    type             = "debian"
  }

  start_on_boot = true
}

output "colt_vault_ip" {
  value       = var.colt_vault_config.ip
  description = "Static IP address for colt-vault LXC"
}
