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
