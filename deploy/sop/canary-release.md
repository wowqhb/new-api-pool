# SOP：灰度发布

每次新功能上线 / 新分组接入 / 新版本升级，必须走灰度。

## 四阶段灰度

```
P1 内测     P2 白名单    P3 邀请码      P4 公开
─────────  ─────────  ─────────  ─────────
5 人 1 周  50 人 2 周  500 人 4 周  全量
```

## 阶段晋级标准

| 阶段 | 流量 | 周期 | 晋级标准 | 回滚条件 |
|---|---|---|---|---|
| **P1 内测** | 5 内部人 | 1 周 | 核心通路全跑通，无 P0 故障 | 任意核心通路不通 |
| **P2 白名单** | 50 邀请用户 | 2 周 | SLO 达标（成功率 ≥ 99%），无 P1 故障 | 5xx > 1% 或 P1 故障 |
| **P3 邀请码** | 500 用户 | 4 周 | 毛利达标，风控有效，客服可承受 | 单日亏 > $100 或客服爆量 |
| **P4 公开** | 全量 | 持续 | - | - |

## 灰度配置（用 user_group 实现）

```bash
# 创建灰度用户分组
docker exec new-api-postgres psql -U newapi -d newapi -c "
INSERT INTO options (key, value)
SELECT 'GroupRatio', '{\"vip\":1.5,\"default\":1.2,\"free\":1.0,\"canary\":1.2,\"auto\":1.2}'
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
"

# 把内测用户改成 canary 分组
# admin → 用户管理 → 编辑 → 用户分组改为 canary

# 灰度渠道 group 也叫 canary（或 xxx-canary），只对 canary 分组用户路由
```

## 每阶段必做

- [ ] **晋级前**：跑一遍 [`testing/k6-smoke.sh`](../testing/k6-smoke.sh) 烟囱测试
- [ ] **晋级前**：在 Grafana 截图当前 SLO 看板，存档对比
- [ ] **晋级前**：填《灰度晋级评审表》（[`canary-checklist.md`](./canary-checklist.md)）
- [ ] **晋级中**：值班 24h 实时盯指标（前 1 天必须有人盯）
- [ ] **晋级后**：48h 内出阶段总结：什么数据 / 什么问题 / 改了什么

## 回滚流程

每次发布**事前必须**写好回滚命令：

```bash
# 例：渠道改回老 group
curl -X PUT "${API_BASE}/api/channel" \
  -H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
  -d '{"id": <ID>, "group": "<原 group>"}'

# 例：版本回滚（在 .env 里改 NEW_API_VERSION）
$EDITOR .env
docker compose -f docker-compose.prod.yml up -d new-api-1 new-api-2

# 例：用户分组回滚
UPDATE users SET "group" = 'default' WHERE "group" = 'canary';
```

## 灰度时的告警阈值（更敏感）

灰度期间 Prometheus 告警阈值要**更敏感**：

- 5xx 错误率 > 1%（正常 5%）
- p95 延迟 > 上游基线 + 200ms（正常 + 500ms）
- 任意 P0 → 立即回滚不讨论

复制一份 `monitoring/rules/` 到 `monitoring/rules-canary/`，把阈值收紧后用 `external_labels: tier=canary` 区分。
