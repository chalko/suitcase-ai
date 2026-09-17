# ==============================================================================
# Camp Colt Sovereign Vault Policies & Kubernetes Auth Roles
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Colt Sysadmin / Owner Policy
# ------------------------------------------------------------------------------
resource "vault_policy" "colt_owner" {
  name = "colt-owner"

  policy = <<EOT
# Key-Value Secrets Engine
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Authentication Backends
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# ACL Policy Management
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Raft Integrated Storage Management & Snapshots
path "sys/storage/raft/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# OpenSSH Certificate Authority
path "ssh/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOT
}

# ------------------------------------------------------------------------------
# 2. General Workload Policy (K8s Pods / Apps)
# ------------------------------------------------------------------------------
resource "vault_policy" "colt_workload" {
  name = "colt-workload"

  policy = <<EOT
path "secret/data/colt/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/colt/*" {
  capabilities = ["read", "list"]
}
EOT
}

# ------------------------------------------------------------------------------
# 3. Dedicated Vault Backup Policy (Least-Privilege for Raft Snapshots)
# ------------------------------------------------------------------------------
resource "vault_policy" "vault_backup" {
  name = "vault-backup"

  policy = <<EOT
# Raft Snapshot Read Capability
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

# Google Drive Service Account and Target Folder Metadata
path "secret/data/colt/backup/*" {
  capabilities = ["read"]
}
path "secret/metadata/colt/backup/*" {
  capabilities = ["read"]
}
EOT
}

# ------------------------------------------------------------------------------
# 4. Kubernetes Auth Backend Role for Vault Backup CronJob
# ------------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "vault_backup" {
  backend                          = "kubernetes"
  role_name                        = "vault-backup"
  bound_service_account_names      = ["vault-backup-sa", "colt-backup-sa"]
  bound_service_account_namespaces = ["vault-backup", "backup-system"]
  token_policies                   = ["vault-backup"]
  token_ttl                        = 3600
}

# ------------------------------------------------------------------------------
# 5. Kubernetes Auth Backend Role for External Secrets Operator (ESO)
# ------------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = "kubernetes"
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = ["colt-workload"]
  token_ttl                        = 3600
}

