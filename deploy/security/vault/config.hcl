storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://127.0.0.1:8200"
ui = true
disable_mlock = false
default_lease_ttl = "168h"
max_lease_ttl = "720h"

# 生产建议：
# 1. 用 raft 替代 file storage（HA）
# 2. 启 TLS（证书放 ./tls/）
# 3. 用 Cloudflare Access 把 8200 套住
