# Suitcase AI Public Release & GitHub Mirroring Runbook

This runbook outlines the operational lifecycle, security boundaries, and step-by-step procedures for synchronizing the sovereign **Suitcase AI** codebase from internal Gitea infrastructure (`colt/suitcase-ai`) to the public GitHub repository ([`github.com/chalko/suitcase-ai`](https://github.com/chalko/suitcase-ai)).

---

## 1. Branch Topology & Architecture

```mermaid
flowchart TD
    subgraph Internal_Gitea["Internal Gitea (gitea.colt.chalko.com)"]
        direction TB
        G_MAIN["Branch: main\n(Active infrastructure & platform development)"]
        PROMO["Promotion Gate\n(scripts/promote-to-public.sh)"]
        SCAN["Zero-Plaintext Security Scan\n(scripts/preflight-public-scan.sh)"]
        G_PUB["Branch: public\n(Curated public release snapshot)"]

        G_MAIN --> PROMO
        PROMO --> SCAN
        SCAN -->|Pass| G_PUB
    end

    subgraph Gitea_Actions["Gitea CI/CD Runner"]
        WF[".gitea/workflows/sync-github.yml\n(Trigger: on push to 'public')"]
        CI_SCAN["Preflight Scan Validation"]
        HTTPS_PUSH["HTTPS Git Push (GH_TOKEN)"]

        G_PUB --> WF
        WF --> CI_SCAN
        CI_SCAN -->|Pass| HTTPS_PUSH
    end

    subgraph GitHub_Public["Public GitHub (github.com/chalko/suitcase-ai)"]
        GH_MAIN["Branch: main\n(Public release & open source consumers)"]
    end

    HTTPS_PUSH -->|"git push github public:main --tags"| GH_MAIN
```

| Branch / Remote            | Purpose                                                            | Access Control                                    |
| :------------------------- | :----------------------------------------------------------------- | :------------------------------------------------ |
| **`colt/main`** (Gitea)    | Internal development, automation, and ongoing feature branches.    | Authorized sysadmins and platform operators only. |
| **`colt/public`** (Gitea)  | Gatekeeper branch containing sanitized, validated release commits. | Protected; updated only via promotion script.     |
| **`github/main`** (GitHub) | Public mirror of `colt/public` for open-source consumers.          | Public read-only; pushed automatically via CI/CD. |

---

## 2. Gitea Actions Secret Configuration

The automated push workflow authenticates using a GitHub Fine-Grained Personal Access Token (PAT) or Personal Access Token with repository write permissions:

1. **Create GitHub Access Token:**
   - Navigate to [`https://github.com/settings/tokens?type=beta`](https://github.com/settings/tokens?type=beta) (Fine-grained tokens) or Classic tokens.
   - Token Name: `gitea-suitcase-ai-sync`.
   - Repository access: Only select **`chalko/suitcase-ai`**.
   - Permissions: **Contents: Read and write**.
   - Generate token and copy token string (`github_pat_...` or `ghp_...`).
2. **Configure Gitea Actions Secret:**
   - Navigate to `https://gitea.colt.chalko.com/colt/suitcase-ai/settings/actions/secrets`.
   - Add Secret Name: **`GH_TOKEN`**.
   - Secret Value: Paste GitHub token string.

---

## 3. Routine Release Promotion Procedure

To promote the current state of `main` to the public GitHub repository:

1. **Verify Local Working Tree:**

   ```bash
   git status
   ```

   Ensure all intended changes are committed.

2. **Execute Promotion Script:**

   ```bash
   ./scripts/promote-to-public.sh
   ```

   This script performs the following automated steps:

   - Runs `./scripts/preflight-public-scan.sh` to ensure Zero-Plaintext compliance (no unencrypted private keys, raw API tokens, or root Vault keys).
   - Fast-forwards the local `public` branch to match `main` HEAD.
   - Pushes `public` to Gitea remote (`colt/public`).
   - Switches back to `main`.

3. **Verify Gitea Action Pipeline:**

   - Check the Actions tab in Gitea: `https://gitea.colt.chalko.com/colt/suitcase-ai/actions`.
   - Confirm the `Sync Public Branch to GitHub` workflow succeeds and pushes to GitHub.

4. **Verify GitHub Repository:**
   - Confirm the latest commit matches at [`https://github.com/chalko/suitcase-ai/commits/main`](https://github.com/chalko/suitcase-ai/commits/main).

---

## 4. Emergency Remediation & Rollback

If a commit on `public` needs to be reverted or amended:

1. **Reset `public` to a previous known-good commit:**

   ```bash
   git checkout public
   git reset --hard <GOOD_COMMIT_SHA>
   git push --force colt public
   ```

2. **Preflight Scan Failure:**
   If `./scripts/preflight-public-scan.sh` fails:
   - Identify the leaked secret reported in the output.
   - Remove or sanitize the occurrence on `main`.
   - Commit the sanitization fix, then rerun `./scripts/promote-to-public.sh`.
