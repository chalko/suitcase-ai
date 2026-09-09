# LiteLLM Gateway Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the LiteLLM Proxy Gateway routing exclusively to our sovereign `nemotron-super-49b-v1.5` inference service, backed by PostgreSQL, managed through Vault secrets, and exposed via in-cluster service and internal Ingress.

**Architecture:** LiteLLM proxy pod with collocated PostgreSQL sidecar. Untolerated pod naturally schedules on general-purpose worker nodes because `colt-gpu-01` is tainted with `nvidia.com/gpu=present:NoSchedule`. Configured with a single model target `nemotron-super-49b-v1.5` proxying to `http://nemotron-49b.nim-system.svc.cluster.local:8000/v1`. Exposed internally via Service `litellm:4000` and internal Ingress (no Cloud DNS).

**Tech Stack:** Kubernetes v1.36.4, Talos Linux v1.14.0, LiteLLM (`ghcr.io/berriai/litellm:main-latest`), PostgreSQL 16 Alpine, HashiCorp Vault, Ingress-NGINX, Flux GitOps.

**Spec:** Fog LiteLLM reference (`https://github.com/BerriAI/litellm`), `AGENTS.md` (Least Privilege & Zero Secret).

## Global Constraints

- **Scheduling:** Standard untolerated deployment. GPU node `colt-gpu-01` is tainted (`nvidia.com/gpu=present:NoSchedule`), ensuring workloads land on CPU worker nodes without requiring explicit nodeSelector pinning.
- **Single Model Configuration:** Only expose `nemotron-super-49b-v1.5` (plus official fully-qualified name `nvidia/llama-3.3-nemotron-super-49b-v1.5`). Zero fallback to cloud models.
- **Zero Plaintext Secrets:** `LITELLM_MASTER_KEY` generated and stored in Vault at `secret/data/colt/litellm/master_key`.
- **No Cloud DNS:** Do NOT register in Google Cloud DNS. Accessible internally via ClusterIP service `http://litellm.litellm.svc.cluster.local:4000` and cluster-internal Ingress.
- **TLS:** Ingress-NGINX with wildcard TLS certificate (`colt-chalko-wildcard-tls`).

---

## File Structure

- Create: `provision/k8s/apps/litellm/namespace.yaml` - Declares `litellm` namespace.
- Create: `provision/k8s/apps/litellm/configmap.yaml` - LiteLLM router configuration with single `nemotron-super-49b-v1.5` model.
- Create: `provision/k8s/apps/litellm/deployment.yaml` - LiteLLM + PostgreSQL sidecar deployment, PVC (5Gi `local-path`), and Service.
- Create: `provision/k8s/apps/litellm/ingress.yaml` - Ingress for `litellm.colt.chalko.com`.
- Create: `provision/k8s/apps/litellm/kustomization.yaml` - Kustomization aggregating LiteLLM manifests.
- Modify: `provision/k8s/kustomization.yaml` - Wire `apps/litellm` into Flux GitOps tree.

---

## Tasks

### Task 1: Vault Secret Generation & Cluster Secret Sync

**Files:**

- None (CLI commands against Vault and Kubernetes)

**Interfaces:**

- Produces:

  - Vault secret `secret/data/colt/litellm/master_key`
  - Kubernetes secret `litellm-secrets` in namespace `litellm`

- [ ] **Step 1: Generate and store LiteLLM master key in Vault**

```bash
source scripts/load_colt_env.sh
MASTER_KEY="sk-colt-$(openssl rand -hex 16)"
vault kv put secret/colt/litellm/master_key master_key="$MASTER_KEY"
echo "LiteLLM master key provisioned in Vault."
```

- [ ] **Step 2: Create namespace and sync Kubernetes secret**

```bash
export KUBECONFIG=/tmp/colt-kubeconfig
kubectl create namespace litellm --dry-run=client -o yaml | kubectl apply -f -

MASTER_KEY=$(vault kv get -field=master_key secret/colt/litellm/master_key)
kubectl create secret generic litellm-secrets \
  --namespace litellm \
  --from-literal=master-key="$MASTER_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

### Task 2: Create Declarative LiteLLM Manifests

**Files:**

- Create: `provision/k8s/apps/litellm/namespace.yaml`
- Create: `provision/k8s/apps/litellm/configmap.yaml`
- Create: `provision/k8s/apps/litellm/deployment.yaml`
- Create: `provision/k8s/apps/litellm/ingress.yaml`
- Create: `provision/k8s/apps/litellm/kustomization.yaml`

**Interfaces:**

- Consumes: In-cluster inference endpoint `http://nemotron-49b.nim-system.svc.cluster.local:8000/v1`
- Produces: Service `litellm.litellm.svc.cluster.local:4000`

- [ ] **Step 1: Create namespace manifest**

```yaml
# provision/k8s/apps/litellm/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: litellm
  labels:
    app.kubernetes.io/part-of: colt-platform
```

- [ ] **Step 2: Create LiteLLM ConfigMap with single model route**

```yaml
# provision/k8s/apps/litellm/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
  namespace: litellm
data:
  config.yaml: |
    model_list:
      # Primary Model Route: Nemotron Super 49B v1.5
      - model_name: nemotron-super-49b-v1.5
        litellm_params:
          model: hosted_vllm/nvidia/llama-3.3-nemotron-super-49b-v1.5
          api_base: http://nemotron-49b.nim-system.svc.cluster.local:8000/v1
          api_key: "local-nim-key"
          temperature: 0.6
          max_tokens: 8192

      # Fully qualified NGC model name alias
      - model_name: nvidia/llama-3.3-nemotron-super-49b-v1.5
        litellm_params:
          model: hosted_vllm/nvidia/llama-3.3-nemotron-super-49b-v1.5
          api_base: http://nemotron-49b.nim-system.svc.cluster.local:8000/v1
          api_key: "local-nim-key"
          temperature: 0.6
          max_tokens: 8192

    litellm_settings:
      drop_params: true
      telemetry: false

    router_settings:
      routing_strategy: simple-shuffle
      num_retries: 2
      timeout: 120
```

- [ ] **Step 3: Create Deployment, PVC, and Service (untolerated, naturally scheduled on CPU worker)**

```yaml
# provision/k8s/apps/litellm/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm
  namespace: litellm
  labels:
    app: litellm
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: litellm
  template:
    metadata:
      labels:
        app: litellm
    spec:
      containers:
        - name: litellm
          image: ghcr.io/berriai/litellm:main-latest
          imagePullPolicy: IfNotPresent
          args:
            - "--config"
            - "/app/config.yaml"
            - "--port"
            - "4000"
          ports:
            - containerPort: 4000
              name: http
          env:
            - name: LITELLM_MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-secrets
                  key: master-key
            - name: DATABASE_URL
              value: "postgresql://postgres:postgres@localhost:5432/litellm"
          volumeMounts:
            - name: config-volume
              mountPath: /app/config.yaml
              subPath: config.yaml
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            httpGet:
              path: /health/readiness
              port: 4000
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 3
          livenessProbe:
            httpGet:
              path: /health/liveness
              port: 4000
            initialDelaySeconds: 30
            periodSeconds: 15
            timeoutSeconds: 3

        - name: postgres
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 5432
              name: postgres
          env:
            - name: POSTGRES_USER
              value: "postgres"
            - name: POSTGRES_PASSWORD
              value: "postgres"
            - name: POSTGRES_DB
              value: "litellm"
          volumeMounts:
            - name: database-volume
              mountPath: /var/lib/postgresql/data
              subPath: postgres-data
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
      volumes:
        - name: config-volume
          configMap:
            name: litellm-config
        - name: database-volume
          persistentVolumeClaim:
            claimName: litellm-db-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: litellm-db-pvc
  namespace: litellm
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: "local-path"
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: litellm
  namespace: litellm
  labels:
    app: litellm
spec:
  selector:
    app: litellm
  ports:
    - protocol: TCP
      port: 4000
      targetPort: 4000
      name: http
```

- [ ] **Step 4: Create Ingress manifest**

```yaml
# provision/k8s/apps/litellm/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: litellm-ingress
  namespace: litellm
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "64m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
    - host: litellm.colt.chalko.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: litellm
                port:
                  number: 4000
```

- [ ] **Step 5: Create Kustomization for litellm**

```yaml
# provision/k8s/apps/litellm/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
  - ingress.yaml
```

---

### Task 3: GitOps Integration & Kustomize Validation

**Files:**

- Modify: `provision/k8s/kustomization.yaml`

- [ ] **Step 1: Add `apps/litellm` to root `provision/k8s/kustomization.yaml`**

```yaml
resources:
  - ...
  - apps/litellm
```

- [ ] **Step 2: Test Kustomize syntax build**

```bash
kubectl kustomize provision/k8s/apps/litellm
kubectl kustomize provision/k8s
```

---

### Task 4: GitOps Commit, Push & Rollout Monitoring

**Files:**

- Commit: `provision/k8s/apps/litellm/*` and `provision/k8s/kustomization.yaml`

**Interfaces:**

- Git repository: `colt/main`
- Flux Kustomization: `colt-cluster`

- [ ] **Step 1: Commit and push changes**

```bash
git add provision/k8s/apps/litellm provision/k8s/kustomization.yaml
git commit -m "feat(litellm): deploy LiteLLM gateway for nemotron-super-49b-v1.5"
git push colt main
```

- [ ] **Step 2: Reconcile Flux**

```bash
KUBECONFIG=/tmp/colt-kubeconfig flux reconcile kustomization colt-cluster --with-source
```

- [ ] **Step 3: Verify pod scheduled on CPU worker node**

```bash
KUBECONFIG=/tmp/colt-kubeconfig kubectl get pods -n litellm -o wide
# Confirm NODE is talos-64r-bft (10.82.0.13), NOT colt-gpu-01
```

---

### Task 5: End-to-End Gateway Verification

**Files:**

- None (verification commands)

**Interfaces:**

- In-cluster endpoint: `http://litellm.litellm.svc.cluster.local:4000/v1`

- [ ] **Step 1: Verify model listing via LiteLLM**

```bash
MASTER_KEY=$(vault kv get -field=master_key secret/colt/litellm/master_key)
KUBECONFIG=/tmp/colt-kubeconfig kubectl run test-litellm --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s http://litellm.litellm.svc.cluster.local:4000/v1/models \
  -H "Authorization: Bearer $MASTER_KEY"
```

- [ ] **Step 2: Verify chat completion query through gateway to backend Nemotron**

```bash
KUBECONFIG=/tmp/colt-kubeconfig kubectl run test-litellm-completion --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -X POST http://litellm.litellm.svc.cluster.local:4000/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nemotron-super-49b-v1.5",
    "messages": [{"role": "user", "content": "Hello from Camp Colt! Respond in one sentence."}],
    "max_tokens": 50
  }'
```
