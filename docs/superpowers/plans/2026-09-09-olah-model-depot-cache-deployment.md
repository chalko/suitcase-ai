# Olah Model Hub Proxy & ModelDepot Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Olah (or high-throughput local HuggingFace/NGC Model Cache Proxy) integrated directly with Camp Colt's ModelDepot (`/mnt/model-depot`) capacity tier to provide line-rate, deduplicated model caching, eliminate redundant multi-gigabyte WAN downloads, and enforce strict disk space quotas and UMA memory hygiene.

**Architecture:** A lightweight caching reverse proxy deployed on the AMD64 worker node (`talos-64r-bft`) and exposed at `https://olah.colt.chalko.com`. Configured to proxy and cache HuggingFace Hub API requests and LFS tensor chunks (`.safetensors`, `.gguf`, `.bin`) into the persistent ModelDepot backing store (`/mnt/model-depot/cache/`). The system exposes standardized endpoints compatible with `HF_ENDPOINT` and `sparkrun`, backed by automated LRU retention policies and Phase 1C page cache flushes (`drop_caches`).

**Tech Stack:** Olah / Python caching proxy, ModelDepot storage tier (`/mnt/model-depot`), ReadyLocker fast tier (`/workspace/models/fast-cache`), HashiCorp Vault (`secret/colt/huggingface`, `secret/colt/ngc`), Traefik Ingress, Flux CD GitOps.

**Spec:** [docs/storage_tiering_model_depot_ready_locker.md](file:///home/luna-mayor-agent/luna/rigs/suitcase-ai/docs/storage_tiering_model_depot_ready_locker.md)

## Global Constraints

- **Master Secret Source:** Upstream HuggingFace user access tokens (`HF_TOKEN`) and NGC API keys MUST be retrieved from HashiCorp Vault (`secret/colt/huggingface`, `secret/colt/ngc`).
- **Strictly Pinned Image Tags:** NEVER use `:latest`. Use pinned container image tags for Olah and auxiliary cron runners.
- **Node Pinning:** Olah proxy runtime runs on worker node `talos-64r-bft` (`kubernetes.io/arch: amd64`), while ModelDepot mount points interface via high-speed cluster storage.
- **Strict ModelDepot Storage Quota:** Enforce strict disk boundaries (e.g. 500GB capacity threshold on depot tier) with an automated LRU eviction daemon for ephemeral recipe downloads.
- **UMA Memory Isolation:** Ensure hydration scripts always drop page caches (`echo 3 > /proc/sys/vm/drop_caches`) to prevent model loading I/O from thrashing Grace Blackwell GB10 unified memory.

---

### Task 1: Vault Secret Provisioning for Model Hub Upstreams

**Files:**

- Create: `scripts/sync-olah-vault.sh`
- Target: Vault path `secret/colt/huggingface`
- Target: K8s Secret `olah-upstream-secrets` in namespace `model-cache`

**Interfaces:**

- Consumes: HashiCorp Vault (`secret/colt/huggingface`, `secret/colt/ngc`)
- Produces: Kubernetes Secret `olah-upstream-secrets` in namespace `model-cache`

- [ ] **Step 1: Author secret synchronization script**
      Create `scripts/sync-olah-vault.sh` to extract HF_TOKEN and NGC_API_KEY from Vault and create Kubernetes Secret `olah-upstream-secrets` with 0600 permissions.

- [ ] **Step 2: Verify secret creation**
      Run: `bash scripts/sync-olah-vault.sh`
      Expected: Secret `olah-upstream-secrets` created in namespace `model-cache`.

---

### Task 2: Declarative Olah GitOps Deployment Manifests

**Files:**

- Create: `provision/k8s/apps/olah/namespace.yaml`
- Create: `provision/k8s/apps/olah/olah-configmap.yaml`
- Create: `provision/k8s/apps/olah/olah-pvc.yaml`
- Create: `provision/k8s/apps/olah/olah-deployment.yaml`
- Create: `provision/k8s/apps/olah/olah-ingress.yaml`
- Create: `provision/k8s/apps/olah/kustomization.yaml`
- Modify: `provision/k8s/kustomization.yaml`

**Interfaces:**

- Consumes: `olah-upstream-secrets`, ModelDepot persistent storage volume
- Produces: Olah proxy service and Ingress at `https://olah.colt.chalko.com`

- [ ] **Step 1: Define Olah storage & configuration**
      Configure persistent volume pointing to ModelDepot capacity storage (`/mnt/model-depot/cache`), with upstream mirror configuration for `https://huggingface.co`.

- [ ] **Step 2: Define Olah Deployment and Service**
      Pin container image, configure readiness/liveness health probes on `/healthz`, and set resource limits.

- [ ] **Step 3: Validate kustomize build and dry-run apply**
      Run: `kubectl kustomize provision/k8s/apps/olah | kubectl apply --dry-run=client -f -`
      Expected: Manifests validate cleanly.

---

### Task 3: ModelDepot Automated LRU Pruner & Disk Governance

**Files:**

- Create: `provision/k8s/apps/olah/pruner-cronjob.yaml`
- Create: `scripts/depot-prune.sh`

**Interfaces:**

- Consumes: ModelDepot directory `/mnt/model-depot/cache`
- Produces: Automated pruning logs and disk usage metrics

- [ ] **Step 1: Author ModelDepot pruning script**
      Author `scripts/depot-prune.sh` that checks disk usage against the 80% threshold:

  - Preserves locked/flagship models (e.g. `Nemotron-49B`, `North-Mini-Code`).
  - Prunes ad-hoc/benchmark snapshots based on access time (LRU) when utilization exceeds watermark.

- [ ] **Step 2: Deploy scheduled Pruner CronJob**
      Create `provision/k8s/apps/olah/pruner-cronjob.yaml` running nightly (`0 4 * * *`) on the AMD64 worker node.

---

### Task 4: Sparkrun & HuggingFace Client Integration

**Files:**

- Create: `provision/k8s/apps/inference/mixins/olah-endpoint.yaml`
- Modify: `tools/spark-to-k8s/compiler.go`

**Interfaces:**

- Consumes: `https://olah.colt.chalko.com`
- Produces: Environment injection `HF_ENDPOINT=https://olah.colt.chalko.com` into inference pods and `sparkrun` configurations

- [ ] **Step 1: Create reusable Olah endpoint mixin**
      Define `olah-endpoint.yaml` mixin setting `HF_ENDPOINT: "https://olah.colt.chalko.com"` and `HF_HUB_ENABLE_HF_TRANSFER: "1"`.

- [ ] **Step 2: Update compiler to support Olah proxy routing**
      Update `tools/spark-to-k8s/compiler.go` to inject `HF_ENDPOINT` when recipe specifies remote HuggingFace model IDs.

---

### Task 5: Verification & End-to-End Weight Hydration Test

- [ ] **Step 1: Commit and reconcile Flux CD**
      Commit manifests to `colt/main` and run `flux reconcile kustomization camp-colt-infra --with-source`.

- [ ] **Step 2: Verify Olah Pod status**
      Run: `kubectl get pods -n model-cache`
      Expected: Olah pod 1/1 Running.

- [ ] **Step 3: Test model hydration through proxy**
      Run a test snapshot download of a lightweight test tokenizer/model (`Qwen/Qwen2.5-0.5B`) through `https://olah.colt.chalko.com` and verify tensor files are saved in `/mnt/model-depot/cache` and served at line-rate on subsequent requests.
