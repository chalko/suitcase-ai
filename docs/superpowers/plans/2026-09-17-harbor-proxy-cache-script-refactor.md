# Harbor Proxy-Cache Script Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple the embedded 200-line shell script from the Kubernetes manifest `provision/k8s/harbor/setup-proxy-cache.yaml` into a dedicated, lintable POSIX shell script, utilizing Kustomize `configMapGenerator` to generate the ConfigMap declaratively.

**Architecture:** Extract the inlined `setup-proxy-cache.sh` logic into `provision/k8s/harbor/scripts/setup-proxy-cache.sh`. Update `provision/k8s/harbor/kustomization.yaml` to generate `ConfigMap/harbor-setup-proxy-cache-script` from this standalone script via `configMapGenerator`. Strip the embedded ConfigMap YAML out of `provision/k8s/harbor/setup-proxy-cache.yaml`, leaving only the declarative `batch/v1 Job` resource.

**Tech Stack:** Kubernetes (Batch/v1 Job, ConfigMap), Kustomize (v5+ `configMapGenerator`), Flux CD (kustomize-controller), POSIX Shell (`/bin/sh`, curl, jq-less parsing).

**Spec:** User request: "Move the script out of provision/k8s/harbor/setup-proxy-cache.yaml That is an antipatern. Make a plan to fix this."

## Global Constraints

- **Zero-Secret / Least Privilege:** Never commit or log plaintext passwords or private keys. Harbor admin password and NGC API key must continue to be projected from Kubernetes secrets (`harbor-secret` and `ngc-secret`).
- **Zero Foreign Rig Mutation:** All operations strictly target Camp Colt (`10.82.0.0/16`, control plane `10.82.0.10:6443`). Always verify context using `scripts/verify-colt-context.sh`.
- **Mandatory Kubeconfig Pinning:** Always specify `KUBECONFIG="$REPO_ROOT/colt-kubeconfig"`.
- **Public Egress Restriction:** NEVER push to `public` branch without express user permission in chat. All commits push strictly to `colt feat/version-upgrades:main` or `colt main`.

---

## File Structure & Proposed Changes

- **Create:** `provision/k8s/harbor/scripts/setup-proxy-cache.sh`
  - Clean, standalone, executable shell script containing the upstream registry and proxy-cache project provisioning logic.
- **Modify:** `provision/k8s/harbor/setup-proxy-cache.yaml`
  - Remove the lines 1–215 (embedded `ConfigMap` and raw script string).
  - Retain strictly the declarative `batch/v1 Job` (`harbor-setup-proxy-cache`).
- **Modify:** `provision/k8s/harbor/kustomization.yaml`
  - Add `configMapGenerator` entry for `harbor-setup-proxy-cache-script` pointing to `scripts/setup-proxy-cache.sh`.
  - Set `generatorOptions.disableNameSuffixHash: true` to ensure zero-churn ConfigMap naming for the Job volume mount.
- **Test / Verify:** `tests/test_harbor_kustomize.sh` (or verification commands using `kubectl kustomize`, `sh -n`, and cluster dry-run).

---

## Tasks

### Task 1: Extract Shell Script to Standalone File and Add Syntax Verification

**Files:**

- Create: `provision/k8s/harbor/scripts/setup-proxy-cache.sh`

**Interfaces:**

- Consumes: Environment variables `HARBOR_URL`, `HARBOR_ADMIN_PASSWORD`, `NGC_API_KEY`.
- Produces: Executable `/scripts/setup-proxy-cache.sh` mounted inside the curl container.

- [ ] **Step 1: Create the scripts directory and standalone script file**

Extract the shell script from `provision/k8s/harbor/setup-proxy-cache.yaml` lines 11–214 into `provision/k8s/harbor/scripts/setup-proxy-cache.sh`:

```bash
mkdir -p provision/k8s/harbor/scripts
cat << 'EOF' > provision/k8s/harbor/scripts/setup-proxy-cache.sh
#!/bin/sh
set -eu

HARBOR_URL="${HARBOR_URL:-http://harbor-core.harbor.svc.cluster.local}"

echo "================================================================="
echo "=== Camp Colt Harbor Declarative Proxy-Cache Setup Runner     ==="
echo "================================================================="

if [ -z "${HARBOR_ADMIN_PASSWORD:-}" ]; then
  echo "[-] ERROR: HARBOR_ADMIN_PASSWORD environment variable is unset."
  exit 1
fi

if [ -z "${NGC_API_KEY:-}" ]; then
  echo "[-] ERROR: NGC_API_KEY environment variable is unset."
  exit 1
fi

echo "[+] Waiting for Harbor API at ${HARBOR_URL}..."
MAX_RETRIES=30
RETRY_COUNT=0
while true; do
  HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -u "admin:${HARBOR_ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/systeminfo" || true)
  if [ "$HTTP_CODE" = "200" ]; then
    echo "[✓] Harbor API is ready and authenticated (HTTP 200)."
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    echo "[-] ERROR: Harbor API did not become ready after ${MAX_RETRIES} attempts (last HTTP code: ${HTTP_CODE})."
    exit 1
  fi
  echo "    Harbor API not ready (HTTP ${HTTP_CODE}), waiting 3s... (${RETRY_COUNT}/${MAX_RETRIES})"
  sleep 3
done

# Function: get_registry_id <registry_name>
get_registry_id() {
  REG_NAME="$1"
  RESP=$(curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/registries")
  echo "$RESP" | tr '{' '\n' | grep '"name":"'"${REG_NAME}"'"' | grep -o '"id":[0-9]*' | head -n1 | cut -d':' -f2 || true
}

# Function: ensure_registry <name> <type> <url> [auth_user] [auth_pass]
ensure_registry() {
  REG_NAME="$1"
  REG_TYPE="$2"
  REG_URL="$3"
  AUTH_USER="${4:-}"
  AUTH_PASS="${5:-}"

  echo "[*] Processing upstream registry: ${REG_NAME} (${REG_TYPE} -> ${REG_URL})..."
  REG_ID=$(get_registry_id "${REG_NAME}")

  if [ -n "${REG_ID}" ]; then
    echo "    Registry ${REG_NAME} already exists with ID ${REG_ID}."
    if [ -n "${AUTH_USER}" ]; then
      echo "    Updating credentials for ${REG_NAME} (ID: ${REG_ID})..."
      STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" -u "admin:${HARBOR_ADMIN_PASSWORD}" -X PUT \
        "${HARBOR_URL}/api/v2.0/registries/${REG_ID}" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "'"${REG_NAME}"'",
          "type": "'"${REG_TYPE}"'",
          "url": "'"${REG_URL}"'",
          "insecure": false,
          "credential": {
            "type": "basic",
            "access_key": "'"${AUTH_USER}"'",
            "access_secret": "'"${AUTH_PASS}"'"
          }
        }')
      if [ "$STATUS" = "200" ]; then
        echo "    [✓] Credentials successfully updated for ${REG_NAME}."
      else
        echo "    [-] WARNING: Failed to update credentials for ${REG_NAME} (HTTP ${STATUS})."
      fi
    fi
  else
    echo "    Creating registry ${REG_NAME}..."
    if [ -n "${AUTH_USER}" ]; then
      STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" -u "admin:${HARBOR_ADMIN_PASSWORD}" -X POST \
        "${HARBOR_URL}/api/v2.0/registries" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "'"${REG_NAME}"'",
          "type": "'"${REG_TYPE}"'",
          "url": "'"${REG_URL}"'",
          "insecure": false,
          "credential": {
            "type": "basic",
            "access_key": "'"${AUTH_USER}"'",
            "access_secret": "'"${AUTH_PASS}"'"
          }
        }')
    else
      STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" -u "admin:${HARBOR_ADMIN_PASSWORD}" -X POST \
        "${HARBOR_URL}/api/v2.0/registries" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "'"${REG_NAME}"'",
          "type": "'"${REG_TYPE}"'",
          "url": "'"${REG_URL}"'",
          "insecure": false
        }')
    fi

    if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ]; then
      REG_ID=$(get_registry_id "${REG_NAME}")
      echo "    [✓] Registry ${REG_NAME} configured with ID ${REG_ID}."
    else
      echo "[-] ERROR: Failed to create registry ${REG_NAME} (HTTP ${STATUS})."
      exit 1
    fi
  fi
}

# Function: ensure_proxy_project <project_name> <registry_name>
ensure_proxy_project() {
  PROJ_NAME="$1"
  REG_NAME="$2"

  echo "[*] Processing proxy project: ${PROJ_NAME} (upstream: ${REG_NAME})..."
  REG_ID=$(get_registry_id "${REG_NAME}")
  if [ -z "${REG_ID}" ]; then
    echo "[-] ERROR: Cannot configure project ${PROJ_NAME}: registry ${REG_NAME} ID not found."
    exit 1
  fi

  PROJ_RESP=$(curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/projects")
  PROJ_FOUND=$(echo "$PROJ_RESP" | tr '{' '\n' | grep '"name":"'"${PROJ_NAME}"'"' || true)

  if [ -n "${PROJ_FOUND}" ]; then
    echo "    Project ${PROJ_NAME} already exists."
  else
    echo "    Creating proxy cache project ${PROJ_NAME} (registry ID ${REG_ID})..."
    STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" -u "admin:${HARBOR_ADMIN_PASSWORD}" -X POST \
      "${HARBOR_URL}/api/v2.0/projects" \
      -H "Content-Type: application/json" \
      -d '{
        "project_name": "'"${PROJ_NAME}"'",
        "metadata": {
          "public": "true"
        },
        "registry_id": '"${REG_ID}"',
        "storage_limit": -1
      }')
    if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ]; then
      echo "    [✓] Proxy cache project ${PROJ_NAME} created successfully."
    else
      echo "[-] ERROR: Failed to create proxy project ${PROJ_NAME} (HTTP ${STATUS})."
      exit 1
    fi
  fi
}

echo "=== Step 1: Upstream Registries ==="
ensure_registry "dockerhub-upstream" "docker-hub" "https://hub.docker.com"
ensure_registry "ghcr-upstream" "github-ghcr" "https://ghcr.io"
ensure_registry "nvcr-upstream" "docker-registry" "https://nvcr.io" '$oauthtoken' "${NGC_API_KEY}"
ensure_registry "quay-upstream" "quay" "https://quay.io"
ensure_registry "k8s-upstream" "docker-registry" "https://registry.k8s.io"

echo "=== Step 2: Proxy Cache Projects ==="
ensure_proxy_project "docker-proxy" "dockerhub-upstream"
ensure_proxy_project "ghcr-proxy" "ghcr-upstream"
ensure_proxy_project "nvcr-proxy" "nvcr-upstream"
ensure_proxy_project "quay-proxy" "quay-upstream"
ensure_proxy_project "k8s-proxy" "k8s-upstream"

echo "=== Step 3: Verification of Upstreams & Proxy Cache Projects ==="
ALL_SUCCESS=true

REG_CHECK=$(curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/registries")
for reg in dockerhub-upstream ghcr-upstream nvcr-upstream quay-upstream k8s-upstream; do
  RID=$(echo "$REG_CHECK" | tr '{' '\n' | grep '"name":"'"${reg}"'"' | grep -o '"id":[0-9]*' | head -n1 | cut -d':' -f2 || true)
  if [ -n "$RID" ]; then
    echo "[✓] Registry verified: ${reg} (ID: ${RID})"
  else
    echo "[-] Registry verification FAILED: ${reg}"
    ALL_SUCCESS=false
  fi
done

PROJ_CHECK=$(curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/projects")
for proj in docker-proxy ghcr-proxy nvcr-proxy quay-proxy k8s-proxy; do
  PFOUND=$(echo "$PROJ_CHECK" | tr '{' '\n' | grep '"name":"'"${proj}"'"' || true)
  if [ -n "$PFOUND" ]; then
    echo "[✓] Proxy Project verified: ${proj}"
  else
    echo "[-] Proxy Project verification FAILED: ${proj}"
    ALL_SUCCESS=false
  fi
done

if [ "$ALL_SUCCESS" = "true" ]; then
  echo "================================================================="
  echo "=== All 5 Harbor proxy-cache configurations verified!         ==="
  echo "================================================================="
else
  echo "[-] ERROR: One or more verifications failed."
  exit 1
fi
EOF
chmod +x provision/k8s/harbor/scripts/setup-proxy-cache.sh
```

- [ ] **Step 2: Run shell syntax validation**

Run: `sh -n provision/k8s/harbor/scripts/setup-proxy-cache.sh`
Expected: Exits with return code 0 (no syntax errors).

- [ ] **Step 3: Commit the new standalone script**

```bash
git add provision/k8s/harbor/scripts/setup-proxy-cache.sh
git commit -m "feat(harbor): extract setup-proxy-cache script to standalone shell script"
```

---

### Task 2: Configure Kustomize configMapGenerator and Clean Job Manifest

**Files:**

- Modify: `provision/k8s/harbor/kustomization.yaml`
- Modify: `provision/k8s/harbor/setup-proxy-cache.yaml`

**Interfaces:**

- Consumes: `provision/k8s/harbor/scripts/setup-proxy-cache.sh`.
- Produces: `ConfigMap/harbor-setup-proxy-cache-script` generated during Kustomize build, consumed by `Job/harbor-setup-proxy-cache`.

- [ ] **Step 1: Update `provision/k8s/harbor/kustomization.yaml`**

Configure `configMapGenerator` to assemble the ConfigMap from the script file:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: harbor

resources:
  - release.yaml
  - backup.yaml
  - secrets.yaml
  - setup-proxy-cache.yaml

configMapGenerator:
  - name: harbor-setup-proxy-cache-script
    files:
      - setup-proxy-cache.sh=scripts/setup-proxy-cache.sh

generatorOptions:
  disableNameSuffixHash: true
```

- [ ] **Step 2: Strip the embedded ConfigMap from `provision/k8s/harbor/setup-proxy-cache.yaml`**

Replace `provision/k8s/harbor/setup-proxy-cache.yaml` with only the declarative `Job`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: harbor-setup-proxy-cache
  namespace: harbor
  labels:
    app.kubernetes.io/name: harbor-setup-proxy-cache
    app.kubernetes.io/part-of: camp-colt
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/name: harbor-setup-proxy-cache
        app.kubernetes.io/part-of: camp-colt
    spec:
      restartPolicy: OnFailure
      nodeSelector:
        kubernetes.io/arch: amd64
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      volumes:
        - name: script-vol
          configMap:
            name: harbor-setup-proxy-cache-script
            defaultMode: 0755
      containers:
        - name: setup-proxy-cache
          image: curlimages/curl:latest
          command:
            - /bin/sh
            - /scripts/setup-proxy-cache.sh
          env:
            - name: HARBOR_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: harbor-secret
                  key: HARBOR_ADMIN_PASSWORD
            - name: NGC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ngc-secret
                  key: NGC_API_KEY
          volumeMounts:
            - name: script-vol
              mountPath: /scripts
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
```

- [ ] **Step 3: Verify Kustomize build and dry-run apply**

Run:

```bash
kubectl kustomize provision/k8s/harbor | grep -A 10 "kind: ConfigMap"
KUBECONFIG="$PWD/colt-kubeconfig" ./scripts/verify-colt-context.sh
KUBECONFIG="$PWD/colt-kubeconfig" kubectl apply -k provision/k8s/harbor --dry-run=client
```

Expected: ConfigMap is cleanly rendered by Kustomize; client dry-run passes with zero errors.

- [ ] **Step 4: Commit Kustomize and Job changes**

```bash
git add provision/k8s/harbor/kustomization.yaml provision/k8s/harbor/setup-proxy-cache.yaml
git commit -m "refactor(harbor): generate setup-proxy-cache configmap via kustomize configMapGenerator"
```

---

### Task 3: Deploy via GitOps & Live Verification

**Files:**

- Test/Execution: Camp Colt Kubernetes Cluster

- [ ] **Step 1: Push changes to GitOps source branch**

```bash
git push colt main
```

_(Never push to public)_

- [ ] **Step 2: Reconcile Flux CD**

```bash
KUBECONFIG="$PWD/colt-kubeconfig" flux reconcile kustomization camp-colt-infra --with-source
```

Expected: `Applied revision: <commit-hash>`, Status: Ready (`True`).

- [ ] **Step 3: Verify in-cluster ConfigMap and Job status**

```bash
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get configmap harbor-setup-proxy-cache-script -n harbor -o jsonpath='{.data.setup-proxy-cache\.sh}' | head -n 15
KUBECONFIG="$PWD/colt-kubeconfig" kubectl get pods -n harbor -l app.kubernetes.io/name=harbor-setup-proxy-cache
```

Expected: ConfigMap contains the complete script; Job/pods show Completed (`0/1 Completed`).

- [ ] **Step 4: Verify Harbor proxy cache projects remain active**

```bash
curl -s -k -u "admin:$(vault kv get -mount=secret -field=admin_password colt/harbor)" https://harbor.colt.chalko.com/api/v2.0/projects | jq -r '.[].name'
```

Expected: All 5 proxy projects (`docker-proxy`, `ghcr-proxy`, `nvcr-proxy`, `quay-proxy`, `k8s-proxy`) and project `fog` are confirmed active.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-17-harbor-proxy-cache-script-refactor.md`. Two execution options:

1. **Subagent-Driven (recommended)** - Dispatch a dedicated subagent to execute the refactor and verify the GitOps reconciliation.
2. **Inline Execution** - Execute tasks directly in this session with immediate checkpoints.
