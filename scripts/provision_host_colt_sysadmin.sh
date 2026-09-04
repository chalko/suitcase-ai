#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/provision_host_colt_sysadmin.sh
# Purpose: Provision colt-sysadmin-agent user, OpenSSH CA trust, and sudoers
#          on Camp Colt target hosts (e.g. colt-cp-01 / colt-gpu-01).
# Usage:   Run as root on the target host.
# ==============================================================================
set -euo pipefail

# 1. Create system user and .ssh directory
if ! id "colt-sysadmin-agent" &>/dev/null; then
    useradd -m -s /bin/bash colt-sysadmin-agent
    echo "[✓] Created user colt-sysadmin-agent"
else
    echo "[i] User colt-sysadmin-agent already exists"
fi

mkdir -p /home/colt-sysadmin-agent/.ssh
chmod 700 /home/colt-sysadmin-agent/.ssh
chown -R colt-sysadmin-agent:colt-sysadmin-agent /home/colt-sysadmin-agent/.ssh
echo "[✓] Configured /home/colt-sysadmin-agent/.ssh"

# 2. Add OpenSSH CA principal mapping
mkdir -p /etc/ssh/auth_principals
cat << 'EOF' > /etc/ssh/auth_principals/colt-sysadmin-agent
colt-sysadmin-agent
colt-sysadmin
sysadmin-agent
EOF
chmod 644 /etc/ssh/auth_principals/colt-sysadmin-agent
echo "[✓] Configured /etc/ssh/auth_principals/colt-sysadmin-agent"

# 3. Deploy OpenSSH CA public key
cat << 'EOF' > /etc/ssh/trusted-user-ca-keys.pem
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn1FgWAOByDV/ee2AVj7UoHPxAGfG/ralalyfaTBfDh3ecPr1hac02skmw3YhnTL2aR8atJCY2DD63brU4fKma7EyTPxbXeJW0n0nmChl+I+L35PQtvZ7dcWPPznbS5G5Lk2PoAY0m3IBJJtbq3MgazOuww8dVDtciFOQBrc8Cglh+iuL1r7i9kBDDO8ZpmjrEAAH2HWaGO5AWuJnxZAUIAD8sv+Lv84d03LMuTrMyZBrq6csIcdmtPoewv1ay/JPUUCCsKI53fvClr2bdUhlW6wwfeq0iN7Nj+ygDziM8+npAxx6jUthG+VTcINKeaLMBUZ1DxAeIXNLPe2ZkH945cVdmHeKinJrAGQDnLArMaoVvC3rugq5lj/WuU3pnR4dgrkfWByVO5aNtsFv4i9nUHCcuWzU5OXArsVolC2gk792oesIbuZCtDzEZYisy4zJ09Aq/toBZXTG1Zb2FJkYCtyWSJ1Lmn6FVfX6jy7V5ktSptb+sznwHu089ch7U0gE= cardno:11_138_351
EOF
chmod 644 /etc/ssh/trusted-user-ca-keys.pem
echo "[✓] Configured /etc/ssh/trusted-user-ca-keys.pem"

# 4. Ensure CA trust in sshd_config and restart ssh
if ! grep -q "TrustedUserCAKeys" /etc/ssh/sshd_config; then
    echo "TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem" >> /etc/ssh/sshd_config
fi

if ! grep -q "AuthorizedPrincipalsFile" /etc/ssh/sshd_config; then
    echo "AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u" >> /etc/ssh/sshd_config
fi

systemctl restart ssh || systemctl restart sshd
echo "[✓] Configured and restarted sshd"

# 5. Configure passwordless sudo
echo "colt-sysadmin-agent ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-colt-sysadmin-agent
chmod 0440 /etc/sudoers.d/99-colt-sysadmin-agent
echo "[✓] Configured /etc/sudoers.d/99-colt-sysadmin-agent"

echo -e "\n[✓] Host provisioning complete for colt-sysadmin-agent."
