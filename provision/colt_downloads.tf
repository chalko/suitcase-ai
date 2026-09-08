resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  content_type        = "vztmpl"
  datastore_id        = "local"
  node_name           = var.proxmox_node
  url                 = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
  file_name           = "debian-12-standard_12.12-1_amd64.tar.zst"
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type        = "iso"
  datastore_id        = "local"
  node_name           = var.proxmox_node
  url                 = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.14.0/metal-amd64.iso"
  file_name           = "talos-v1.14.0-qemu-metal-amd64.iso"
  overwrite_unmanaged = true
}
