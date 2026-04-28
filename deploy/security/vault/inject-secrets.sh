#!/usr/bin/env bash
# Vault 上游 Key 操作工具（CLI 包装）
# 用法：
#   vault-export.sh <path>            # 取值
#   vault-import-bulk.sh <csv>        # 批量从 CSV 导入
#   vault-list.sh                     # 列出
set -euo pipefail

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:?需要 VAULT_TOKEN（root token 或 AppRole token）}"
export VAULT_ADDR VAULT_TOKEN

cmd="${1:-help}"
shift || true

case "$cmd" in
  put)
    # put openai/sk-proj-001 api_key=sk-... email=...
    PATH_="$1"; shift
    docker exec -i vault vault kv put "secret/upstream/${PATH_}" "$@"
    ;;
  get)
    PATH_="$1"
    docker exec -i vault vault kv get -format=json "secret/upstream/${PATH_}" | jq '.data.data'
    ;;
  list)
    PATH_="${1:-}"
    docker exec -i vault vault kv list "secret/upstream/${PATH_}"
    ;;
  delete)
    PATH_="$1"
    docker exec -i vault vault kv delete "secret/upstream/${PATH_}"
    ;;
  audit)
    docker exec -i vault tail -100 /vault/audit/audit.log | jq '.'
    ;;
  *)
    echo "用法："
    echo "  $0 put <source/account> key=val [key=val...]"
    echo "  $0 get <source/account>"
    echo "  $0 list [source]"
    echo "  $0 delete <source/account>"
    echo "  $0 audit"
    exit 1
    ;;
esac
