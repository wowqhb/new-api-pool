#!/usr/bin/env bash
# SSH 加固脚本（幂等）
# ⚠️ 跑之前确保你能用 key 登录！否则改完就锁外面
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "需要 root"; exit 1; }

SSH_PORT="${SSH_PORT:-23456}"
ALLOW_USERS="${ALLOW_USERS:-ops}"

CONFIG=/etc/ssh/sshd_config
BACKUP="${CONFIG}.bak.$(date +%s)"

cp "$CONFIG" "$BACKUP"
echo "[+] 备份 $CONFIG -> $BACKUP"

set_or_replace() {
	local key="$1" val="$2"
	if grep -qE "^[#\s]*${key}\s" "$CONFIG"; then
		sed -i "s|^[#\s]*${key}\s.*|${key} ${val}|" "$CONFIG"
	else
		echo "${key} ${val}" >> "$CONFIG"
	fi
}

set_or_replace Port "$SSH_PORT"
set_or_replace Protocol 2
set_or_replace PermitRootLogin no
set_or_replace PasswordAuthentication no
set_or_replace PubkeyAuthentication yes
set_or_replace ChallengeResponseAuthentication no
set_or_replace MaxAuthTries 3
set_or_replace LoginGraceTime 30
set_or_replace ClientAliveInterval 300
set_or_replace ClientAliveCountMax 2
set_or_replace X11Forwarding no
set_or_replace AllowAgentForwarding no
set_or_replace AllowUsers "$ALLOW_USERS"

echo "[+] sshd_config 已更新"
sshd -t && echo "[+] 配置语法 OK"

if command -v ufw >/dev/null; then
	ufw allow "${SSH_PORT}/tcp" || true
	ufw allow 80/tcp || true
	ufw allow 443/tcp || true
fi

systemctl reload sshd
echo "[+] sshd 已 reload。请新开一个会话验证 ssh -p ${SSH_PORT} ${ALLOW_USERS}@<host> 能登"
echo "[!] 如失败：sudo cp ${BACKUP} ${CONFIG} && sudo systemctl reload sshd"
