# NVIDIA Nemotron-49B Two-Phase Inference Bringup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the validated flagship NVIDIA Nemotron-49B-FP8 NIM inference service on `colt-gpu-01` (ASUS Ascent GX10 / NVIDIA Grace Blackwell GB10) using our hardened two-phase initContainer pattern, decoupled health probes, and host NVMe/Dewpoint storage caching, reconciled via Flux GitOps.

**Architecture:** Two-phase container lifecycle decoupling storage pre-flight/Dewpoint cache restore and NVIDIA profile validation (`download-to-cache`) from the runtime inference engine (`nemotron-engine`). Inference runs with decoupled ports (8001 inference / 8002 health), the GB10 UMA 80% memory limit rule, and a cluster Service exposing port 8000.

**Tech Stack:** Kubernetes v1.36.4, Talos Linux v1.14.0, NVIDIA NIM (`nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:latest`), Blackwell sm_121 FP8 profile (`f3b4963ec6c3826a2377ea80c1dcd05bef1c6267a9eb67805e3872b8fe2151ae`), HashiCorp Vault, Flux GitOps.

**Spec:** `docs/gx10_k8s_architecture.md`, `docs/DEWPOINT.md`, Fog `nemotron-49b-fp8.yaml`.

## Global Constraints

- **Zero Plaintext Secrets:** All API keys and registry credentials managed through HashiCorp Vault (`secret/data/colt/infra/ngc`).
- **Strict Node Pinning:** Target `colt-gpu-01` exclusively (`kubernetes.io/hostname: colt-gpu-01`, `kubernetes.io/arch: arm64`).
- **UMA Memory Sizing:** Set `NIM_GPU_MEMORY_UTILIZATION: 0.50` (or `0.75-0.78`) to guarantee a 28–30 GB unallocated host RAM buffer for kernel, containerd, and system daemons on the 128 GB LPDDR5X UMA architecture.
- **Model Clearance Compliance:** Model weights strictly restricted to cleared models per `model_clearance_registry.md`.
- **Offline-First Cache:** Rely on local NVMe fast tier (`/workspace/models/nim-cache`) and capacity tier (`/mnt/dewpoint`) to avoid WAN re-downloads.

---

## The Two-Phase InitContainer Pattern

```text
+-----------------------------------------------------------------------------------------+
| Pod: nemotron-49b-haze                                                                  |
|                                                                                         |
|  [PHASE 1A: Dewpoint & Host Storage Pre-Flight] (initContainer: dewpoint-preflight)    |
|  ├── Mounts /mnt/dewpoint (Capacity Tier) and /workspace/models/nim-cache (NVMe Tier)   |
|  ├── Checks if model files exist in /opt/nim/.cache/ngc/hub/                            |
|  ├── If missing, restores/hardlinks from /mnt/dewpoint/nims/validated/                  |
|  └── Flushes caches (sync; drop_caches) and sets correct ownership                      |
|                                     │ (Exits code 0)                                    |
|                                     ▼                                                   |
|  [PHASE 1B: NVIDIA Profile Validation] (initContainer: download-model)                  |
|  ├── Image: nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:latest                |
|  ├── Command: download-to-cache --profiles f3b4963ec6c3826a2377ea80c1dcd05bef1c6267a9eb6|
|  ├── Verifies manifest integrity against pre-warmed cache (takes < 5s)                  |
|  └── Exits code 0 WITHOUT claiming GPU cores or starting CUDA driver                    |
|                                     │ (Exits code 0)                                    |
|                                     ▼                                                   |
|  [PHASE 1C: Page Cache Flusher] (initContainer: cache-flusher)                         |
|  ├── Image: docker.io/library/busybox:1.36                                              |
|  ├── SecurityContext: privileged: true                                                  |
|  ├── VolumeMount: /proc -> hostPath /proc                                               |
|  ├── Command: sync; echo 3 > /proc/sys/vm/drop_caches || true                            |
|  ├── Drops kernel disk page cache after heavy staging so UMA memory doesn't block boot  |
|  └── Exits code 0                                                                       |
|                                     │ (Exits code 0)                                    |
|                                     ▼                                                   |
|  [PHASE 2: NIM Inference Runtime Engine] (container: nemotron-engine)                   |
|  ├── Claims nvidia.com/gpu: 1                                                           |
|  ├── Mounts local-nvme-cache and 16Gi emptyDir Memory /dev/shm                          |
|  ├── Port 8001: HTTP Inference API (/v1/chat/completions)                               |
|  └── Port 8002: Decoupled Health Probes (/v1/health/ready, /v1/health/live)             |
+-----------------------------------------------------------------------------------------+
```

---

## File Structure

- Create: `provision/k8s/apps/inference/namespace.yaml` - Defines `nim-system` namespace.
- Create: `provision/k8s/apps/inference/secrets.yaml` - Secrets for NGC access (`ngc-secret`, `ngc-imagepull-secret`).
- Create: `provision/k8s/apps/inference/nemotron-49b.yaml` - Deployment and Service implementing the two-phase initContainer pattern.
- Create: `provision/k8s/apps/inference/kustomization.yaml` - Kustomization for inference app.
- Modify: `provision/k8s/kustomization.yaml` - Include `apps/inference` in root cluster resources.

---

## Tasks

### Task 1: NGC Secret Provisioning in Vault & Namespace Setup

**Files:**

- Create: `provision/k8s/apps/inference/namespace.yaml`
- Create: `provision/k8s/apps/inference/secrets.yaml`

**Interfaces:**

- Consumes: Vault secret `secret/data/colt/infra/ngc` (or creates it if absent)
- Produces: Secret `ngc-secret` and `ngc-imagepull-secret` in namespace `nim-system`

- [ ] **Step 1: Create the `nim-system` namespace manifest**

```yaml
# provision/k8s/apps/inference/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nim-system
  labels:
    app.kubernetes.io/part-of: colt-inference
```

- [ ] **Step 2: Check or populate NGC credentials in Vault**

```bash
source scripts/load_colt_env.sh
vault kv get secret/colt/infra/ngc || echo "Need NGC_API_KEY to store in Vault"
```

- [ ] **Step 3: Create secrets manifest for `nim-system`**

```yaml
# provision/k8s/apps/inference/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ngc-secret
  namespace: nim-system
type: Opaque
stringData:
  NGC_API_KEY: "<vault-injected-or-synced>"
---
apiVersion: v1
kind: Secret
metadata:
  name: ngc-imagepull-secret
  namespace: nim-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: "<vault-injected-dockerconfig>"
```

- [ ] **Step 4: Verify secret applying cleanly in cluster**

```bash
KUBECONFIG=/tmp/colt-kubeconfig kubectl apply -f provision/k8s/apps/inference/namespace.yaml
KUBECONFIG=/tmp/colt-kubeconfig kubectl get ns nim-system
```

---

### Task 2: Fast NVMe Cache Hydration & Verification from Dewpoint

**Files:**

- Script: `scripts/dewpoint-nim-sync.sh`

**Interfaces:**

- Consumes: `/mnt/dewpoint/nims/validated/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5` on `colt-gpu-01`
- Produces: `/workspace/models/nim-cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5` on `colt-gpu-01`

- [ ] **Step 1: Check existing cache on `colt-gpu-01`**

```bash
ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.3 \
  "ls -la /workspace/models/nim-cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5 2>/dev/null || echo 'Not linked in fast cache'"
```

- [ ] **Step 2: Link or restore model weights from Dewpoint to fast NVMe cache**

```bash
ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.3 \
  "sudo mkdir -p /workspace/models/nim-cache/ngc/hub && \
   if [ ! -d /workspace/models/nim-cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5 ]; then \
     echo 'Linking validated Nemotron-49B weights from Dewpoint...'; \
     sudo cp -al /mnt/dewpoint/nims/validated/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5 /workspace/models/nim-cache/ngc/hub/; \
   fi && \
   sudo chown -R nick:root /workspace/models/nim-cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5 && \
   sudo chmod -R 775 /workspace/models/nim-cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
```

- [ ] **Step 3: Verify model files and profile shards on `colt-gpu-01`**

```bash
ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.3 \
  "du -sh /workspace/models/nim-cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
```

---

### Task 3: Manifest Creation - Two-Phase InitContainer Deployment & Service

**Files:**

- Create: `provision/k8s/apps/inference/nemotron-49b.yaml`
- Create: `provision/k8s/apps/inference/kustomization.yaml`
- Modify: `provision/k8s/kustomization.yaml`

**Interfaces:**

- Consumes: `ngc-secret`, `local-nvme-cache` (`/workspace/models/nim-cache`), `dewpoint-storage` (`/mnt/dewpoint`)
- Produces: Service `nemotron-49b.nim-system.svc.cluster.local:8000`

- [ ] **Step 1: Create `nemotron-49b.yaml` with the two-phase initContainer pattern**

```yaml
# provision/k8s/apps/inference/nemotron-49b.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nemotron-49b-haze
  namespace: nim-system
  labels:
    app.kubernetes.io/name: nemotron-49b
    app.kubernetes.io/component: llm-inference
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nemotron-49b
  template:
    metadata:
      labels:
        app: nemotron-49b
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        kubernetes.io/hostname: colt-gpu-01
      hostNetwork: true
      dnsPolicy: Default
      imagePullSecrets:
        - name: ngc-imagepull-secret
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "dedicated"
          operator: "Equal"
          value: "gpu"
          effect: "NoSchedule"
      initContainers:
        # Phase 1A: Pre-flight Dewpoint check, permission verification, and cache sync
        - name: dewpoint-preflight
          image: docker.io/library/busybox:1.36
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              echo "==> [Phase 1A] Checking NVMe fast cache for Nemotron-49B..."
              TARGET="/opt/nim/.cache/ngc/hub/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
              SOURCE="/mnt/dewpoint/nims/validated/models--nim--nvidia--llama-3.3-nemotron-super-49b-v1.5"
              if [ ! -d "$TARGET" ] && [ -d "$SOURCE" ]; then
                echo "Restoring from Dewpoint validated storage..."
                mkdir -p /opt/nim/.cache/ngc/hub
                cp -al "$SOURCE" "$TARGET"
              fi
              echo "Syncing filesystem and verifying directory structure..."
              sync
              echo "Phase 1A Pre-flight completed."
          volumeMounts:
            - name: local-nvme-cache
              mountPath: /opt/nim/.cache
            - name: dewpoint-storage
              mountPath: /mnt/dewpoint
              readOnly: true
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "4"
              memory: "4Gi"

        # Phase 1B: Official NVIDIA NIM profile download-to-cache and manifest validation
        - name: download-model
          image: nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:latest
          imagePullPolicy: IfNotPresent
          command:
            - download-to-cache
          args:
            - --profiles
            - "f3b4963ec6c3826a2377ea80c1dcd05bef1c6267a9eb67805e3872b8fe2151ae"
          env:
            - name: NGC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ngc-secret
                  key: NGC_API_KEY
            - name: NIM_MODEL_NAME
              value: "nvidia/llama-3.3-nemotron-super-49b-v1.5"
            - name: NIM_CACHE_PATH
              value: "/opt/nim/.cache"
          resources:
            requests:
              cpu: "4"
              memory: "8Gi"
            limits:
              cpu: "20"
              memory: "110Gi"
          volumeMounts:
            - name: local-nvme-cache
              mountPath: /opt/nim/.cache
            - name: dshm
              mountPath: /dev/shm

        # Phase 1C: Flush Linux kernel page cache after hydration to prevent blocking engine startup on UMA
        - name: cache-flusher
          image: docker.io/library/busybox:1.36
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
          command:
            - "/bin/sh"
            - "-c"
            - |
              echo "==> Flushing Linux kernel page cache after hydration..."
              sync
              echo 3 > /proc/sys/vm/drop_caches || true
              echo "==> Page cache flush complete."
          volumeMounts:
            - name: proc
              mountPath: /proc

      # Phase 2: Runtime Inference Engine
      containers:
        - name: nemotron-engine
          image: nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:latest
          imagePullPolicy: IfNotPresent
          env:
            - name: NGC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ngc-secret
                  key: NGC_API_KEY
            - name: NIM_CACHE_PATH
              value: "/opt/nim/.cache"
            - name: NIM_MODEL_NAME
              value: "nvidia/llama-3.3-nemotron-super-49b-v1.5"
            - name: NIM_SERVER_PORT
              value: "8001"
            - name: NIM_HEALTH_PORT
              value: "8002"
            - name: NIM_HTTP_API_PORT
              value: "8001"
            - name: NIM_GPU_MEMORY_UTILIZATION
              value: "0.50"
            - name: NIM_ENABLE_KV_CACHE_REUSE
              value: "1"
            - name: NIM_PASSTHROUGH_ARGS
              value: "--port 8001 --enable-prefix-caching --kv-cache-dtype fp8 --enable-auto-tool-choice --tool-call-parser llama3_json"
            - name: NIM_MAX_NUM_SEQS
              value: "64"
            - name: NIM_MAX_MODEL_LEN
              value: "32768"
            - name: NVIDIA_VISIBLE_DEVICES
              value: "all"
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: "all"
          ports:
            - name: http-api
              containerPort: 8001
              protocol: TCP
            - name: health-api
              containerPort: 8002
              protocol: TCP
          resources:
            requests:
              cpu: "8"
              memory: "32Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "20"
              memory: "110Gi"
              nvidia.com/gpu: "1"
          volumeMounts:
            - name: local-nvme-cache
              mountPath: /opt/nim/.cache
            - name: dshm
              mountPath: /dev/shm
          startupProbe:
            httpGet:
              path: /v1/health/ready
              port: 8002
            initialDelaySeconds: 20
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /v1/health/live
              port: 8002
            initialDelaySeconds: 30
            periodSeconds: 30
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /v1/health/ready
              port: 8002
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
      volumes:
        - name: local-nvme-cache
          hostPath:
            path: /workspace/models/nim-cache
            type: DirectoryOrCreate
        - name: dewpoint-storage
          hostPath:
            path: /mnt/dewpoint
            type: DirectoryOrCreate
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 16Gi
        - name: proc
          hostPath:
            path: /proc
---
apiVersion: v1
kind: Service
metadata:
  name: nemotron-49b
  namespace: nim-system
  labels:
    app.kubernetes.io/name: nemotron-49b
    app.kubernetes.io/component: llm-inference
spec:
  type: ClusterIP
  selector:
    app: nemotron-49b
  ports:
    - name: http
      port: 8000
      targetPort: 8001
      protocol: TCP
    - name: health
      port: 8002
      targetPort: 8002
      protocol: TCP
```

- [ ] **Step 2: Create `provision/k8s/apps/inference/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - secrets.yaml
  - nemotron-49b.yaml
```

- [ ] **Step 3: Update `provision/k8s/kustomization.yaml`**

Add `- apps/inference` to the resources list.

- [ ] **Step 4: Run dry-run validation**

```bash
kubectl kustomize provision/k8s/apps/inference > /tmp/test-inference.yaml
head -n 40 /tmp/test-inference.yaml
```

---

### Task 4: GitOps Commit & Reconcile via Flux

**Files:**

- Modify: `provision/k8s/kustomization.yaml`
- Create: `provision/k8s/apps/inference/*`

**Interfaces:**

- Git repository: `colt/main`
- Flux Kustomization: `colt-cluster`

- [ ] **Step 1: Commit manifests to git**

```bash
git add provision/k8s/apps/inference provision/k8s/kustomization.yaml
git commit -m "feat(inference): deploy Nemotron-49B-FP8 NIM with two-phase initContainer pattern"
git push colt main
```

- [ ] **Step 2: Trigger and watch Flux reconciliation**

```bash
KUBECONFIG=/tmp/colt-kubeconfig flux reconcile kustomization colt-cluster --with-source
```

- [ ] **Step 3: Monitor pod lifecycle and initContainer execution**

```bash
KUBECONFIG=/tmp/colt-kubeconfig kubectl get pods -n nim-system -w
```

---

### Task 5: End-to-End Inference Verification

**Files:**

- None (verification commands)

**Interfaces:**

- Consumes: `http://nemotron-49b.nim-system.svc.cluster.local:8000/v1`

- [ ] **Step 1: Check pod logs for Phase 1a, Phase 1b, and Phase 2**

```bash
POD_NAME=$(KUBECONFIG=/tmp/colt-kubeconfig kubectl get pods -n nim-system -l app=nemotron-49b -o jsonpath='{.items[0].metadata.name}')
KUBECONFIG=/tmp/colt-kubeconfig kubectl logs -n nim-system $POD_NAME -c dewpoint-preflight
KUBECONFIG=/tmp/colt-kubeconfig kubectl logs -n nim-system $POD_NAME -c download-model
KUBECONFIG=/tmp/colt-kubeconfig kubectl logs -n nim-system $POD_NAME -c nemotron-engine --tail=50
```

- [ ] **Step 2: Verify GPU memory allocation and temperature**

```bash
ssh -i agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent colt-sysadmin-agent@10.82.0.3 "nvidia-smi"
```

- [ ] **Step 3: Execute model health check & completion query**

```bash
KUBECONFIG=/tmp/colt-kubeconfig kubectl run test-curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s http://nemotron-49b.nim-system.svc.cluster.local:8000/v1/models

KUBECONFIG=/tmp/colt-kubeconfig kubectl run test-completion --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -X POST http://nemotron-49b.nim-system.svc.cluster.local:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/llama-3.3-nemotron-super-49b-v1.5",
    "messages": [{"role": "user", "content": "Respond with: Camp Colt Sovereign AI Operational"}],
    "max_tokens": 30
  }'
```
