#!/usr/bin/env bash
set -euo pipefail
KEY="/home/luna-mayor-agent/luna/rigs/suitcase-ai/agent-keys/agents/colt-sysadmin/id_ed25519_colt_sysadmin_agent"
exec ssh -o StrictHostKeyChecking=no -i "$KEY" colt-sysadmin-agent@10.82.0.2 "$@"
