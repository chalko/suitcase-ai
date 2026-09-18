# Ingress-NGINX & Gitea GitOps Safe Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely migrate the cluster's core traffic router (`ingress-nginx`) and GitOps source-of-truth (`gitea` + `act_runner`) from raw static manifests to official Flux `HelmRelease` configurations with zero GitOps disconnection, zero data loss, and uninterrupted cluster connectivity.

**Architecture:**

1. **Ingress-NGINX Migration:** Transition to `ingress-nginx/ingress-nginx` Helm chart in namespace `ingress-nginx`, preserving the static LoadBalancer IP `10.82.50.10` from MetalLB, the default IngressClass `nginx`, and the wildcard TLS secret (`colt-chalko-wildcard-tls`).
2. **Gitea & Runner Migration:** Transition to `gitea/gitea` Helm chart in namespace `gitea`, mounting the existing `gitea-data` (20Gi `local-path` PVC) without re-initialization, injecting HashiCorp Vault secrets (`secret/colt/gitea`, `secret/colt/gitea_runner`), and attaching the existing Docker-in-Docker `act_runner` sub-chart/deployment.

**Tech Stack:** Kubernetes (v1.36.4 on Talos Linux v1.14.0), Flux CD `helm-controller` (v2), HashiCorp Vault (`10.82.0.5:8200`), MetalLB (`colt-ingress-pool`), `ingress-nginx` Helm chart, `gitea` Helm chart.

**Spec:** [docs/PUBLIC_RELEASE_RUNBOOK.md](../PUBLIC_RELEASE_RUNBOOK.md) & [AGENTS.md](../../AGENTS.md)

## Global Constraints

- **GitOps Continuity:** Gitea is the source repository for Flux CD (`https://gitea.colt.chalko.com/colt/suitcase-ai.git`). Under no circumstance may repository data or git access be deleted, wiped, or locked.
- **Master Secret Source:** All Gitea admin tokens, database credentials, and runner registration tokens MUST be read from and managed via HashiCorp Vault (`secret/colt/gitea`, `secret/colt/gitea_runner`).
- **LoadBalancer IP Preservation:** The Ingress controller must retain VIP `10.82.50.10` to avoid breaking DNS wildcard resolution (`*.colt.chalko.com`).
- **Strict Node Pinning:** Both Ingress and Gitea workloads must target the AMD64 worker node `talos-64r-bft` (`kubernetes.io/arch: amd64`).
- **Strictly Pinned Versions:** NEVER use `:latest`. Pin explicit chart and image versions.

---

### Task 1: Safe Ingress-NGINX Migration to HelmRelease

**Files:**

- Create: `provision/k8s/ingress/release.yaml`
- Modify: `provision/k8s/kustomization.yaml` (replace `ingress/ingress-nginx.yaml` with `ingress`)
- Modify: `provision/k8s/ingress/kustomization.yaml`

**Interfaces:**

- Consumes: MetalLB IP pool `colt-ingress-pool`, TLS Secret `colt-chalko-wildcard-tls`
- Produces: `ingress-nginx-controller` Service with external IP `10.82.50.10` and IngressClass `nginx`

- [ ] **Step 1: Author `provision/k8s/ingress/release.yaml`**
      Define `HelmRepository` (`https://kubernetes.github.io/ingress-nginx`) and `HelmRelease` (`chart: ingress-nginx`, version: `4.11.3` / appVersion: `1.11.3`):

  - `controller.nodeSelector: { kubernetes.io/arch: amd64 }`
  - `controller.service.annotations: { metallb.universe.tf/address-pool: colt-ingress-pool }`
  - `controller.service.loadBalancerIP: 10.82.50.10`
  - `controller.ingressClassResource.name: nginx`
  - `controller.ingressClassResource.default: true`
  - `controller.extraArgs.default-ssl-certificate: "gitea/colt-chalko-wildcard-tls"`
  - `controller.config.proxy-body-size: "0"`

- [ ] **Step 2: Dry-run validate kustomize build**
      Run: `kubectl kustomize provision/k8s/ingress | kubectl apply --dry-run=client -f -`
      Expected: Clean validation.

- [ ] **Step 3: Perform smooth cutover**
      Apply `release.yaml` via Flux CD. Verify the new controller adopts the service and VIP `10.82.50.10` without dropping active HTTP routes.

- [ ] **Step 4: Verify all ingress endpoints**
      Verify HTTP 200 responses for:
  - `https://gitea.colt.chalko.com`
  - `https://harbor.colt.chalko.com`
  - `https://olah.colt.chalko.com`
  - `https://litellm.colt.chalko.com`

---

### Task 2: Pre-Flight Gitea Data Snapshot & Vault Secret Validation

**Files:**

- Create: `scripts/backup-gitea-pre-migration.sh`
- Target: Vault path `secret/colt/gitea`, `secret/colt/gitea_runner`

**Interfaces:**

- Consumes: PVC `gitea-data` in namespace `gitea`
- Produces: Verified SQLite DB backup and repository tarball in `/tmp/gitea-backup/`

- [ ] **Step 1: Execute read-only data snapshot**
      Execute `scripts/backup-gitea-pre-migration.sh` to dump Gitea's SQLite database (`gitea.db`) and verify that Vault contains the matching admin token and runner token.

- [ ] **Step 2: Confirm backup integrity**
      Verify backup archive size > 0 and checksum valid before proceeding.

---

### Task 3: Author Gitea & Act Runner HelmRelease

**Files:**

- Create: `provision/k8s/gitea/release.yaml`
- Modify: `provision/k8s/gitea/kustomization.yaml`
- Preserve: `provision/k8s/gitea/runner.yaml` & `provision/k8s/gitea/runner-configmap.yaml`

**Interfaces:**

- Consumes: Existing PVC `gitea-data` (20Gi `local-path`), Secret `gitea-admin-secret`
- Produces: Official `gitea` HelmRelease and associated service/ingress

- [ ] **Step 1: Author `provision/k8s/gitea/release.yaml`**
      Configure official chart `https://dl.gitea.com/charts/` (`gitea/gitea`, version: `10.6.0`):

  - `gitea.admin.existingSecret: gitea-admin-secret`
  - `gitea.config.database.DB_TYPE: sqlite3`
  - `gitea.config.database.PATH: /data/gitea/gitea.db`
  - `persistence.existingClaim: gitea-data`
  - `persistence.mountPath: /data`
  - `nodeSelector: { kubernetes.io/arch: amd64 }`
  - `ingress.enabled: true` with host `gitea.colt.chalko.com` and secret `colt-chalko-wildcard-tls`.

- [ ] **Step 2: Validate Kustomize aggregation**
      Run: `kubectl kustomize provision/k8s/gitea`
      Expected: Gitea server HelmRelease and Act Runner manifests properly rendered.

---

### Task 4: Execute Safe Gitea Cutover & Verification

- [ ] **Step 1: Commit and reconcile Flux CD**
      Push manifests to `colt/main` and trigger `flux reconcile kustomization camp-colt-infra --with-source`.

- [ ] **Step 2: Verify Gitea Pod health and data persistence**
      Verify `gitea-0` is **1/1 Running**, SQLite DB connects seamlessly, and all repositories (`colt/suitcase-ai`) exist with full commit history.

- [ ] **Step 3: Verify Act Runner connection**
      Verify `gitea-runner` pod is **2/2 Running** and connected to the migrated Gitea instance via Vault registration token.

- [ ] **Step 4: Verify Git push/pull and live inference prompt**
      Test `git fetch colt` and dispatch live sample prompt to inference engine.
