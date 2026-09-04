resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type        = "iso"
  datastore_id        = "local"
  node_name           = var.proxmox_node
  url                 = "https://github.com/siderolabs/talos/releases/download/v1.9.1/metal-amd64.iso"
  file_name           = "talos-v1.9.1-metal-amd64.iso"
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "k8s_nodes" {
  for_each    = var.k8s_nodes
  name        = each.key
  description = "Talos Kubernetes Node - Managed by Terraform/OpenTofu"
  tags        = ["terraform", "k8s", "talos"]
  node_name   = var.proxmox_node
  vm_id       = each.value.vmid
  bios        = "ovmf"

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = false
  }

  network_device {
    bridge      = var.vm_bridge
    mac_address = each.value.mac
  }

  disk {
    datastore_id = "local-fast-zfs"
    interface    = "scsi0"
    size         = each.value.disk
    file_format  = "raw"
  }

  efi_disk {
    datastore_id = "local-fast-zfs"
    file_format  = "raw"
    type         = "4m"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["ide2", "scsi0"]
}
