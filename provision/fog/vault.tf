resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
  file_name    = "debian-12-standard_12.12-1_amd64.tar.zst"
}

resource "random_password" "vault_root_password" {
  length  = 20
  special = true
}

resource "proxmox_virtual_environment_container" "vault" {
  node_name    = var.proxmox_node
  vm_id        = 9090
  unprivileged = true

  initialization {
    hostname = "vault"

    ip_config {
      ipv4 {
        address = "10.7.82.90/24"
        gateway = "10.7.82.1"
      }
    }

    dns {
      server = "10.5.110.3"
    }

    user_account {
      keys     = length(var.ssh_public_keys) > 0 ? var.ssh_public_keys : (fileexists("/home/nick/id_rsa_yubikey.pub") ? [trimspace(file("/home/nick/id_rsa_yubikey.pub"))] : [])
      password = random_password.vault_root_password.result
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.vm_bridge
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-fast-zfs"
    size         = 16
  }

  features {
    nesting = true
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template.id
    type             = "debian"
  }

  # Ensure the container starts automatically on boot
  start_on_boot = true
}

output "vault_container_ip" {
  value       = "10.7.82.90"
  description = "The static IP address of the Vault LXC container"
}
