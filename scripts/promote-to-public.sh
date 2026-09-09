#!/usr/bin/env bash
# ==============================================================================
# scripts/promote-to-public.sh
# Promotes validated commits from 'main' to 'public' gatekeeper branch
# ==============================================================================
set -euo pipefail

REMOTE="${REMOTE:-colt}"
MAIN_BRANCH="main"
PUBLIC_BRANCH="public"

echo "======================================================================"
echo " [Promotion] Promoting 'main' to 'public' with Zero-Plaintext Gate"
echo "======================================================================"

# 1. Ensure working directory is clean
if ! git diff-index --quiet HEAD --; then
  echo "❌ ERROR: Working tree is dirty. Please commit or stash changes before promoting."
  exit 1
fi

# 2. Run Zero-Plaintext Preflight Scan
echo "==> Running Zero-Plaintext preflight security scan..."
./scripts/preflight-public-scan.sh

# 3. Fetch latest refs from remote
echo "==> Fetching latest changes from remote '${REMOTE}'..."
git fetch "${REMOTE}"

# 4. Check out or create public branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> Switching to branch '${PUBLIC_BRANCH}'..."
if git show-ref --verify --quiet "refs/heads/${PUBLIC_BRANCH}"; then
  git checkout "${PUBLIC_BRANCH}"
  git merge --ff-only "${REMOTE}/${MAIN_BRANCH}" || git reset --hard "${REMOTE}/${MAIN_BRANCH}"
else
  git checkout -b "${PUBLIC_BRANCH}" "${REMOTE}/${MAIN_BRANCH}"
fi

# 5. Push public branch to remote
echo "==> Pushing '${PUBLIC_BRANCH}' to remote '${REMOTE}'..."
git push "${REMOTE}" "${PUBLIC_BRANCH}"

# 6. Return to original branch
echo "==> Returning to original branch '${CURRENT_BRANCH}'..."
git checkout "${CURRENT_BRANCH}"

echo "======================================================================"
echo " ✔ PROMOTION SUCCESSFUL: '${PUBLIC_BRANCH}' is synchronized with '${MAIN_BRANCH}'"
echo " Gitea Actions will now trigger automated synchronization to GitHub main."
echo "======================================================================"
