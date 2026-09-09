# Spark Arena Recipe Integration & Benchmarking on GX10 (`sa-a1y`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement declarative Spark Arena recipe integration, reusable Kubernetes inference mixins, the `spark-to-k8s` manifest compiler (in Go), and automated in-cluster `llama-benchy` benchmarking on the ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10), fulfilling bead `sa-a1y`.

**Architecture:** A modular 4-layer cloud-native inference stack:

1. **Reusable K8s Inference Mixins**: Kustomize components decoupling ModelDepot/ReadyLocker caching (`model-depot-cache.yaml`), hardware affinity (`gb10-affinity.yaml`), and runtime engine templates (`nim-engine-base.yaml`, `vllm-engine-base.yaml`).
2. **Declarative Recipe Registry**: Standardized YAML recipe specifications for baseline NVIDIA NIM (`nemotron-49b-fp8.yaml`) and community vLLM nightly quant models (`north-mini-code-nvfp4.yaml`).
3. **`spark-to-k8s` Generator (Go)**: Type-safe CLI tool compiling declarative recipes into validated Kubernetes manifests implementing the 3-phase ModelDepot/ReadyLocker lifecycle and UMA kernel cache drops (`drop_caches`).
4. **Automated In-Cluster Benchmarking**: `llama-benchy` Kubernetes Job querying live cluster endpoints with the `--arena` flag and generating standard Spark Arena submission artifacts (`results.csv` + `recipe.yaml`).

**Tech Stack:** Go 1.24, Kubernetes v1.36 (Talos Linux / Proxmox VE), Kustomize, NVIDIA Grace Blackwell GB10 (128GB LPDDR5X UMA), NVIDIA NIM, vLLM (`ghcr.io/spark-arena/dgx-vllm-eugr-nightly`), `llama-benchy`, Flux GitOps.

**Spec:** [`scai/plans/0.1/spark_arena_recipe_gx10_integration_plan.md`](../../../scai/plans/0.1/spark_arena_recipe_gx10_integration_plan.md), Bead `sa-a1y`, and Directives in `lu-wisp-jtbo1w` & `lu-wisp-mx6p33`.

---

## Global Constraints

- **Strict Technical & Operational Focus**: Maintain architectural and systems engineering rigor across all `suitcase-ai` documentation and code (e.g. UMA memory envelope, PCIe bandwidth, kernel page cache management); exclude external strategic career/investor narratives from `suitcase-ai`.
- **Zero Plaintext Secrets**: Secrets referenced via Kubernetes `secretKeyRef` / Vault (`ngc-secret`).
- **Semantic Node Pinning (No Static Hostname)**: Target GPU capabilities directly:

  ```yaml
  nodeSelector:
    kubernetes.io/arch: arm64
    accelerator: gb10
    nvidia.com/gpu.present: "true"
  ```

- **GB10 UMA Memory Envelope**: Enforce `gpu-memory-utilization` between `0.70` and `0.75` (max 96 GB allocated) to guarantee a 32 GB host RAM buffer for kernel page tables, containerd, and system daemons.
- **Mandatory 3-Phase Pod Lifecycle**:
  - Phase 1A: `depot-hydration-preflight` (ModelDepot -> ReadyLocker restore)
  - Phase 1B: `download-model` / engine profile verification
  - Phase 1C: `cache-flusher` (`echo 3 > /proc/sys/vm/drop_caches`)
  - Phase 2: Runtime engine container
- **80-Line Go Rule**: Standalone generators exceeding 80 lines must be authored in Go with unit tests.

---

## Plan Overview & Task Breakdown

1. **Task 1: Reusable Kubernetes Inference Mixins & Kustomize Architecture**

   - Create `provision/k8s/apps/inference/mixins/gb10-affinity.yaml`
   - Create `provision/k8s/apps/inference/mixins/model-depot-cache.yaml`
   - Create `provision/k8s/apps/inference/mixins/nim-engine-base.yaml`
   - Create `provision/k8s/apps/inference/mixins/vllm-engine-base.yaml`
   - Refactor `provision/k8s/apps/inference/kustomization.yaml`

2. **Task 2: Declarative Recipe Schema & Registry**

   - Create `provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml` (Recipe #1: Baseline NVIDIA NIM)
   - Create `provision/k8s/apps/inference/recipes/north-mini-code-nvfp4.yaml` (Recipe #2: Community vLLM Nightly)

3. **Task 3: Implement `spark-to-k8s` Compiler (Go)**

   - Author Go module, recipe parser, manifest renderer, and CLI entrypoint in `tools/spark-to-k8s/`
   - Write comprehensive unit tests in `tools/spark-to-k8s/compiler_test.go`
   - Verify generation of both NIM and vLLM deployments

4. **Task 4: Automated In-Cluster `llama-benchy` Benchmarking Job**

   - Create `provision/k8s/apps/inference/benchmarks/llama-benchy-job.yaml`
   - Configure `--arena` parameters and PVC/hostPath output staging for leaderboard submissions

5. **Task 5: Technical Documentation & Systems Runbook**

   - Author `docs/SPARK_ARENA_RECIPES.md` detailing the recipe schema, `spark-to-k8s` workflow, and benchmark procedures

6. **Task 6: Verification, GitOps Push, Bead Closure, and Strategic Reporting**
   - Execute `go test ./tools/spark-to-k8s/...`
   - Validate manifests with `kubectl apply --dry-run=client`
   - Commit and push to `colt/main`
   - Close bead `sa-a1y`
   - Report completion to `scai/peggy` via `gc mail`

---

## Detailed Tasks

### Task 1: Reusable Kubernetes Inference Mixins & Kustomize Architecture

**Files:**

- Create: `provision/k8s/apps/inference/mixins/gb10-affinity.yaml`
- Create: `provision/k8s/apps/inference/mixins/model-depot-cache.yaml`
- Create: `provision/k8s/apps/inference/mixins/nim-engine-base.yaml`
- Create: `provision/k8s/apps/inference/mixins/vllm-engine-base.yaml`
- Modify: `provision/k8s/apps/inference/kustomization.yaml`

**Interfaces:**

- Produces: Composable Kustomize mixin building blocks for any sovereign LLM workload on Camp Colt.

- [ ] **Step 1: Create `provision/k8s/apps/inference/mixins/gb10-affinity.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-base
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        accelerator: gb10
        nvidia.com/gpu.present: "true"
      runtimeClassName: nvidia
      hostNetwork: true
      dnsPolicy: Default
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "dedicated"
          operator: "Equal"
          value: "gpu"
          effect: "NoSchedule"
```

- [ ] **Step 2: Create `provision/k8s/apps/inference/mixins/model-depot-cache.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-base
spec:
  template:
    spec:
      volumes:
        - name: local-ready-cache
          hostPath:
            path: /workspace/models/fast-cache
            type: DirectoryOrCreate
        - name: model-depot-storage
          hostPath:
            path: /mnt/model-depot
            type: DirectoryOrCreate
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 16Gi
        - name: proc
          hostPath:
            path: /proc
```

- [ ] **Step 3: Create `provision/k8s/apps/inference/mixins/nim-engine-base.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-base
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ngc-imagepull-secret
```

- [ ] **Step 4: Create `provision/k8s/apps/inference/mixins/vllm-engine-base.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-base
spec:
  template:
    spec:
      restartPolicy: Always
```

- [ ] **Step 5: Verify mixin syntax**

Run: `kubectl apply --dry-run=client -f provision/k8s/apps/inference/mixins/`
Expected: Return 0

- [ ] **Step 6: Commit mixins**

```bash
git add provision/k8s/apps/inference/mixins/
git commit -m "feat(inference): add reusable K8s mixins for GB10 affinity and ModelDepot storage"
```

---

### Task 2: Declarative Recipe Schema & Registry

**Files:**

- Create: `provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml`
- Create: `provision/k8s/apps/inference/recipes/north-mini-code-nvfp4.yaml`

**Interfaces:**

- Consumes: Model registry lineages and runtime tuning specs
- Produces: Declarative recipes consumed by `spark-to-k8s` compiler

- [ ] **Step 1: Create Recipe #1 `recipes/nemotron-49b-fp8.yaml`**

```yaml
apiVersion: inference.colt.ai/v1alpha1
kind: SparkRecipe
metadata:
  name: nemotron-49b-fp8
  labels:
    tier: flagship
    quant: fp8
spec:
  model:
    id: "nvidia/llama-3.3-nemotron-super-49b-v1.5"
    directory: "models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
    source: "ngc"
  runtime:
    engine: "nim"
    image: "nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:latest"
    profile: "498e09394f7016bb2f08d830e3da8ad03dcf7b027a227d57f397cc69682f05c8"
    gpuMemoryUtilization: 0.75
    maxNumSeqs: 64
    maxModelLen: 32768
    passthroughArgs: "--enable-prefix-caching --kv-cache-dtype fp8 --enable-auto-tool-choice --tool-call-parser llama3_json"
  hardware:
    accelerator: "gb10"
    arch: "arm64"
    gpuCount: 1
  storage:
    depotSource: "/mnt/model-depot/nims/validated/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
    readyTarget: "/opt/nim/.cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
```

- [ ] **Step 2: Create Recipe #2 `recipes/north-mini-code-nvfp4.yaml`**

```yaml
apiVersion: inference.colt.ai/v1alpha1
kind: SparkRecipe
metadata:
  name: north-mini-code-nvfp4
  labels:
    tier: community-arena
    quant: nvfp4
spec:
  model:
    id: "North-Mini-Code-NVFP4"
    directory: "models--north--mini-code-nvfp4"
    source: "huggingface"
  runtime:
    engine: "vllm"
    image: "ghcr.io/spark-arena/dgx-vllm-eugr-nightly:latest"
    gpuMemoryUtilization: 0.70
    maxNumSeqs: 128
    maxModelLen: 16384
    passthroughArgs: "--quantization fp4 --enforce-eager --kv-cache-dtype fp8"
  hardware:
    accelerator: "gb10"
    arch: "arm64"
    gpuCount: 1
  storage:
    depotSource: "/mnt/model-depot/huggingface/hub/models--north--mini-code-nvfp4"
    readyTarget: "/opt/nim/.cache/huggingface/hub/models--north--mini-code-nvfp4"
```

- [ ] **Step 3: Commit recipes**

```bash
git add provision/k8s/apps/inference/recipes/
git commit -m "feat(recipes): add declarative Spark recipes for Nemotron-49B and North-Mini-Code-NVFP4"
```

---

### Task 3: Implement `spark-to-k8s` Compiler (Go)

**Files:**

- Create: `tools/spark-to-k8s/go.mod`
- Create: `tools/spark-to-k8s/types.go`
- Create: `tools/spark-to-k8s/compiler.go`
- Create: `tools/spark-to-k8s/compiler_test.go`
- Create: `tools/spark-to-k8s/main.go`

**Interfaces:**

- Consumes: YAML SparkRecipe file path
- Produces: Validated multi-document Kubernetes YAML (Deployment + Service) to stdout or file

- [ ] **Step 1: Initialize Go module & dependencies**

```bash
mkdir -p tools/spark-to-k8s
cd tools/spark-to-k8s
go mod init colt.ai/spark-to-k8s
go get gopkg.in/yaml.v3
```

- [ ] **Step 2: Define Recipe & Manifest Data Models (`types.go`)**

```go
package main

type SparkRecipe struct {
 APIVersion string `yaml:"apiVersion"`
 Kind       string `yaml:"kind"`
 Metadata   struct {
  Name   string            `yaml:"name"`
  Labels map[string]string `yaml:"labels"`
 } `yaml:"metadata"`
 Spec struct {
  Model struct {
   ID        string `yaml:"id"`
   Directory string `yaml:"directory"`
   Source    string `yaml:"source"`
  } `yaml:"model"`
  Runtime struct {
   Engine               string  `yaml:"engine"`
   Image                string  `yaml:"image"`
   Profile              string  `yaml:"profile"`
   GPUMemoryUtilization float64 `yaml:"gpuMemoryUtilization"`
   MaxNumSeqs           int     `yaml:"maxNumSeqs"`
   MaxModelLen          int     `yaml:"maxModelLen"`
   PassthroughArgs      string  `yaml:"passthroughArgs"`
  } `yaml:"runtime"`
  Hardware struct {
   Accelerator string `yaml:"accelerator"`
   Arch        string `yaml:"arch"`
   GPUCount    int    `yaml:"gpuCount"`
  } `yaml:"hardware"`
  Storage struct {
   DepotSource string `yaml:"depotSource"`
   ReadyTarget string `yaml:"readyTarget"`
  } `yaml:"storage"`
 } `yaml:"spec"`
}
```

- [ ] **Step 3: Implement Compiler Logic (`compiler.go`)**

Generate the 3-phase initContainer pattern, GB10 node selectors, UMA page cache drop (`echo 3 > /proc/sys/vm/drop_caches`), and runtime container specifications based on engine type (`nim` vs `vllm`).

- [ ] **Step 4: Write Unit Tests (`compiler_test.go`)**

Test both NIM and vLLM recipes, asserting:

- `depot-hydration-preflight` initContainer is present with correct paths.
- `cache-flusher` privileged initContainer is present.
- `accelerator: gb10` and `nvidia.com/gpu.present: "true"` are in `nodeSelector`.
- Engine ports and environment variables are populated correctly.

- [ ] **Step 5: Run unit tests**

Run: `go test -v ./tools/spark-to-k8s/...`
Expected: PASS

- [ ] **Step 6: Build CLI entrypoint (`main.go`) and test rendering**

Run: `go run ./tools/spark-to-k8s/main.go provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml`
Expected: Validated Kubernetes Deployment & Service YAML emitted.

- [ ] **Step 7: Commit compiler**

```bash
git add tools/spark-to-k8s/
git commit -m "feat(tools): implement spark-to-k8s recipe compiler in Go with unit tests"
```

---

### Task 4: Automated In-Cluster `llama-benchy` Benchmarking Job

**Files:**

- Create: `provision/k8s/apps/inference/benchmarks/llama-benchy-job.yaml`

**Interfaces:**

- Consumes: Live inference endpoint in `nim-system` namespace (port 8000)
- Produces: Standardized benchmark output (`results.csv`, `recipe.yaml`) staged in `/workspace/benchmarks/`

- [ ] **Step 1: Write `llama-benchy-job.yaml`**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llama-benchy-benchmark
  namespace: nim-system
  labels:
    app: llama-benchy
    component: benchmarking
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 1
  template:
    metadata:
      labels:
        app: llama-benchy
    spec:
      restartPolicy: Never
      hostNetwork: true
      dnsPolicy: Default
      nodeSelector:
        kubernetes.io/arch: arm64
        accelerator: gb10
      containers:
        - name: llama-benchy
          image: ghcr.io/spark-arena/llama-benchy:latest
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              set -eu
              echo "==> [llama-benchy] Starting automated Spark Arena benchmark on GB10..."
              mkdir -p /workspace/benchmarks/latest
              llama-benchy \
                --base-url "http://127.0.0.1:8000/v1" \
                --model "nvidia/llama-3.3-nemotron-super-49b-v1.5" \
                --arena \
                --concurrency 1,4,16,32 \
                --prompt-tokens 512,2048 \
                --output-tokens 128,512 \
                --output-dir /workspace/benchmarks/latest
              echo "==> Benchmark complete. Output staged in /workspace/benchmarks/latest."
          volumeMounts:
            - name: benchmark-output
              mountPath: /workspace/benchmarks
      volumes:
        - name: benchmark-output
          hostPath:
            path: /workspace/benchmarks
            type: DirectoryOrCreate
```

- [ ] **Step 2: Validate Job manifest syntax**

Run: `kubectl apply --dry-run=client -f provision/k8s/apps/inference/benchmarks/llama-benchy-job.yaml`
Expected: Return 0

- [ ] **Step 3: Commit benchmark job**

```bash
git add provision/k8s/apps/inference/benchmarks/
git commit -m "feat(benchmarks): add automated in-cluster llama-benchy Job manifest"
```

---

### Task 5: Technical Systems Documentation & Architecture Guide

**Files:**

- Create: `docs/SPARK_ARENA_RECIPES.md`

**Interfaces:**

- Produces: Engineering runbook for operators deploying and benchmarking recipes on Camp Colt.

- [ ] **Step 1: Write `docs/SPARK_ARENA_RECIPES.md`**

Cover:

- Declarative Recipe Schema & Fields
- 3-Phase ModelDepot/ReadyLocker Lifecycle integration
- `spark-to-k8s` CLI compilation workflow
- Automated `llama-benchy` execution and Spark Arena submission packaging
- UMA memory management on Grace Blackwell GB10

- [ ] **Step 2: Verify markdown formatting and links**

Run: `test -f docs/SPARK_ARENA_RECIPES.md`
Expected: Return 0

- [ ] **Step 3: Commit documentation**

```bash
git add docs/SPARK_ARENA_RECIPES.md
git commit -m "docs(recipes): add Spark Arena recipe and benchmarking engineering guide"
```

---

### Task 6: Verification, GitOps Push, Bead Closure, and Strategic Reporting

- [ ] **Step 1: Run complete pre-flight test suite and syntax verification**

```bash
go test -v ./tools/spark-to-k8s/...
kubectl apply --dry-run=client -f provision/k8s/apps/inference/mixins/
kubectl apply --dry-run=client -f provision/k8s/apps/inference/benchmarks/
```

- [ ] **Step 2: Push changes to GitOps remote `colt/main`**

```bash
git push colt main
```

- [ ] **Step 3: Close bead `sa-a1y`**

```bash
bd close sa-a1y -r "Implemented Spark Arena recipe integration, spark-to-k8s compiler, reusable K8s mixins, and automated llama-benchy benchmarking on GX10"
```

- [ ] **Step 4: Send strategic confirmation mail to `scai/peggy`**

```bash
gc mail send scai/peggy --subject "RE: Task Bead Assigned: sa-a1y (Spark Recipe Integration & Benchmarking)" --body "Peggy,

Task bead sa-a1y has been fully implemented, tested, and pushed to colt/main:

1. Reusable K8s Mixins: Modularized GB10 affinity, ModelDepot/ReadyLocker caching, and engine templates in provision/k8s/apps/inference/mixins/.
2. Declarative Recipe Registry: Authored recipes for Nemotron-49B FP8 and North-Mini-Code-NVFP4 in provision/k8s/apps/inference/recipes/.
3. spark-to-k8s Compiler (Go): Implemented type-safe compiler in tools/spark-to-k8s/ with 100% passing unit tests enforcing 3-phase ModelDepot lifecycle and UMA drop_caches flush.
4. Automated In-Cluster Benchmarking: Created llama-benchy Job manifest for automated Spark Arena runs.
5. Documentation: Authored docs/SPARK_ARENA_RECIPES.md adhering to strict technical/systems engineering scope.

Bead sa-a1y is closed."
```
