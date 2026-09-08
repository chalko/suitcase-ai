terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.3.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7.0"
    }
  }
}

provider "proxmox" {
  # Automatically reads PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN
  insecure = true

  ssh {
    agent    = false
    username = "colt-sysadmin-agent"
  }
}

provider "vault" {
  address          = "https://10.82.0.5:8200"
  skip_tls_verify  = true
  skip_child_token = true
}

