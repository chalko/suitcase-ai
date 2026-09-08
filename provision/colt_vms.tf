resource "proxmox_virtual_environment_vm" "colt_k8s_nodes" {
  for_each    = var.colt_k8s_nodes
  name        = each.key
  description = "Camp Colt Talos Kubernetes Node (${each.value.node_type}) - Managed by Terraform"
  tags        = ["colt", "k8s", "talos", "terraform"]
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
    model       = "virtio"
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

  boot_order = ["scsi0"]
}
