#!/usr/bin/env bash
# ==============================================================================
# scripts/configure-harbor-proxy-projects.sh
# Configures pull-through proxy cache endpoints and projects in Harbor
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export VAULT_ADDR="${VAULT_ADDR:-https://10.82.0.5:8200}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"
export VAULT_CLIENT_CERT="${VAULT_CLIENT_CERT:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.crt}"
export VAULT_CLIENT_KEY="${VAULT_CLIENT_KEY:-$REPO_ROOT/agent-keys/agents/colt-sysadmin/colt-sysadmin_tls.key}"

echo "Authenticating to Vault..."
vault login -method=cert >/dev/null

HARBOR_URL="https://harbor.colt.chalko.com"
ADMIN_PASSWORD="$(vault kv get -field=admin_password secret/colt/harbor)"

echo "Testing connection to Harbor API..."
curl -sk -u "admin:${ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/ping" >/dev/null
echo "Harbor API is responsive."

create_or_get_registry() {
  local name="$1"
  local type="$2"
  local url="$3"

  local existing_id
  existing_id="$(curl -sk -u "admin:${ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/registries?name=${name}" | jq -r '.[0].id // empty')"

  if [ -n "${existing_id}" ]; then
    echo "Registry '${name}' already exists (ID: ${existing_id})."
    echo "${existing_id}"
    return
  fi

  echo "Creating registry endpoint '${name}' (${type} -> ${url})..." >&2
  curl -sk -u "admin:${ADMIN_PASSWORD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"type\":\"${type}\",\"url\":\"${url}\",\"insecure\":false}" \
    "${HARBOR_URL}/api/v2.0/registries" >/dev/null

  existing_id="$(curl -sk -u "admin:${ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/registries?name=${name}" | jq -r '.[0].id')"
  echo "Created registry '${name}' (ID: ${existing_id})." >&2
  echo "${existing_id}"
}

create_proxy_project() {
  local project_name="$1"
  local registry_id="$2"

  local project_exists
  project_exists="$(curl -sk -u "admin:${ADMIN_PASSWORD}" "${HARBOR_URL}/api/v2.0/projects?name=${project_name}" | jq -r '.[0].project_id // empty')"

  if [ -n "${project_exists}" ]; then
    echo "Proxy project '${project_name}' already exists (ID: ${project_exists})."
    return
  fi

  echo "Creating proxy cache project '${project_name}' backed by registry ${registry_id}..."
  curl -sk -u "admin:${ADMIN_PASSWORD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"project_name\": \"${project_name}\",
      \"public\": true,
      \"registry_id\": ${registry_id},
      \"metadata\": {
        \"public\": \"true\",
        \"enable_content_trust\": \"false\",
        \"auto_scan\": \"false\",
        \"prevent_vul\": \"false\"
      }
    }" \
    "${HARBOR_URL}/api/v2.0/projects" >/dev/null

  echo "✔ Created proxy cache project '${project_name}'."
}

# 1. Docker Hub Proxy
DOCKER_REG_ID="$(create_or_get_registry "dockerhub-upstream" "docker-hub" "https://hub.docker.com")"
create_proxy_project "docker-proxy" "${DOCKER_REG_ID}"

# 2. GitHub Container Registry (ghcr.io) Proxy
GHCR_REG_ID="$(create_or_get_registry "ghcr-upstream" "github-ghcr" "https://ghcr.io")"
create_proxy_project "ghcr-proxy" "${GHCR_REG_ID}"

# 3. NVIDIA NGC Registry (nvcr.io) Proxy
NVCR_REG_ID="$(create_or_get_registry "nvcr-upstream" "docker-registry" "https://nvcr.io")"
create_proxy_project "nvcr-proxy" "${NVCR_REG_ID}"

echo "✔ Successfully configured Harbor pull-through proxy cache endpoints and projects."
