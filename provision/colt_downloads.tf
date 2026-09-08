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
  url                 = "https://github.com/siderolabs/talos/releases/download/v1.13.10/metal-amd64.iso"
  file_name           = "talos-v1.13.10-metal-amd64.iso"
  overwrite_unmanaged = true
}
