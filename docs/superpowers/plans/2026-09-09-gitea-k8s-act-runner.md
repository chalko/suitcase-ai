# Gitea Actions K8s Runner (`act_runner`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy an automated, in-cluster Gitea Actions runner (`act_runner`) on the Talos Linux AMD64 worker (`talos-64r-bft`) using strictly pinned container images and Vault-backed secrets management, allowing declarative execution of CI/CD workflows and automated push mirroring to GitHub without manual workarounds.

**Architecture:** A Kubernetes Deployment in namespace `gitea` consisting of two containers: `act_runner` (pinned to `gitea/act_runner:0.2.11`) and Docker-in-Docker `dind` (pinned to `docker:27.5.1-dind`) communicating over localhost socket/TCP, registered to `https://gitea.colt.chalko.com` via a registration token sourced directly from HashiCorp Vault (`secret/colt/gitea_runner`).

**Tech Stack:** Kubernetes (Talos Linux 1.14.0 / K8s 1.36.4), HashiCorp Vault (`10.82.0.5:8200`), Gitea 1.22.6, `gitea/act_runner:0.2.11`, `docker:27.5.1-dind`, Flux CD GitOps.

**Spec:** [docs/PUBLIC_RELEASE_RUNBOOK.md](../PUBLIC_RELEASE_RUNBOOK.md)

## Global Constraints

- **Vault as Master Secret Source:** All secrets (Gitea admin token, GitHub PAT, Runner registration token) MUST be stored in and retrieved from HashiCorp Vault (`secret/colt/...`). Never store plaintext secrets in git or scripts.
- **Strictly Pinned Image Tags:** Never use `:latest`. All images MUST specify exact immutable tags (`gitea/act_runner:0.2.11`, `docker:27.5.1-dind`, `catthehacker/ubuntu:act-22.04`).
- **Zero-Secret Compliance:** Never print, log, or hardcode registration tokens or API keys in bash outputs or transcripts.
- **Node Pinning:** Runner workloads must target general worker `kubernetes.io/arch: amd64` (`talos-64r-bft`), avoiding the GPU node (`colt-gpu-01`).
- **GitOps Declarative Deployment:** All Kubernetes resources must be declared in `provision/k8s/gitea/` and reconciled via Flux CD.

---

### Task 1: Generate Registration Secret in Vault & Provision K8s Secret

**Files:**

- Create: `scripts/sync-gitea-runner-vault.sh`
- Target: Vault path `secret/colt/gitea_runner`
- Target: K8s Secret `gitea-runner-secret` in namespace `gitea`

**Interfaces:**

- Consumes: Vault path `secret/colt/gitea` (for Gitea admin token)
- Produces: Vault path `secret/colt/gitea_runner` and K8s secret `gitea-runner-secret`

- [ ] **Step 1: Retrieve registration token from Gitea API via Vault and store in Vault & K8s**
      Read admin token from Vault `secret/colt/gitea`, query `https://gitea.colt.chalko.com/api/v1/orgs/colt/actions/runners/registration-token`, store token in Vault `secret/colt/gitea_runner`, and apply Kubernetes Secret `gitea-runner-secret` in namespace `gitea` via dry-run stream without printing token.

- [ ] **Step 2: Verify secret creation in Vault & Kubernetes**
      Run: `vault kv get -format=json secret/colt/gitea_runner | jq -r '.data.data | keys'`
      Run: `kubectl --kubeconfig colt-kubeconfig get secret -n gitea gitea-runner-secret`
      Expected: `gitea-runner-secret   Opaque   1      ...`

---

### Task 2: Create Declarative Runner Manifests

**Files:**

- Create: `provision/k8s/gitea/runner-configmap.yaml`
- Create: `provision/k8s/gitea/runner.yaml`
- Modify: `provision/k8s/gitea/kustomization.yaml`

**Interfaces:**

- Consumes: `gitea-runner-secret`, `gitea-inline-config`
- Produces: `gitea-runner-config` ConfigMap, `gitea-runner` Deployment

- [ ] **Step 1: Author `runner-configmap.yaml`**
      Define runner configuration with pinned default container environment:

  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: gitea-runner-config
    namespace: gitea
  data:
    config.yaml: |
      runner:
        file: .runner
        capacity: 2
        timeout: 3h
        shutdown_timeout: 0s
        fetch_timeout: 5s
        fetch_interval: 2s
        labels:
          - "ubuntu-latest:docker://catthehacker/ubuntu:act-22.04"
          - "ubuntu-22.04:docker://catthehacker/ubuntu:act-22.04"
      cache:
        enabled: true
      container:
        network: "host"
        privileged: false
  ```

- [ ] **Step 2: Author `runner.yaml` Deployment with Pinned Images**
      Deploy `act_runner` and `dind` sidecar pinned to AMD64:

  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: gitea-runner
    namespace: gitea
    labels:
      app.kubernetes.io/name: gitea-runner
      app.kubernetes.io/part-of: colt-gitea
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: gitea-runner
    template:
      metadata:
        labels:
          app: gitea-runner
      spec:
        nodeSelector:
          kubernetes.io/arch: amd64
        volumes:
          - name: runner-config
            configMap:
              name: gitea-runner-config
          - name: runner-data
            emptyDir: {}
          - name: dind-storage
            emptyDir: {}
        containers:
          - name: dind
            image: docker:27.5.1-dind
            imagePullPolicy: IfNotPresent
            securityContext:
              privileged: true
            env:
              - name: DOCKER_TLS_CERTDIR
                value: ""
            volumeMounts:
              - name: dind-storage
                mountPath: /var/lib/docker
            resources:
              requests:
                cpu: "500m"
                memory: "512Mi"
              limits:
                cpu: "2"
                memory: "4Gi"
          - name: runner
            image: gitea/act_runner:0.2.11
            imagePullPolicy: IfNotPresent
            env:
              - name: GITEA_INSTANCE_URL
                value: "http://gitea.gitea.svc.cluster.local:3000"
              - name: GITEA_RUNNER_REGISTRATION_TOKEN
                valueFrom:
                  secretKeyRef:
                    name: gitea-runner-secret
                    key: token
              - name: GITEA_RUNNER_NAME
                value: "colt-k8s-runner-01"
              - name: DOCKER_HOST
                value: "tcp://localhost:2375"
              - name: CONFIG_FILE
                value: "/config/config.yaml"
            volumeMounts:
              - name: runner-config
                mountPath: /config
              - name: runner-data
                mountPath: /data
            resources:
              requests:
                cpu: "250m"
                memory: "256Mi"
              limits:
                cpu: "1"
                memory: "1Gi"
  ```

- [ ] **Step 3: Update `provision/k8s/gitea/kustomization.yaml`**
      Add `runner-configmap.yaml` and `runner.yaml` to resources list.

- [ ] **Step 4: Dry-run validate Kustomize output**
      Run: `kubectl kustomize provision/k8s/gitea`
      Expected: Clean YAML output containing both `gitea` and `gitea-runner` deployments.

---

### Task 3: Commit, GitOps Reconcile, & Verify Runner Registration

**Files:**

- Modify: `provision/k8s/gitea/` files

- [ ] **Step 1: Commit and push changes**
      Commit with: `"feat(gitea): deploy in-cluster act_runner on AMD64 with pinned image versions and Vault secrets"`
      Push to `colt/main`.

- [ ] **Step 2: Reconcile Flux CD**
      Run: `flux --kubeconfig colt-kubeconfig reconcile source git flux-system && flux --kubeconfig colt-kubeconfig reconcile kustomization camp-colt-infra --with-source`
      Expected: `✔ applied revision ...`

- [ ] **Step 3: Verify Pod Startup & Runner Logs**
      Run: `kubectl --kubeconfig colt-kubeconfig get pods -n gitea -l app=gitea-runner`
      Expected: `2/2 Running` (dind + runner).
      Inspect runner logs to confirm successful registration: `Registered successfully: colt-k8s-runner-01`.

- [ ] **Step 4: Verify Runner in Gitea API**
      Verify active runner status in Gitea without printing secrets.

---

### Task 4: End-to-End Automated Workflow Test

- [ ] **Step 1: Test GitHub Sync Workflow**
      Execute `./scripts/promote-to-public.sh`, and verify Gitea Actions executes on `colt-k8s-runner-01` without manual intervention.
- [ ] **Step 2: Confirm GitHub Egress**
      Verify the workflow succeeds and mirrors directly to GitHub `main`.
