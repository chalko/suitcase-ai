#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/fix_colt_cp_ca.sh
# Purpose: Installs YubiKey SSH CA public key on colt-cp-01 and restarts sshd.
# Usage:   Run as root on colt-cp-01 (or via: ssh root@10.82.0.2 "bash -s" < fix_colt_cp_ca.sh)
# ==============================================================================
set -euo pipefail

echo "[*] Installing OpenSSH CA trusted public key..."
cat << 'EOF' > /etc/ssh/trusted-user-ca-keys.pem
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn1FgWAOByDV/ee2AVj7UoHPxAGfG/ralalyfaTBfDh3ecPr1hac02skmw3YhnTL2aR8atJCY2DD63brU4fKma7EyTPxbXeJW0n0nmChl+I+L35PQtvZ7dcWPPznbS5G5Lk2PoAY0m3IBJJtbq3MgazOuww8dVDtciFOQBrc8Cglh+iuL1r7i9kBDDO8ZpmjrEAAH2HWaGO5AWuJnxZAUIAD8sv+Lv84d03LMuTrMyZBrq6csIcdmtPoewv1ay/JPUUCCsKI53fvClr2bdUhlW6wwfeq0iN7Nj+ygDziM8+npAxx6jUthG+VTcINKeaLMBUZ1DxAeIXNLPe2ZkH945cVdmHeKinJrAGQDnLArMaoVvC3rugq5lj/WuU3pnR4dgrkfWByVO5aNtsFv4i9nUHCcuWzU5OXArsVolC2gk792oesIbuZCtDzEZYisy4zJ09Aq/toBZXTG1Zb2FJkYCtyWSJ1Lmn6FVfX6jy7V5ktSptb+sznwHu089ch7U0gE= cardno:11_138_351
EOF
chmod 644 /etc/ssh/trusted-user-ca-keys.pem
echo "[✓] Written /etc/ssh/trusted-user-ca-keys.pem"

echo "[*] Ensuring sshd_config CA directives..."
grep -q "TrustedUserCAKeys" /etc/ssh/sshd_config || echo "TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem" >> /etc/ssh/sshd_config
grep -q "AuthorizedPrincipalsFile" /etc/ssh/sshd_config || echo "AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u" >> /etc/ssh/sshd_config

echo "[*] Restarting ssh service..."
systemctl restart ssh || systemctl restart sshd
echo "[✓] SSH service restarted successfully."
