#!/usr/bin/env bash
# ==============================================================================
# scripts/preflight-public-scan.sh
# Zero-Plaintext Security Preflight Scanner for Public Releases
# ==============================================================================
set -euo pipefail

echo "======================================================================"
echo " [Zero-Plaintext] Running Preflight Security Scan for Public Release"
echo "======================================================================"

EXIT_CODE=0

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
  echo "❌ ERROR: git command not found"
  exit 1
fi

# List of tracked files
TRACKED_FILES=$(git ls-files)

# 1. Check for raw Private Keys in tracked files
echo "==> Scanning tracked files for unencrypted private keys..."
if echo "$TRACKED_FILES" | xargs grep -nE "BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY" 2>/dev/null; then
  echo "❌ ERROR: Private key pattern detected in git tracked files!"
  EXIT_CODE=1
else
  echo "✔ No private keys detected."
fi

# 2. Check for raw NGC or API tokens
echo "==> Scanning tracked files for raw NGC / GitHub / API tokens..."
if echo "$TRACKED_FILES" | xargs grep -nE "nvapi-[a-zA-Z0-9_-]{30,}|ghp_[a-zA-Z0-9]{30,}|gho_[a-zA-Z0-9]{30,}" 2>/dev/null; then
  echo "❌ ERROR: Raw API token pattern detected in git tracked files!"
  EXIT_CODE=1
else
  echo "✔ No raw API tokens detected."
fi

# 3. Check for raw Vault tokens or unseal keys
echo "==> Scanning tracked files for raw Vault root tokens..."
if echo "$TRACKED_FILES" | xargs grep -nE "hvs\.[a-zA-Z0-9_-]{24,}|VAULT_TOKEN=[a-zA-Z0-9_-]{10,}" 2>/dev/null; then
  echo "❌ ERROR: Raw Vault credential pattern detected in git tracked files!"
  EXIT_CODE=1
else
  echo "✔ No raw Vault credentials detected."
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "======================================================================"
  echo " ✔ ALL PREFLIGHT SECURITY CHECKS PASSED: Safe for public egress."
  echo "======================================================================"
else
  echo "======================================================================"
  echo " ❌ PREFLIGHT CHECKS FAILED: Public synchronization aborted."
  echo "======================================================================"
fi

exit "$EXIT_CODE"
