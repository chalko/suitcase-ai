# Harbor Registry & Pull-Through Proxy Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Harbor as a sovereign in-cluster OCI container registry and pull-through proxy cache for Docker Hub (`docker.io`), NVIDIA NGC (`nvcr.io`), and GitHub Container Registry (`ghcr.io`) on the AMD64 worker node (`talos-64r-bft`), preventing WAN saturation, eliminating upstream rate limits, and enforcing strict disk quotas and automated garbage collection.

**Architecture:** A declarative Kubernetes deployment in namespace `harbor` exposed via Ingress at `harbor.colt.chalko.com`. Configured with pull-through proxy cache projects (`docker-proxy`, `nvcr-proxy`, `ghcr-proxy`) backed by persistent storage with storage limits, automated tag retention rules, and weekly garbage collection. Talos Linux nodes are configured with `containerd` registry mirrors to route pulls through Harbor transparently.

**Tech Stack:** Harbor v2.11.x (or pinned lightweight distribution), Kubernetes (Talos Linux 1.14 / K8s 1.36.4), HashiCorp Vault (`10.82.0.5:8200`), Traefik/Ingress-Nginx, Flux CD GitOps.

**Spec:** [docs/storage_tiering_model_depot_ready_locker.md](../storage_tiering_model_depot_ready_locker.md)

## Global Constraints

- **Master Secret Source:** All administrative credentials and upstream registry pull secrets MUST be stored in HashiCorp Vault (`secret/colt/harbor`, `secret/colt/ngc`, `secret/colt/dockerhub`).
- **Strictly Pinned Image Tags:** NEVER use `:latest`. All Harbor components and sidecars must pin explicit versions (e.g. `goharbor/harbor-core:v2.11.0`, `goharbor/harbor-registryctl:v2.11.0`, `goharbor/registry-photon:v2.11.0`).
- **Node Pinning:** General infrastructure services MUST target AMD64 worker node `talos-64r-bft` (`kubernetes.io/arch: amd64`), keeping the Grace Blackwell GB10 GPU node (`colt-gpu-01`) dedicated to inference workloads.
- **Strict Storage Quota:** Proxy cache storage volume must be capped with explicit size constraints (max 120GB) and scheduled garbage collection.
- **GitOps Declarative Deployment:** All manifests must reside in `provision/k8s/harbor/` and reconcile via Flux CD.

---

### Task 1: Vault Secret Setup & Admin Credential Management

**Files:**

- Create: `scripts/sync-harbor-vault.sh`
- Target: Vault path `secret/colt/harbor`
- Target: K8s Secret `harbor-admin-secret` and `harbor-upstream-tokens` in namespace `harbor`

**Interfaces:**

- Consumes: HashiCorp Vault (`secret/colt/harbor`, `secret/colt/ngc`, `secret/colt/dockerhub`)
- Produces: Kubernetes Secrets in namespace `harbor`

- [ ] **Step 1: Create secret generation and sync script**
      Author `scripts/sync-harbor-vault.sh` to generate cryptographically random database, secret key, and admin passwords, store them in Vault `secret/colt/harbor`, and apply Kubernetes Secret without exposing plaintexts in stdout.

- [ ] **Step 2: Run script and verify secrets in Vault & K8s**
      Run: `bash scripts/sync-harbor-vault.sh`
      Expected: Secret `harbor-admin-secret` applied in namespace `harbor`.

---

### Task 2: Create Declarative Harbor GitOps Manifests

**Files:**

- Create: `provision/k8s/harbor/namespace.yaml`
- Create: `provision/k8s/harbor/harbor-configmap.yaml`
- Create: `provision/k8s/harbor/harbor-pvc.yaml`
- Create: `provision/k8s/harbor/harbor-deployment.yaml`
- Create: `provision/k8s/harbor/harbor-ingress.yaml`
- Create: `provision/k8s/harbor/kustomization.yaml`
- Modify: `provision/k8s/kustomization.yaml`

**Interfaces:**

- Consumes: `harbor-admin-secret`, `harbor-upstream-tokens`
- Produces: Harbor core, registry, registryctl, redis, portal, and ingress at `harbor.colt.chalko.com`

- [ ] **Step 1: Author storage and configuration manifests**
      Define PVC with explicit 120GB quota on storage pool and ConfigMaps specifying pull-through proxy caching behavior and token auth.

- [ ] **Step 2: Author Harbor Deployment and Service manifests**
      Pin all Harbor images to exact tags, inject `kubernetes.io/arch: amd64` nodeSelector, and configure Ingress for `https://harbor.colt.chalko.com`.

- [ ] **Step 3: Validate kustomize build and dry-run apply**
      Run: `kubectl kustomize provision/k8s/harbor | kubectl apply --dry-run=client -f -`
      Expected: All resources validate cleanly.

---

### Task 3: Configure Proxy-Cache Projects & Storage Retention Policies

**Files:**

- Create: `provision/k8s/harbor/retention-cronjob.yaml`
- Create: `scripts/configure-harbor-proxy-projects.sh`

**Interfaces:**

- Consumes: Harbor REST API at `https://harbor.colt.chalko.com/api/v2.0`
- Produces: Proxy cache projects (`docker-proxy`, `nvcr-proxy`, `ghcr-proxy`), tag retention rules, scheduled GC cron

- [ ] **Step 1: Author proxy-cache project provisioning script**
      Create endpoint registries for `https://registry-1.docker.io`, `https://nvcr.io`, and `https://ghcr.io` with pull-through caching enabled.
      Configure tag retention policies:

  - Keep last 2 tags for floating images.
  - Automatically prune unreferenced / untagged blobs after 7 days.

- [ ] **Step 2: Author scheduled Harbor Garbage Collection CronJob**
      Author a declarative CronJob in `provision/k8s/harbor/retention-cronjob.yaml` running weekly (`0 3 * * 0`) that triggers registry GC with `delete_untagged: true`.

---

### Task 4: Configure Talos Linux containerd Registry Mirrors

**Files:**

- Create: `provision/talos/patches/registry-mirrors.yaml`
- Modify: `provision/talos/worker.yaml` / `provision/talos/controlplane.yaml`

**Interfaces:**

- Consumes: Harbor endpoint `harbor.colt.chalko.com`
- Produces: Talos machine config `.machine.registries.mirrors` for `docker.io`, `nvcr.io`, `ghcr.io`

- [ ] **Step 1: Author Talos registry mirror configuration patch**
      Define mirror endpoints:

  ```yaml
  machine:
    registries:
      mirrors:
        "docker.io":
          endpoints:
            - "https://harbor.colt.chalko.com/v2/docker-proxy"
        "nvcr.io":
          endpoints:
            - "https://harbor.colt.chalko.com/v2/nvcr-proxy"
        "ghcr.io":
          endpoints:
            - "https://harbor.colt.chalko.com/v2/ghcr-proxy"
  ```

- [ ] **Step 2: Test patch syntax against Talos machine config**
      Validate patch against Talos machine specs using `talosctl validate`.

---

### Task 5: Verification & End-to-End Image Pull Test

- [ ] **Step 1: Commit and reconcile Flux CD**
      Commit all manifests to `colt/main` and run `flux reconcile kustomization camp-colt-infra --with-source`.

- [ ] **Step 2: Verify Harbor Health and Pods**
      Run: `kubectl get pods -n harbor`
      Expected: All Harbor components 1/1 Running.

- [ ] **Step 3: Test proxy cache pull**
      Dispatch test pod pulling `docker.io/library/alpine:3.20.2` via mirror and verify layer cache hit in Harbor dashboard and logs.
