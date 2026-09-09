# Spark Recipe Registry

This directory contains declarative inference recipes (`SparkRecipe`) targeting the ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10) appliance within Camp Colt.

---

## Schema Reference

Recipes use the `inference.colt.ai/v1alpha1` API version and `SparkRecipe` resource kind.

```yaml
apiVersion: inference.colt.ai/v1alpha1
kind: SparkRecipe
metadata:
  name: <recipe-name>
  labels:
    tier: <flagship|community-arena|specialized>
    quant: <fp8|nvfp4|int4|bf16>
spec:
  model:
    id: <model-identifier>
    directory: <model-cache-directory-name>
    source: <ngc|huggingface|local>
  runtime:
    engine: <nim|vllm>
    image: <container-image-uri>
    profile: <nim-profile-hash-if-applicable>
    gpuMemoryUtilization: <0.70-0.75>
    maxNumSeqs: <integer>
    maxModelLen: <integer>
    passthroughArgs: <engine-cli-flags>
  hardware:
    accelerator: gb10
    arch: arm64
    gpuCount: 1
  storage:
    depotSource: <immutable-nfs-or-depot-path>
    readyTarget: <fast-cache-mount-target>
```

---

## Core Specification Fields

### 1. `metadata`

- **`name`**: Unique identifier for the recipe (e.g. `nemotron-49b-fp8`, `north-mini-code-nvfp4`).
- **`labels`**: Metadata tags for categorization (e.g., `tier: flagship`, `quant: fp8`).

### 2. `spec.model`

- **`id`**: Upstream model identifier (e.g., `nvidia/llama-3.3-nemotron-super-49b-v1.5`, `North-Mini-Code-NVFP4`).
- **`directory`**: Subdirectory name formatted according to cache conventions (`models--<org>--<name>`).
- **`source`**: Model source repository (`ngc` for NVIDIA NGC registry, `huggingface` for HuggingFace Hub).

### 3. `spec.runtime`

- **`engine`**: Inference serving framework (`nim` for NVIDIA Inference Microservices, `vllm` for vLLM).
- **`image`**: Fully qualified container image reference.
- **`profile`**: (Optional / NIM) Hardware-optimized profile hash.
- **`gpuMemoryUtilization`**: Fraction of Unified Memory Architecture (UMA) allocated to weights and KV cache (strictly bounded to `0.70` - `0.75`).
- **`maxNumSeqs`**: Maximum concurrent sequences / batch slots.
- **`maxModelLen`**: Maximum context length (e.g. `32768`, `16384`).
- **`passthroughArgs`**: Framework-specific arguments (e.g., prefix caching, FP8/NVFP4 quantization, tool calling parsers).

### 4. `spec.hardware`

- **`accelerator`**: Target GPU accelerator architecture (`gb10` for NVIDIA Grace Blackwell GB10).
- **`arch`**: Host CPU architecture (`arm64` for NVIDIA Grace CPU).
- **`gpuCount`**: Number of GPUs allocated (default: `1`).

### 5. `spec.storage`

- **`depotSource`**: Immutable ModelDepot source path (`/mnt/model-depot/...`).
- **`readyTarget`**: Fast-cache NVMe path inside the container (`/opt/nim/.cache/...`).

---

## Memory Envelope & UMA Limits

The ASUS Ascent GX10 features a unified 128 GB LPDDR5X memory architecture shared between the NVIDIA Grace CPU and Blackwell GB10 GPU.

- **Maximum `gpuMemoryUtilization`**: Must NOT exceed `0.75` (96 GB allocated for GPU weight/KV cache).
- **Host Buffer**: A minimum of 32 GB RAM is strictly reserved for kernel page tables, Talos Linux system services, containerd, and networking buffers.
- **Page Cache Management**: Pods generated from these recipes must include a privileged `cache-flusher` init container (`echo 3 > /proc/sys/vm/drop_caches`) post-hydration to free host memory before the inference engine allocates its memory pool.

---

## Storage Architecture: ModelDepot & ReadyLocker

- **ModelDepot (`/mnt/model-depot`)**: Immutable, persistent capacity tier housing validated model weights and NGC/HuggingFace artifacts. Mounted read-only into preflight hydration containers.
- **ReadyLocker (`/workspace/models/fast-cache` -> `/opt/nim/.cache`)**: High-speed local NVMe fast-cache providing instant warmup and eliminating re-downloads across container restarts.

---

## Registered Recipes

| Recipe File                                                | Model                             | Engine       | Precision | Context Len | Memory Util |
| :--------------------------------------------------------- | :-------------------------------- | :----------- | :-------- | :---------- | :---------- |
| [`nemotron-49b-fp8.yaml`](nemotron-49b-fp8.yaml)           | Llama-3.3-Nemotron-Super-49B-v1.5 | NIM          | FP8       | 32,768      | 0.75        |
| [`north-mini-code-nvfp4.yaml`](north-mini-code-nvfp4.yaml) | North-Mini-Code                   | vLLM Nightly | NVFP4     | 16,384      | 0.70        |

---

## Compilation

Recipes are compiled into standard Kubernetes Deployment and Service manifests using the `spark-to-k8s` compiler:

```bash
spark-to-k8s provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml > provision/k8s/apps/inference/nemotron-49b.yaml
```
