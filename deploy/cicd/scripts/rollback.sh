#!/usr/bin/env bash
# 一键回滚到上一稳定 tag
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:-}"  # 可选 override

if [[ -z "$TAG" ]]; then
    echo "[*] 未指定 tag，将自动回到上一稳定版本"
fi

echo "[!] 即将在生产执行回滚"
read -r -p "确认？[y/N] " ok
[[ "${ok,,}" == "y" ]] || exit 0

cd ansible

if [[ -n "$TAG" ]]; then
    ansible-playbook -i inventories/production.yml playbooks/rollback.yml \
        -e "rollback_tag=$TAG"
else
    ansible-playbook -i inventories/production.yml playbooks/rollback.yml
fi

echo "[+] 回滚完成"
