#!/usr/bin/env bash
# ==============================================================================
# File: scripts/sign_agent_cert.sh
# Description: Signs OpenSSH client certificates for autonomous agents across
#              Camp Colt / Suitcase AI using a host CA key or YubiKey.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default parameter values
AGENT_NAME=""
AGENT_PUB_KEY=""
PRINCIPAL=""
VALIDITY="-5m:+30d"
CA_KEY=""
TARGET_HOST=""
TARGET_USER=""
TARGET_DIR=""
DRY_RUN=0
VERBOSE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]

${BOLD}Description:${NC}
  Signs an OpenSSH client certificate for an agent public key using a local CA
  key or hardware security key (YubiKey) and installs/deploys the certificate.

${BOLD}Options:${NC}
  -a, --agent-name NAME     Agent identity name (e.g., colt_sysadmin, sysadmin-agent)
  -p, --pub PATH            Path to agent public key file (.pub)
  -n, --principal PRINC     Principal(s) (comma-separated, e.g. \"colt-sysadmin,sysadmin-agent,sysadmin\")
  -V, --validity DURATION   Certificate validity window (default: \"-5m:+30d\")
      --ca-key PATH         Path to CA private key or public stub for YubiKey (default: auto-detected)
  -H, --target-host HOST    Optional remote host to deploy certificate to (e.g. \"10.82.0.2\")
  -u, --target-user USER    Target remote user (default: "colt-sysadmin-agent")
      --target-dir DIR      Target remote directory (default: "/home/<user>/.ssh")
      --dry-run             Perform validation checks without signing or deploying
  -v, --verbose             Enable debug tracing
  -h, --help                Show this help message

${BOLD}Examples:${NC}
  # Sign certificate for colt-sysadmin:
  $0 -a colt_sysadmin -n \"colt-sysadmin,colt-sysadmin-agent,sysadmin-agent\"

  # Sign with custom key path and deploy to Camp Colt control plane:
  $0 -p ~/.ssh/agents/id_ed25519_colt_sysadmin.pub -n colt-sysadmin -H 10.82.0.2 -u colt-sysadmin-agent

  # Sign a 24-hour temporary cert:
  $0 -a colt_sysadmin -V \"-5m:+24h\""
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--agent-name|--name)
            AGENT_NAME="$2"
            shift 2
            ;;
        -p|--pub|--agent-pub)
            AGENT_PUB_KEY="$2"
            shift 2
            ;;
        -n|--principal|--principals)
            PRINCIPAL="$2"
            shift 2
            ;;
        -V|--validity)
            VALIDITY="$2"
            shift 2
            ;;
        --ca-key)
            CA_KEY="$2"
            shift 2
            ;;
        -H|--target-host|--host)
            TARGET_HOST="$2"
            shift 2
            ;;
        -u|--target-user|--user)
            TARGET_USER="$2"
            shift 2
            ;;
        --target-dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            set -x
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}[✖] ERROR:${NC} Unknown argument: $1" >&2
            echo "Use -h or --help for usage information." >&2
            exit 1
            ;;
    esac
done

# 1. Resolve agent public key
if [[ -z "${AGENT_PUB_KEY}" ]]; then
    if [[ -z "${AGENT_NAME}" ]]; then
        echo -e "${RED}[✖] ERROR:${NC} Must specify either --agent-name (-a) or --pub (-p)." >&2
        echo "Use -h or --help for usage information." >&2
        exit 1
    fi

    # Try common locations
    candidates=(
        "${HOME}/.ssh/agents/id_ed25519_${AGENT_NAME}.pub"
        "${HOME}/.ssh/agents/id_ed25519_${AGENT_NAME//-/_}.pub"
        "${HOME}/.ssh/id_ed25519_${AGENT_NAME}.pub"
        "${HOME}/.ssh/id_ed25519_${AGENT_NAME//-/_}.pub"
        "${REPO_ROOT}/agent-keys/agents/${AGENT_NAME}/id_ed25519_${AGENT_NAME}.pub"
    )

    for cand in "${candidates[@]}"; do
        if [[ -f "${cand}" ]]; then
            AGENT_PUB_KEY="${cand}"
            break
        fi
    done

    if [[ -z "${AGENT_PUB_KEY}" ]]; then
        echo -e "${RED}[✖] ERROR:${NC} Could not find public key for agent '${AGENT_NAME}' in standard locations." >&2
        echo "Checked: ${candidates[*]}" >&2
        exit 1
    fi
fi

if [[ ! -f "${AGENT_PUB_KEY}" ]]; then
    echo -e "${RED}[✖] ERROR:${NC} Agent public key not found at ${AGENT_PUB_KEY}" >&2
    exit 1
fi

CERT_FILE="${AGENT_PUB_KEY%.pub}-cert.pub"

# 2. Derive default principal if not provided
if [[ -z "${PRINCIPAL}" ]]; then
    if [[ -n "${AGENT_NAME}" ]]; then
        PRINCIPAL="${AGENT_NAME//_/-}"
    else
        base_name="$(basename "${AGENT_PUB_KEY}" .pub)"
        PRINCIPAL="${base_name#id_ed25519_}"
        PRINCIPAL="${PRINCIPAL//_/-}"
    fi
fi

# 3. Resolve CA key / YubiKey stub
if [[ -z "${CA_KEY}" ]]; then
    ca_candidates=(
        "${HOME}/.ssh/id_rsa_yubikey.pub"
        "${HOME}/.ssh/id_ed25519_yubikey.pub"
        "${HOME}/.ssh/id_ed25519_ca.pub"
        "${HOME}/.ssh/id_rsa_yubikey"
        "${HOME}/.ssh/id_ed25519_ca"
    )
    for ca_cand in "${ca_candidates[@]}"; do
        if [[ -f "${ca_cand}" ]]; then
            CA_KEY="${ca_cand}"
            break
        fi
    done
    if [[ -z "${CA_KEY}" ]]; then
        CA_KEY="${HOME}/.ssh/id_rsa_yubikey.pub"
    fi
fi

if [[ ! -f "${CA_KEY}" && ${DRY_RUN} -eq 0 ]]; then
    echo -e "${RED}[✖] ERROR:${NC} CA key not found at ${CA_KEY}" >&2
    echo -e "  ${YELLOW}Remedy:${NC} Plug in your YubiKey or ensure CA key exists in ~/.ssh/." >&2
    exit 1
fi

# 4. Generate serial number & key ID
entropy=$(od -An -N4 -tu4 < /dev/urandom 2>/dev/null | awk '{printf "%05d", $1 % 100000}' || printf "%05d" "$((RANDOM % 100000))")
serial="$(date +%s)${entropy}"
key_id="agent:${PRINCIPAL}@scai-$(date +%s)"

agent_flags=()
if [[ "${CA_KEY}" == *.pub ]]; then
    agent_flags=("-U")
fi

echo -e "\n${BLUE}============================================================${NC}"
echo -e "${BOLD} Signing OpenSSH Agent Certificate${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "  • ${BOLD}Public Key:${NC}   ${AGENT_PUB_KEY}"
echo -e "  • ${BOLD}Certificate:${NC}  ${CERT_FILE}"
echo -e "  • ${BOLD}Principal(s):${NC} ${GREEN}${PRINCIPAL}${NC}"
echo -e "  • ${BOLD}Validity:${NC}     ${GREEN}${VALIDITY}${NC}"
echo -e "  • ${BOLD}Key ID:${NC}       ${key_id}"
echo -e "  • ${BOLD}CA Key:${NC}       ${CA_KEY}"
echo -e "${BLUE}============================================================${NC}\n"

if [[ ${DRY_RUN} -eq 1 ]]; then
    echo -e "${YELLOW}[DRY-RUN] Pre-flight validation passed. Skipping signing invocation.${NC}"
    exit 0
fi

echo -e "${YELLOW}${BOLD}>> ACTION REQUIRED: Please touch your YubiKey if prompted! <<${NC}\n"

rm -f "${CERT_FILE}"

ssh-keygen "${agent_flags[@]}" \
    -s "${CA_KEY}" \
    -I "${key_id}" \
    -n "${PRINCIPAL}" \
    -V "${VALIDITY}" \
    -z "${serial}" \
    -O clear \
    -O permit-pty \
    -O permit-user-rc \
    "${AGENT_PUB_KEY}"

if ! ssh-keygen -L -f "${CERT_FILE}" >/dev/null 2>&1; then
    echo -e "${RED}[✖] ERROR:${NC} Failed to verify generated OpenSSH certificate at ${CERT_FILE}" >&2
    exit 1
fi

echo -e "\n${GREEN}[✓] Certificate successfully generated & verified:${NC}"
ssh-keygen -L -f "${CERT_FILE}" | sed 's/^/    /'

# 5. Local and Remote Deployment
# Ensure cert is present in ~/.ssh/ directory if signed in ~/.ssh/agents/
local_dot_ssh="${HOME}/.ssh/$(basename "${CERT_FILE}")"
if [[ "${CERT_FILE}" != "${local_dot_ssh}" ]]; then
    cp -f "${CERT_FILE}" "${local_dot_ssh}"
    chmod 644 "${local_dot_ssh}"
    echo -e "\n${GREEN}[✓] Certificate mirrored to:${NC} ${local_dot_ssh}"
fi

if [[ -n "${TARGET_HOST}" ]]; then
    if [[ -z "${TARGET_USER}" ]]; then
        TARGET_USER="colt-sysadmin-agent"
    fi
    if [[ -z "${TARGET_DIR}" ]]; then
        if [[ "${TARGET_USER}" == "root" ]]; then
            TARGET_DIR="/root/.ssh"
        else
            TARGET_DIR="/home/${TARGET_USER}/.ssh"
        fi
    fi
    echo -e "\n[*] Deploying certificate to remote host: ${TARGET_HOST}:${TARGET_DIR}..."
    ssh -o IdentitiesOnly=yes "${TARGET_USER}@${TARGET_HOST}" "mkdir -p '${TARGET_DIR}' && chmod 700 '${TARGET_DIR}'"
    scp -o IdentitiesOnly=yes "${CERT_FILE}" "${TARGET_USER}@${TARGET_HOST}:${TARGET_DIR}/$(basename "${CERT_FILE}")"
    echo -e "${GREEN}[✓] Deployed certificate to ${TARGET_USER}@${TARGET_HOST}:${TARGET_DIR}/$(basename "${CERT_FILE}")${NC}"
fi

echo -e "\n${GREEN}${BOLD}Signing & deployment complete.${NC}\n"
