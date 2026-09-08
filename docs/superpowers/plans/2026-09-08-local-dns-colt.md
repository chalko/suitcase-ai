# Camp Colt Local DNS Architecture & Lodge Network Hand-off Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish sovereign, local DNS resolution for Camp Colt (`*.colt.chalko.com`) by deploying an authoritative in-cluster CoreDNS instance with LoadBalancer VIP (`10.82.50.2:53`) and providing a conditional forwarding hand-off specification for the Lodge network administrator.

**Architecture:**

- **Camp Colt In-Cluster CoreDNS (`coredns-colt`):** Runs in namespace `dns` with LoadBalancer Service bound to VIP `10.82.50.2:53` (UDP/TCP). Authoritatively resolves `*.colt.chalko.com` to Ingress VIP `10.82.50.10`, maps static appliance infrastructure (PVE hypervisor, GPU accelerator, Vault), and forwards upstream recursive queries to the Lodge gateway (`10.82.0.1`).
- **Lodge Network Integration:** The Lodge upstream DNS server (Unifi Gateway, pfSense/OPNsense, Pi-hole, or dnsmasq) sets a **Conditional Forwarder / Domain Delegation** for `colt.chalko.com` to `10.82.50.2`.

**Tech Stack:** CoreDNS (`registry.k8s.io/coredns/coredns:v1.14.7`), Talos Linux v1.14.0, MetalLB, Ingress-NGINX, Flux GitOps.

**Spec:** Fog CoreDNS reference (`infrastructure/base/coredns-fog/coredns-fog.yaml`), Camp Colt network specification (`10.82.0.0/16`).

---

## 1. Executive Summary & Hand-off for Lodge Network Admin

> [!IMPORTANT] > **To: Lodge Network Administrator** > **From: Camp Colt Infrastructure (`colt-sysadmin`)** > **Subject: Local Domain Delegation for `colt.chalko.com`**

To keep Camp Colt homelab services (`gitea`, `litellm`, `vault`, etc.) private, low-latency, and decoupled from public Google Cloud DNS, Camp Colt is running an authoritative local DNS resolver at **`10.82.50.2:53`**.

We request that the Lodge DNS router/server add a **conditional forwarder** for the domain `colt.chalko.com`.

### DNS Delegation Parameters

| Field                          | Value                                      | Notes                                                   |
| :----------------------------- | :----------------------------------------- | :------------------------------------------------------ |
| **Delegated Domain**           | `colt.chalko.com`                          | Includes all subdomains (`*.colt.chalko.com`)           |
| **Authoritative Forwarder IP** | **`10.82.50.2`**                           | Colt DNS VIP (`dns01.colt.chalko.com` / `coredns-colt`) |
| **Port**                       | `53` (UDP/TCP)                             | Standard DNS                                            |
| **Fallback**                   | Refuse / Do not forward to public internet | Prevents private IP leakage                             |

### Ready-to-Apply Router / DNS Configurations

#### Option A: UniFi Dream Machine / UniFi OS (UDM-Pro / UCG)

Under **Settings -> Routing -> Static Routes & DNS / Content Filtering -> Local DNS**:

- **Domain:** `colt.chalko.com`
- **Forwarding DNS Server:** `10.82.50.2`

#### Option B: dnsmasq / Pi-hole / OpenWrt

Add to `/etc/dnsmasq.d/99-colt.conf`:

```text
server=/colt.chalko.com/10.82.50.2
```

#### Option C: pfSense / OPNsense (Unbound DNS Resolver)

Under **Services -> DNS Resolver -> Domain Overrides**:

- **Domain:** `colt.chalko.com`
- **IP Address:** `10.82.50.2`
- **TLS Queries:** Disabled

#### Option D: BIND / Named / CoreDNS

```text
zone "colt.chalko.com" {
    type forward;
    forward only;
    forwarders { 10.82.50.2; };
};
```

---

## 2. In-Cluster Camp Colt DNS Architecture (`coredns-colt`)

### Zone Map & Record Definitions

```text
+---------------------------------------------------------------------------------------------+
| Zone: colt.chalko.com                                                                       |
| Authoritative Nameserver: 10.82.50.2:53 (coredns-colt)                                      |
|                                                                                             |
| Static Infrastructure Records:                                                              |
|  • pve.colt.chalko.com           -> 10.82.0.2   (Proxmox VE Hypervisor)                     |
|  • hypervisor.colt.chalko.com    -> 10.82.0.2   (Proxmox VE Hypervisor Alias)               |
|  • colt-gpu-01.colt.chalko.com   -> 10.82.0.3   (ASUS Ascent GX10 / Grace Blackwell GB10)   |
|  • haze.colt.chalko.com          -> 10.82.0.3   (GPU Node Alias)                            |
|  • vault.colt.chalko.com         -> 10.82.0.5   (HashiCorp Vault Appliance)                 |
|  • k8s.colt.chalko.com           -> 10.82.0.10  (Talos Control Plane)                       |
|                                                                                             |
| Dynamic Ingress Wildcard Template:                                                          |
|  • *.colt.chalko.com             -> 10.82.50.10 (Ingress-NGINX VIP)                         |
|    - gitea.colt.chalko.com       -> 10.82.50.10                                             |
|    - litellm.colt.chalko.com     -> 10.82.50.10                                             |
|    - colt.chalko.com             -> 10.82.50.10                                             |
|                                                                                             |
| Upstream Recursion (for queries outside colt.chalko.com):                                   |
|  • .                             -> Forward to Lodge Gateway: 10.82.0.1 (or 1.1.1.1)        |
+---------------------------------------------------------------------------------------------+
```

---

## 3. Implementation Tasks

### Task 1: Create Declarative `coredns-colt` Manifests

**Files:**

- Create: `provision/k8s/apps/dns/namespace.yaml`
- Create: `provision/k8s/apps/dns/coredns-colt.yaml`
- Create: `provision/k8s/apps/dns/kustomization.yaml`
- Modify: `provision/k8s/kustomization.yaml`

**Interfaces:**

- Consumes: Worker host interface `10.82.0.13`
- Produces: Port `53` DNS service listening on `10.82.0.13`

- [ ] **Step 1: Create DNS namespace manifest**

```yaml
# provision/k8s/apps/dns/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: coredns-colt
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    app.kubernetes.io/part-of: colt-infrastructure
```

- [ ] **Step 2: Create Corefile ConfigMap and Deployment**

```yaml
# provision/k8s/apps/dns/coredns-colt.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-colt-config
  namespace: coredns-colt
data:
  Corefile: |
    # Static Appliance Infrastructure
    pve.colt.chalko.com:53 hypervisor.colt.chalko.com:53 {
        log
        errors
        hosts {
            10.82.0.2 pve.colt.chalko.com hypervisor.colt.chalko.com
        }
    }

    colt-gpu-01.colt.chalko.com:53 haze.colt.chalko.com:53 {
        log
        errors
        hosts {
            10.82.0.3 colt-gpu-01.colt.chalko.com haze.colt.chalko.com
        }
    }

    vault.colt.chalko.com:53 {
        log
        errors
        hosts {
            10.82.0.5 vault.colt.chalko.com
        }
    }

    k8s.colt.chalko.com:53 {
        log
        errors
        hosts {
            10.82.0.10 k8s.colt.chalko.com
        }
    }

    # Authoritative Ingress Wildcard for *.colt.chalko.com -> 10.82.0.13
    colt.chalko.com:53 {
        log
        errors
        health :8080
        template IN A colt.chalko.com {
            match .*\.colt\.chalko\.com
            answer "{{ .Name }} 60 IN A 10.82.0.13"
        }
        template IN AAAA colt.chalko.com {
            match .*\.colt\.chalko\.com
            rcode NOERROR
        }
    }

    # Upstream Recursion via Lodge Gateway & Root Servers
    .:53 {
        log
        errors
        forward . 10.82.0.1 1.1.1.1 8.8.8.8 {
            prefer_udp
            max_concurrent 2000
        }
        cache 300 {
            success 8192 300
            denial 2048 60
            prefetch 1 30s 10%
            serve_stale 24h
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns-colt
  namespace: coredns-colt
  labels:
    app: coredns-colt
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: coredns-colt
  template:
    metadata:
      labels:
        app: coredns-colt
    spec:
      nodeSelector:
        kubernetes.io/hostname: talos-64r-bft
      containers:
        - name: coredns
          image: registry.k8s.io/coredns/coredns:v1.12.0
          imagePullPolicy: IfNotPresent
          securityContext:
            capabilities:
              add:
                - NET_BIND_SERVICE
          args: ["-conf", "/etc/coredns/Corefile"]
          volumeMounts:
            - name: config-volume
              mountPath: /etc/coredns
              readOnly: true
          ports:
            - containerPort: 53
              hostPort: 53
              hostIP: 10.82.0.13
              name: dns-udp
              protocol: UDP
            - containerPort: 53
              hostPort: 53
              hostIP: 10.82.0.13
              name: dns-tcp
              protocol: TCP
            - containerPort: 8080
              name: health
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 128Mi
      volumes:
        - name: config-volume
          configMap:
            name: coredns-colt-config
```

- [ ] **Step 3: Create Kustomization files**

```yaml
# provision/k8s/apps/dns/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - coredns-colt.yaml
```

- [ ] **Step 4: Wire into root `provision/k8s/kustomization.yaml`**

```yaml
resources:
  - ...
  - apps/dns
```

---

### Task 2: GitOps Commit & Reconcile via Flux

**Files:**

- Commit: `provision/k8s/apps/dns/*` and `provision/k8s/kustomization.yaml`

- [ ] **Step 1: Commit and push changes**

```bash
git add provision/k8s/apps/dns provision/k8s/kustomization.yaml
git commit -m "feat(dns): deploy authoritative local CoreDNS on worker node for colt.chalko.com"
git push colt main
```

- [ ] **Step 2: Trigger Flux reconciliation**

```bash
KUBECONFIG=/tmp/colt-kubeconfig flux reconcile kustomization colt-cluster --with-source
```

- [ ] **Step 3: Verify pod is running on `10.82.0.13`**

```bash
KUBECONFIG=/tmp/colt-kubeconfig kubectl get pods -n coredns-colt -o wide
```

---

### Task 3: Local DNS Resolution Verification

**Files:**

- None (verification commands)

- [ ] **Step 1: Test resolution of Ingress wildcard hostnames**

```bash
dig @10.82.0.13 litellm.colt.chalko.com +short
# Expected: 10.82.0.13

dig @10.82.0.13 gitea.colt.chalko.com +short
# Expected: 10.82.0.13
```

- [ ] **Step 2: Test resolution of static appliance hosts**

```bash
dig @10.82.0.13 vault.colt.chalko.com +short
# Expected: 10.82.0.5

dig @10.82.0.13 pve.colt.chalko.com +short
# Expected: 10.82.0.2

dig @10.82.0.13 colt-gpu-01.colt.chalko.com +short
# Expected: 10.82.0.3
```

- [ ] **Step 3: Test recursive forwarder**

```bash
dig @10.82.0.13 google.com +short
# Expected: resolved via upstream 10.82.0.1 / 1.1.1.1
```
