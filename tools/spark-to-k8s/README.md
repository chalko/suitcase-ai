# spark-to-k8s: Declarative Recipe Manifest Compiler

`spark-to-k8s` is a type-safe Go CLI compiler that transforms high-level, declarative inference recipes (`inference.colt.ai/v1alpha1 SparkRecipe`) into fully validated, production-ready Kubernetes manifests (`Deployment` and `Service`) targeting the ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10) appliance in Camp Colt.

---

## 🎯 Key Features

1. **Strict GB10 UMA Validation**:

   - Enforces the GB10 memory envelope (`gpuMemoryUtilization <= 0.75` / 96 GB) to guarantee a minimum 32 GB RAM buffer for kernel page tables, Talos Linux system services, and containerd.
   - Requires `accelerator: gb10` and `arch: arm64`.

2. **Automated 3-Phase ModelDepot / ReadyLocker Lifecycle**:

   - **Phase 1A (`depot-hydration-preflight`)**: Busybox initContainer verifying and restoring model weights from immutable ModelDepot (`/mnt/model-depot`) into the local NVMe ReadyLocker (`/workspace/models/fast-cache` -> `/opt/nim/.cache`) and ensuring write permissions.
   - **Phase 1B (Engine Profile Verification)**: Profile validation using `download-to-cache` (NVIDIA NIM) or fast directory integrity checks (vLLM).
   - **Phase 1C (`cache-flusher`)**: Privileged initContainer executing `sync; echo 3 > /proc/sys/vm/drop_caches` to free dirty kernel pages post-hydration before the inference runtime initializes its tensor pool.
   - **Phase 2 (Engine Runtime)**: Hardened container specification with decoupled API (port 8000) and health probe (port 8002) endpoints, UMA memory clamping, and hardware affinities.

3. **Multi-Engine Support**:

   - Native compilation for **NVIDIA NIM** (`nim`) containers and **vLLM** (`vllm`) nightly releases.

4. **Hardware Pinning & Tolerations**:
   - Injects `nodeSelector` (`accelerator: gb10`, `kubernetes.io/arch: arm64`, `nvidia.com/gpu.present: "true"`), GPU tolerations, `runtimeClassName: nvidia`, and `hostNetwork: true`.

---

## 🚀 Installation & Building

```bash
cd tools/spark-to-k8s
go build -o /usr/local/bin/spark-to-k8s .
```

---

## 🛠️ CLI Usage & Options

```text
Usage: spark-to-k8s [options] <recipe.yaml>

Options:
  -i, --input string       Path to the input SparkRecipe YAML file
  -o, --output string      Path to the output Kubernetes YAML manifest file (writes to stdout if omitted)
  -n, --namespace string   Kubernetes namespace for the generated resources (default "nim-system")
  -v, --validate           Validate recipe syntax and constraints without generating full manifest
```

---

## 📋 Examples

### 1. Validate a recipe without compiling

```bash
spark-to-k8s --validate provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml
```

### 2. Compile a recipe to stdout

```bash
spark-to-k8s provision/k8s/apps/inference/recipes/north-mini-code-nvfp4.yaml
```

### 3. Compile and save to a Kubernetes manifest file

```bash
spark-to-k8s -i provision/k8s/apps/inference/recipes/north-mini-code-nvfp4.yaml \
             -o provision/k8s/apps/inference/north-mini-code-nvfp4.yaml \
             -n nim-system
```

---

## 🧪 Testing

Execute unit tests covering schema validation, UMA limits, and manifest generation:

```bash
go test -v ./tools/spark-to-k8s/...
```
