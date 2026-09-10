#!/usr/bin/env bash
# Pre-flight Guardrail: Verify Kubernetes context points strictly to Camp Colt
set -euo pipefail

if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
elif [ -n "${ZSH_VERSION:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Default KUBECONFIG to colt-kubeconfig if not explicitly set
if [ -z "${KUBECONFIG:-}" ]; then
    if [ -f "$REPO_ROOT/colt-kubeconfig" ]; then
        export KUBECONFIG="$REPO_ROOT/colt-kubeconfig"
    fi
fi

if [ -z "${KUBECONFIG:-}" ] || [ ! -f "$KUBECONFIG" ]; then
    echo "ERROR: KUBECONFIG is not set or file does not exist ($KUBECONFIG)." >&2
    echo "Expected: $REPO_ROOT/colt-kubeconfig" >&2
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
CURRENT_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)

echo "=== Camp Colt Pre-flight Cluster Context Check ==="
echo "KUBECONFIG:      $KUBECONFIG"
echo "Current Context: $CURRENT_CONTEXT"
echo "Server Endpoint: $CURRENT_SERVER"

# Validate that context is Camp Colt
if [[ "$CURRENT_CONTEXT" != *"camp-colt"* ]]; then
    echo "CRITICAL SAFETY ERROR: Context '$CURRENT_CONTEXT' does not match 'camp-colt'!" >&2
    echo "Mutating commands against foreign rigs (e.g. Fog) are strictly forbidden." >&2
    exit 1
fi

# Validate that server IP is in Camp Colt subnet (10.82.0.0/16)
if [[ "$CURRENT_SERVER" != *"10.82."* ]]; then
    echo "CRITICAL SAFETY ERROR: Server endpoint '$CURRENT_SERVER' is outside the Camp Colt appliance network (10.82.0.0/16)!" >&2
    echo "Mutating commands against foreign rigs are strictly forbidden." >&2
    exit 1
fi

echo "✓ Verification passed: Target cluster is Camp Colt ($CURRENT_CONTEXT @ $CURRENT_SERVER)."
