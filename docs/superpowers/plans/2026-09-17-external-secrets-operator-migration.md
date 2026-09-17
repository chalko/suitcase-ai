# External Secrets Operator (ESO) & Progressive Service Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the External Secrets Operator (ESO) to Camp Colt via GitOps (Flux CD), establish a `ClusterSecretStore` backed by HashiCorp Vault (`colt-vault` @ `10.82.0.5:8200`), and progressively migrate workloads (Harbor, Grafana, LiteLLM, Gitea) to declarative `ExternalSecret` synchronization with end-to-end testing at each step.

**Architecture:** A centralized External Secrets Operator deployed in namespace `external-secrets` via Flux CD `HelmRelease`. ESO authenticates to `colt-vault` via the Kubernetes Auth method using a dedicated ServiceAccount and Vault role `external-secrets` with read access to `secret/data/colt/*`. A cluster-wide `ClusterSecretStore` named `colt-vault` enables any namespace to declare native `ExternalSecret` manifests, eliminating imperative host scripts and closing the GitOps secret gap across Camp Colt.

**Tech Stack:** External Secrets Operator v0.10.3+, Flux CD v2.x, HashiCorp Vault 1.18+, Talos Linux v1.14 / K8s v1.36.4, Terraform, Dolt/Beads (`bd`).

**Spec:** [`plans/2026-09-17-external-secrets-operator-migration.md`](file:///home/luna-mayor-agent/luna/rigs/suitcase-ai/docs/superpowers/plans/2026-09-17-external-secrets-operator-migration.md) (implements `sa-rxx`, `sa-2pq`, and prerequisites for `sa-zdt`).

## Global Constraints

- **Zero-Secret / Least Privilege:** Never print or leak raw private keys, tokens, or credentials in stdout, logs, or git. Never commit plain secret values to git.
- **GitOps for Kubernetes:** All Kubernetes resources must reside in `provision/k8s/` and reconcile cleanly via Flux CD (`flux reconcile kustomization camp-colt-infra --with-source`).
- **Strict Context Pinning:** Every `kubectl` or `flux` invocation MUST explicitly set `KUBECONFIG="$REPO_ROOT/colt-kubeconfig"`.
- **Zero Foreign Rig Mutation:** All operations are strictly pinned to Camp Colt (`10.82.0.0/16`, control plane `10.82.0.10:6443`). Never target Fog or other contexts.
- **Node Pinning:** Operator pods and infrastructure workloads must target AMD64 worker node `talos-64r-bft` (`kubernetes.io/arch: amd64`), preserving the Grace Blackwell GB10 GPU node (`colt-gpu-01`) for inference.
- **Mandatory Live Verification:** Test and verify service health, secret generation, and live inference at each migration checkpoint before proceeding.

---

### Task 1: Configure Vault Kubernetes Auth Role & Policy for ESO

**Files:**

- Modify: `provision/colt_vault_policies.tf`

**Interfaces:**

- Consumes: HashiCorp Vault at `https://10.82.0.5:8200`
- Produces: Vault role `external-secrets` bound to ServiceAccount `external-secrets` in namespace `external-secrets` with policy `colt-workload`

- [ ] **Step 1: Declare Vault Kubernetes Auth Role in Terraform**

Add the `vault_kubernetes_auth_backend_role` resource to `provision/colt_vault_policies.tf`:

```hcl
# ------------------------------------------------------------------------------
# 5. Kubernetes Auth Backend Role for External Secrets Operator (ESO)
# ------------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = "kubernetes"
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = ["colt-workload"]
  token_ttl                        = 3600
}
```

- [ ] **Step 2: Apply Terraform configuration to colt-vault**

Run:

```bash
terraform -chdir=provision plan -target=vault_kubernetes_auth_backend_role.external_secrets
terraform -chdir=provision apply -target=vault_kubernetes_auth_backend_role.external_secrets -auto-approve
```

Expected: `vault_kubernetes_auth_backend_role.external_secrets` created successfully.

- [ ] **Step 3: Verify role in Vault**

Run:

```bash
bash -c '
export VAULT_ADDR="https://10.82.0.5:8200"
export VAULT_SKIP_VERIFY=true
export VAULT_CLIENT_CERT="$PWD/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt"
export VAULT_CLIENT_KEY="$PWD/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key"
vault login -method=cert >/dev/null
vault read auth/kubernetes/role/external-secrets
'
```

Expected: Role displayed with `bound_service_account_names = [external-secrets]`, `bound_service_account_namespaces = [external-secrets]`, and `token_policies = [colt-workload]`.

- [ ] **Step 4: Commit changes**

```bash
git add provision/colt_vault_policies.tf
git commit -m "feat(vault): add external-secrets role to kubernetes auth backend"
```

---

### Task 2: Author Declarative External Secrets Operator GitOps Manifests

**Files:**

- Create: `provision/k8s/external-secrets/namespace.yaml`
- Create: `provision/k8s/external-secrets/release.yaml`
- Create: `provision/k8s/external-secrets/vault-ca-configmap.yaml`
- Create: `provision/k8s/external-secrets/cluster-secret-store.yaml`
- Create: `provision/k8s/external-secrets/kustomization.yaml`
- Modify: `provision/k8s/kustomization.yaml`

**Interfaces:**

- Consumes: `https://charts.external-secrets.io` Helm chart repository
- Produces: `external-secrets` namespace, HelmRelease, and `ClusterSecretStore` `colt-vault`

- [ ] **Step 1: Extract Vault TLS CA public certificate**

Fetch the public self-signed CA certificate of `colt-vault` (`10.82.0.5:8200`) and write `provision/k8s/external-secrets/vault-ca-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: colt-vault-ca
  namespace: external-secrets
data:
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
```

- [ ] **Step 2: Create namespace and HelmRelease manifests**

Create `provision/k8s/external-secrets/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
```

Create `provision/k8s/external-secrets/release.yaml`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: external-secrets
  namespace: external-secrets
spec:
  interval: 1h
  url: https://charts.external-secrets.io
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: external-secrets
  namespace: external-secrets
spec:
  interval: 1h
  chart:
    spec:
      chart: external-secrets
      version: "0.10.3"
      sourceRef:
        kind: HelmRepository
        name: external-secrets
        namespace: external-secrets
  install:
    crds: CreateReplace
    remediation:
      retries: 3
  upgrade:
    crds: CreateReplace
    remediation:
      retries: 3
  values:
    installCRDs: true
    nodeSelector:
      kubernetes.io/arch: amd64
    webhook:
      nodeSelector:
        kubernetes.io/arch: amd64
    certController:
      nodeSelector:
        kubernetes.io/arch: amd64
```

- [ ] **Step 3: Create ClusterSecretStore definition**

Create `provision/k8s/external-secrets/cluster-secret-store.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: colt-vault
spec:
  provider:
    vault:
      server: "https://10.82.0.5:8200"
      path: "secret"
      version: "v2"
      caProvider:
        type: ConfigMap
        name: colt-vault-ca
        namespace: external-secrets
        key: ca.crt
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
```

- [ ] **Step 4: Create kustomization and register in root provision/k8s/kustomization.yaml**

Create `provision/k8s/external-secrets/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - vault-ca-configmap.yaml
  - release.yaml
  - cluster-secret-store.yaml
```

Add `- external-secrets` to `provision/k8s/kustomization.yaml`.

- [ ] **Step 5: Pre-flight syntax and dry-run verification**

Run:

```bash
scripts/verify-colt-context.sh
kubectl kustomize provision/k8s/external-secrets | KUBECONFIG="$PWD/colt-kubeconfig" kubectl apply --dry-run=client -f -
```

Expected: All resources validate with `configured (dry run)`.

- [ ] **Step 6: Commit and push GitOps manifests**

```bash
git add provision/k8s/external-secrets provision/k8s/kustomization.yaml
git commit -m "feat(k8s): add external-secrets operator and colt-vault ClusterSecretStore"
git push colt main
```

- [ ] **Step 7: Reconcile Flux CD and verify ESO deployment**

Run:

```bash
KUBECONFIG="$PWD/colt-kubeconfig" flux reconcile kustomization camp-colt-infra --with-source
KUBECONFIG="$PWD/colt-kubeconfig" kubectl wait --namespace external-secrets --for=condition=ready pod --selector=app.kubernetes.io/name=external-secrets --timeout=120s
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get clustersecretstore colt-vault
```

Expected: Pods in `external-secrets` report `1/1 Running`, `ClusterSecretStore` `colt-vault` reports `Ready: Valid`.

---

### Task 3: Migrate Harbor Secrets & Declarative Proxy-Cache Setup (Service 1)

**Files:**

- Create: `provision/k8s/harbor/secrets.yaml`
- Create: `provision/k8s/harbor/setup-proxy-cache.yaml`
- Modify: `provision/k8s/harbor/kustomization.yaml`
- Modify: `provision/k8s/harbor/release.yaml`

**Interfaces:**

- Consumes: Vault keys `secret/data/colt/harbor` and `secret/data/colt/infra/ngc`
- Produces: Declarative `ExternalSecret` `harbor-secret` and `ngc-secret`, plus automated proxy cache setup Job

- [ ] **Step 1: Declare ExternalSecrets in Harbor**

Create `provision/k8s/harbor/secrets.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-vault-secret
  namespace: harbor
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: colt-vault
    kind: ClusterSecretStore
  target:
    name: harbor-secret
    creationPolicy: Owner
  data:
    - secretKey: HARBOR_ADMIN_PASSWORD
      remoteRef:
        key: secret/data/colt/harbor
        property: admin_password
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: secret/data/colt/harbor
        property: database_password
    - secretKey: POSTGRESQL_PASSWORD
      remoteRef:
        key: secret/data/colt/harbor
        property: database_password
    - secretKey: POSTGRESQL_POSTGRES_PASSWORD
      remoteRef:
        key: secret/data/colt/harbor
        property: database_password
    - secretKey: SECRET_KEY
      remoteRef:
        key: secret/data/colt/harbor
        property: secret_key
    - secretKey: CORE_SECRET
      remoteRef:
        key: secret/data/colt/harbor
        property: core_secret
    - secretKey: JOBSERVICE_SECRET
      remoteRef:
        key: secret/data/colt/harbor
        property: jobservice_secret
    - secretKey: REGISTRY_HTTP_SECRET
      remoteRef:
        key: secret/data/colt/harbor
        property: registry_http_secret
    - secretKey: REGISTRY_SECRET
      remoteRef:
        key: secret/data/colt/harbor
        property: core_secret
    - secretKey: private_key.pem
      remoteRef:
        key: secret/data/colt/harbor
        property: token_private_key
    - secretKey: root.crt
      remoteRef:
        key: secret/data/colt/harbor
        property: token_public_cert
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ngc-secret
  namespace: harbor
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: colt-vault
    kind: ClusterSecretStore
  target:
    name: ngc-secret
    creationPolicy: Owner
  data:
    - secretKey: NGC_API_KEY
      remoteRef:
        key: secret/data/colt/infra/ngc
        property: api_key
```

- [ ] **Step 2: Create Declarative Proxy-Cache Setup Job in Harbor**

Create `provision/k8s/harbor/setup-proxy-cache.yaml` with a ConfigMap script and Job running curl against Harbor API to idempotently configure all 5 upstreams and proxy projects (`docker-proxy`, `ghcr-proxy`, `nvcr-proxy`, `quay-proxy`, `k8s-proxy`). Mounts `HARBOR_ADMIN_PASSWORD` from `harbor-secret` and `NGC_API_KEY` from `ngc-secret`.

- [ ] **Step 3: Update Harbor Kustomization & Release**

Add `secrets.yaml` and `setup-proxy-cache.yaml` to `provision/k8s/harbor/kustomization.yaml`.

- [ ] **Step 4: Commit, reconcile Flux, and verify Harbor secret sync**

Run:

```bash
git add provision/k8s/harbor/
git commit -m "feat(harbor): migrate harbor secrets to ExternalSecrets and add declarative proxy setup job"
git push colt main
KUBECONFIG="$PWD/colt-kubeconfig" flux reconcile kustomization camp-colt-infra --with-source
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get externalsecrets,secrets -n harbor
```

Expected: `harbor-vault-secret` and `ngc-secret` report `SecretSynced: True`, setup Job completes successfully (`1/1 Completed`), and all 5 proxy cache projects exist in Harbor.

---

### Task 4: Migrate Grafana Secrets to Vault & ESO (Service 2 — Closes `sa-2pq`)

**Files:**

- Create: `provision/k8s/apps/monitoring/secrets.yaml`
- Modify: `provision/k8s/apps/monitoring/release.yaml`
- Modify: `provision/k8s/apps/monitoring/kustomization.yaml`

**Interfaces:**

- Consumes: Vault key `secret/data/colt/monitoring/grafana`
- Produces: Declarative `ExternalSecret` `grafana-admin-secret` in `monitoring` namespace

- [ ] **Step 1: Ensure Grafana Admin Credentials in Vault**

Check/store `admin_user` and `admin_password` in Vault `secret/colt/monitoring/grafana`:

```bash
bash -c '
export VAULT_ADDR="https://10.82.0.5:8200"
export VAULT_SKIP_VERIFY=true
export VAULT_CLIENT_CERT="$PWD/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt"
export VAULT_CLIENT_KEY="$PWD/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key"
vault login -method=cert >/dev/null
if ! vault kv get secret/colt/monitoring/grafana >/dev/null 2>&1; then
  PASS="$(openssl rand -base64 18 | tr -dc "a-zA-Z0-9" | head -c 16)"
  vault kv put secret/colt/monitoring/grafana admin_user="admin" admin_password="$PASS"
fi
'
```

- [ ] **Step 2: Create ExternalSecret manifest for Grafana**

Create `provision/k8s/apps/monitoring/secrets.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: grafana-admin-secret
  namespace: monitoring
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: colt-vault
    kind: ClusterSecretStore
  target:
    name: grafana-admin-secret
    creationPolicy: Owner
  data:
    - secretKey: admin-user
      remoteRef:
        key: secret/data/colt/monitoring/grafana
        property: admin_user
    - secretKey: admin-password
      remoteRef:
        key: secret/data/colt/monitoring/grafana
        property: admin_password
```

- [ ] **Step 3: Update kube-prometheus-stack HelmRelease values**

In `provision/k8s/apps/monitoring/release.yaml`, configure Grafana to use `existingSecret: grafana-admin-secret`:

```yaml
grafana:
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
```

- [ ] **Step 4: Commit, reconcile Flux, and verify Grafana**

```bash
git add provision/k8s/apps/monitoring/
git commit -m "feat(monitoring): migrate grafana admin secrets to ExternalSecret (closes sa-2pq)"
git push colt main
KUBECONFIG="$PWD/colt-kubeconfig" flux reconcile kustomization camp-colt-infra --with-source
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get externalsecrets,secrets -n monitoring
```

Expected: `grafana-admin-secret` synced, Grafana pod healthy, bead `sa-2pq` closed.

---

### Task 5: Migrate LiteLLM Secrets to Vault & ESO (Service 3)

**Files:**

- Create: `provision/k8s/apps/litellm/secrets.yaml`
- Modify: `provision/k8s/apps/litellm/kustomization.yaml`
- Modify: `provision/k8s/apps/litellm/deployment.yaml`

**Interfaces:**

- Consumes: Vault key `secret/data/colt/litellm`
- Produces: Declarative `ExternalSecret` `litellm-secret` in `litellm` namespace

- [ ] **Step 1: Check existing LiteLLM secrets in Vault**

Inspect `secret/colt/litellm` in Vault to ensure keys (`master_key`, `salt_key`, database info) match workload needs.

- [ ] **Step 2: Create ExternalSecret manifest for LiteLLM**

Create `provision/k8s/apps/litellm/secrets.yaml` targeting `colt-vault` ClusterSecretStore and generating `litellm-secret`.

- [ ] **Step 3: Commit, reconcile Flux, and verify LiteLLM + Inference**

```bash
git add provision/k8s/apps/litellm/
git commit -m "feat(litellm): migrate litellm credentials to ExternalSecret"
git push colt main
KUBECONFIG="$PWD/colt-kubeconfig" flux reconcile kustomization camp-colt-infra --with-source
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get externalsecrets,secrets -n litellm
```

- [ ] **Step 4: Run Live Inference Test**

Dispatch test inference request to LiteLLM endpoint:

```bash
curl -s http://10.82.50.10/v1/models | jq .
```

Expected: HTTP 200 with available models list.

---

### Task 6: Migrate Gitea Runner Token to Vault & ESO (Service 4)

**Files:**

- Create: `provision/k8s/gitea/runner-secret.yaml`
- Modify: `provision/k8s/gitea/kustomization.yaml`

**Interfaces:**

- Consumes: Vault key `secret/data/colt/gitea_runner`
- Produces: Declarative `ExternalSecret` `gitea-runner-token` in `gitea` namespace

- [ ] **Step 1: Create ExternalSecret for Gitea Runner**

Create `provision/k8s/gitea/runner-secret.yaml` generating `gitea-runner-token` from `secret/data/colt/gitea_runner`.

- [ ] **Step 2: Commit, reconcile Flux, and verify Gitea Runner**

```bash
git add provision/k8s/gitea/
git commit -m "feat(gitea): migrate gitea runner token to ExternalSecret"
git push colt main
KUBECONFIG="$PWD/colt-kubeconfig" flux reconcile kustomization camp-colt-infra --with-source
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get externalsecrets -n gitea
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get pods -n gitea -l app.kubernetes.io/name=gitea-runner
```

Expected: `gitea-runner-token` synced, runner pod running and registered.

---

### Task 7: Convoy & Sub-Bead Tracking (`bd`)

**Interfaces:**

- Updates beads database for `sa-rxx`, `sa-2pq`, and sub-tasks.

- [ ] **Step 1: Create Sub-Beads under sa-rxx**

Create sub-beads using `bd create --parent sa-rxx`:

- Deploy External Secrets Operator HelmRelease & ClusterSecretStore
- Migrate Harbor Secrets & Setup Declarative Proxy-Cache Job
- Migrate Grafana Administrative Secrets (`sa-2pq`)
- Migrate LiteLLM Secrets & Verify Live Inference
- Migrate Gitea Runner Token

- [ ] **Step 2: Progressively close sub-beads as tasks complete**

Close child beads and mark `sa-rxx` and `sa-2pq` completed once verified.
