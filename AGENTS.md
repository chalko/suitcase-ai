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
   - **GitOps for Kubernetes:** Always use **Flux** (`flux reconcile kustomization <name> --with-source`)
     for managing Kubernetes workloads and cluster state from `colt/main`.
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

3. **Operational Segregation & Rig Isolation:**

   - Camp Colt operates strictly on the `10.82.0.0/16` appliance network (gateway `10.82.0.1`, Kubernetes control plane `10.82.0.10:6443`).
   - **MANDATORY KUBECONFIG PINNING:** Never run `kubectl` or `flux` without explicitly setting `KUBECONFIG="$REPO_ROOT/colt-kubeconfig"` (or sourcing `scripts/load_colt_env.sh`). All subagents and automated tasks MUST be passed explicit `--kubeconfig` paths or have `KUBECONFIG` pre-set.
   - **ZERO FOREIGN RIG MUTATION:** Never reference, target, or execute mutating commands against external rigs (such as Fog on `10.7.82.0/24` or contexts like `admin@talos-k8s-cluster`). Run `scripts/verify-colt-context.sh` before executing cluster operations to guarantee context safety.
   - Hypervisor allocations for legacy Fog workloads (`provision/fog/`) are strictly segregated at the resource boundary on VLAN 613; in-guest OS configurations are managed externally.

4. **Verification & Live Validation Before Task Completion:**

   - **GitOps Reconciliation & Health Checks:** Always ensure Flux updates are complete
     and pods/jobs are verified healthy and ready before marking tasks complete or closing beads.
   - **Mandatory Inference Prompt Verification:** If a change modifies or affects inference
     workloads, engines, storage tiers, or routing, you MUST dispatch a live sample prompt
     to the inference endpoint (e.g. `/v1/chat/completions`) and verify valid model output
     before declaring the task complete.
   - **Pre-flight Checks:** Always run pre-flight syntax checks, dry-run plans (`terraform plan`,
     `kubectl --dry-run=client`), and network verifications before committing changes.

5. **Release Promotion & Public Egress:**

   - **EXPRESS PERMISSION REQUIRED FOR PUBLIC PROMOTION:** **NEVER** promote to the `public` branch (via `scripts/promote-to-public.sh`, `git push colt public`, or PR) without express, explicit permission from the user in the active conversation. Passing preflight scans (`./scripts/preflight-public-scan.sh`) and build tests is a necessary prerequisite, but autonomous promotion to `public` is strictly forbidden.
