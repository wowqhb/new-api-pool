# 错误码字典

## HTTP 状态码

| 状态 | 说明 | 排查方向 |
|---|---|---|
| 200 | OK | 正常 |
| 400 | Bad Request | 请求参数错误，看响应 body |
| 401 | Unauthorized | Token 错误 / 过期 / 禁用 |
| 402 | Payment Required | 余额不足 |
| 403 | Forbidden | 无权访问该模型 / IP 不在白名单 |
| 404 | Not Found | 路径错误 / 模型不存在 |
| 409 | Conflict | 幂等冲突（同一 idempotency-key 重复）|
| 413 | Payload Too Large | 请求体过大 |
| 422 | Unprocessable Entity | 参数语义错误（如 messages 空数组）|
| 429 | Too Many Requests | 触发限速 / 配额耗尽 |
| 499 | Client Closed | 客户端主动断开 |
| 500 | Internal Server Error | 网关内部错误（请提交工单）|
| 502 | Bad Gateway | 上游连接失败 / 全部分组不可用 |
| 503 | Service Unavailable | 维护中 / 全员熔断 |
| 504 | Gateway Timeout | 上游响应超时 |

## 业务错误码（响应 body `error.code`）

```json
{
  "error": {
    "message": "Token 余额不足",
    "type": "insufficient_quota",
    "code": "AITR-402-INSUF-BAL",
    "param": null,
    "request_id": "req_abc123"
  }
}
```

### 鉴权类（AITR-401-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-401-NOTOKEN | 缺少 Authorization header | 加 header |
| AITR-401-BADFORMAT | header 格式错（缺 `Bearer `）| 修正格式 |
| AITR-401-NOTFOUND | Token 不存在 | 检查 Token / 是否被删 |
| AITR-401-DISABLED | Token 已禁用 | 启用或新建 |
| AITR-401-EXPIRED | Token 已过期 | 新建 |
| AITR-401-IPDENY | IP 不在白名单 | 添加 IP 或关闭白名单 |

### 计费类（AITR-402-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-402-INSUF-BAL | 用户余额不足 | 充值 |
| AITR-402-DAILY-LIMIT | 触发日消费上限 | 等次日 / 升档位 |
| AITR-402-MODEL-LIMIT | 该模型单笔最大消费触顶 | 减小请求 / 改模型 |

### 权限类（AITR-403-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-403-MODEL-FORBIDDEN | 您的分组无权使用该模型 | 升 VIP |
| AITR-403-AUP-VIOLATION | 检测到违反 AUP（敏感词等）| 修改请求 |
| AITR-403-CIDR-DENY | IP 不在白名单 | 见 401-IPDENY |

### 路由类（AITR-404/422-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-404-MODEL | 模型 ID 不存在 | 检查模型清单 |
| AITR-404-PATH | API 路径错 | 检查 base_url + path |
| AITR-422-MSG-EMPTY | messages 为空 | 至少 1 条 message |
| AITR-422-MSG-FORMAT | message 格式错 | 看 schema |
| AITR-422-CTX-EXCEEDED | 上下文超过模型上限 | 截断 / 改模型 |

### 限速类（AITR-429-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-429-RPM | 触发 Token RPM 限制 | 退避重试 |
| AITR-429-TPM | 触发 Token TPM 限制 | 退避重试 |
| AITR-429-USER-DAILY | 触发用户日消费 | 等次日 |
| AITR-429-UPSTREAM | 上游限流 | 自动切渠道，无需处理 |

### 上游类（AITR-5xx-UPSTREAM-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-502-UPSTREAM-CONN | 上游连接失败 | 自动重试，多次失败可换模型 |
| AITR-503-NO-CHANNEL | 无可用渠道 | 全分组宕，等公告 |
| AITR-504-UPSTREAM-TIMEOUT | 上游超时 | 重试或缩短 prompt |

### 网关类（AITR-5xx-GW-*）
| 代码 | 说明 | 客户端处理 |
|---|---|---|
| AITR-500-GW-INTERNAL | 网关内部错误 | 提交工单 + request_id |
| AITR-503-GW-MAINT | 维护中 | 等公告 |
| AITR-503-GW-CIRCUIT-OPEN | 全员熔断（失败率超标）| 等告警解除 |

## 重试策略

| 状态 | 是否重试 | 退避 | 备注 |
|---|---|---|---|
| 401/402/403 | ❌ | - | 鉴权/计费类不重试 |
| 422 | ❌ | - | 参数错误不重试 |
| 429 | ✅ | 指数退避 | 用 `Retry-After` header（如有）|
| 5xx | ✅ | 指数退避 | 上游问题，最多 3 次 |
| 网络错误 | ✅ | 指数退避 | 客户端层 |

## 排查工具

每个响应都有：
- `X-Request-Id`：请求唯一 ID（提工单时附此）
- `X-RateLimit-Remaining-*`：剩余配额
- `X-Channel-Used`：本次实际命中的渠道（仅管理员）
- `X-Latency-Ms`：网关侧总耗时

提交工单时，至少提供 `request_id`，能让客服 1 分钟内定位问题。
