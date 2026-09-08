# Create dedicated cluster secrets for Camp Colt
resource "talos_machine_secrets" "colt" {
  talos_version = "v1.13.10"
}

# Generate machine configuration for colt-control-01
data "talos_machine_configuration" "colt_controlplane" {
  cluster_name       = "camp-colt-k8s"
  cluster_endpoint   = "https://10.82.0.10:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.colt.machine_secrets
  talos_version      = "v1.13.10"
  kubernetes_version = "v1.35.8"

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        network = {
          interfaces = [
            {
              interface = "ens18"
              addresses = ["10.82.0.10/24"]
              routes    = [{ network = "0.0.0.0/0", gateway = "10.82.0.1" }]
            }
          ]
          nameservers = ["10.5.110.3", "10.82.0.1"]
        }
        time = {
          servers = ["10.5.110.3", "10.5.110.1"]
        }
      }
    })
  ]
}

# Generate machine configuration for colt-worker-01
data "talos_machine_configuration" "colt_worker" {
  cluster_name       = "camp-colt-k8s"
  cluster_endpoint   = "https://10.82.0.10:6443"
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.colt.machine_secrets
  talos_version      = "v1.13.10"
  kubernetes_version = "v1.35.8"

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        network = {
          interfaces = [
            {
              interface = "ens18"
              addresses = ["10.82.0.13/24"]
              routes    = [{ network = "0.0.0.0/0", gateway = "10.82.0.1" }]
            }
          ]
          nameservers = ["10.5.110.3", "10.82.0.1"]
        }
        time = {
          servers = ["10.5.110.3", "10.5.110.1"]
        }
      }
    })
  ]
}

# Apply configurations to colt nodes
resource "talos_machine_configuration_apply" "colt_controlplane" {
  client_configuration        = talos_machine_secrets.colt.client_configuration
  machine_configuration_input = data.talos_machine_configuration.colt_controlplane.machine_configuration
  node                        = "10.82.0.10"
  endpoint                    = "10.82.0.254"
  depends_on                  = [proxmox_virtual_environment_vm.colt_k8s_nodes]
}

resource "talos_machine_configuration_apply" "colt_worker" {
  client_configuration        = talos_machine_secrets.colt.client_configuration
  machine_configuration_input = data.talos_machine_configuration.colt_worker.machine_configuration
  node                        = "10.82.0.13"
  endpoint                    = "10.82.0.253"
  depends_on                  = [proxmox_virtual_environment_vm.colt_k8s_nodes]
}

# Bootstrap Camp Colt cluster on colt-control-01
resource "talos_machine_bootstrap" "colt" {
  client_configuration = talos_machine_secrets.colt.client_configuration
  node                 = "10.82.0.10"
  endpoint             = "10.82.0.10"
  depends_on           = [talos_machine_configuration_apply.colt_controlplane]
}

# Retrieve Camp Colt kubeconfig
data "talos_cluster_kubeconfig" "colt" {
  client_configuration = talos_machine_secrets.colt.client_configuration
  node                 = "10.82.0.10"
  endpoint             = "10.82.0.10"
  depends_on           = [talos_machine_bootstrap.colt]
}

resource "local_file" "colt_kubeconfig" {
  content  = data.talos_cluster_kubeconfig.colt.kubeconfig_raw
  filename = "${path.module}/../colt-kubeconfig"
}

data "talos_client_configuration" "colt" {
  cluster_name         = "camp-colt-k8s"
  client_configuration = talos_machine_secrets.colt.client_configuration
  nodes                = ["10.82.0.10"]
  endpoints            = ["10.82.0.10"]
}

resource "local_file" "colt_talosconfig" {
  content  = data.talos_client_configuration.colt.talos_config
  filename = "${path.module}/../colt-talosconfig"
}
