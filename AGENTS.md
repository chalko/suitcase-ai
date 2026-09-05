# Agent Guidelines for Suitcase AI (`suitcase-ai`)

This repository contains the declarative infrastructure-as-code, automation
playbooks, and operational tooling for **Camp Colt**—the sovereign AI appliance
within the Suitcase AI initiative.

---

## 🎖️ Operational Roles & Responsibilities

- **Camp Colt Sysadmin (`colt-sysadmin`)**: Primary infrastructure administrator
  responsible for bare-metal hypervisors, GPU nodes, Talos Linux Kubernetes
  clusters, and sovereign secrets management.
- **Platform & Workload Operator**: Responsible for staging platform services
  (Ingress, LiteLLM gateway, Dolt database, and monitoring).

---

## 📜 Core Infrastructure & Coding Guidelines

1. **Tooling Standards:**

   - **Infrastructure as Code (IaC):** Use **Terraform** (`terraform plan`,
     `terraform apply`) for managing Proxmox VE hypervisors and Talos Linux
     nodes.
   - **Configuration Management:** Use **Ansible**
     (`provision/ansible/inventory/hosts.yaml`) with OpenSSH CA certificate
     authentication.
   - **Secret Management:** Use **HashiCorp Vault** (`colt-vault` @
     `10.82.0.5:8200`). Never hardcode or print raw credentials.

2. **Zero-Secret / Least Privilege:**

   - All host and hypervisor administrative access requires OpenSSH CA signed
     client certificates (`id_ed25519_colt_sysadmin_agent-cert.pub`).
   - Master unseal keys and sensitive tokens must be managed through `pass` or
     volatile memory.
   - Never commit private keys, tokens, or credential JSON files to git.
     Maintain strict `.gitignore` rules.

3. **Operational Segregation:**

   - Camp Colt operates on the `10.82.0.0/16` appliance network (gateway `10.82.0.1`).
   - Hypervisor allocations for legacy Fog workloads (`provision/fog/`) are
     strictly segregated at the resource boundary on VLAN 613; in-guest OS configurations
     are managed externally.

4. **Verification Before Assertion:**
   - Always run pre-flight syntax checks, dry-run plans (`terraform plan`), and
     network verifications before committing changes or declaring milestones
     complete.
