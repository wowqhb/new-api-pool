# Runbook 07：号池大批失效

**P1** · 影响：成本飙升 / 部分用户 429 · 目标 MTTR：30 分钟切流稳定

## 现象 / 触发

- `ChannelMassFailure` 告警批量触发
- 某分组（如 `gemini-free` / `claude-oauth`）50%+ 渠道被自动禁用
- 用户大量 429 / 500 / 401 反馈
- 上游成本（在能监控的部分）突然变化（号失效后流量打到付费分组）

## 第一时间动作

1. **判断是哪个分组受灾**：
   ```bash
   # 看分组的禁用渠道数
   docker exec new-api-postgres psql -U newapi -d newapi -c "
     SELECT \"group\", status, count(*)
     FROM channels
     WHERE \"group\" IS NOT NULL
     GROUP BY \"group\", status
     ORDER BY \"group\", status;
   "
   ```
   `status=2` 是被自动禁用的，`status=3` 是手动禁用。

2. **判断失效原因**（看其中一个具体渠道的最新日志）：
   ```bash
   docker exec new-api-postgres psql -U newapi -d newapi -c "
     SELECT created_at, content FROM logs
     WHERE channel_id = <某个被禁用的渠道 ID>
     ORDER BY created_at DESC LIMIT 5;
   "
   ```

   常见原因：
   - **401/403 集体 → 上游统一封号潮**（最常见）→ 等几小时不会自己好，要补号
   - **429 集体 → 限速/配额**（Gemini Free 当日跑完了等明天）→ 大概率第二天恢复
   - **5xx 集体 → 上游故障**（看 Runbook 01）
   - **超时集体 → 网络/代理问题**（看自己出网）

3. **临时止血**：
   - 把还活着的高优分组（`official`）权重调高
   - 受灾分组对应的用户分组临时切到上一档（`free` 用户暂停或限速更狠）
   - 公告 / 状态页

4. **应急号池启动**：
   - 把"备用号池"渠道从 `weight=0` 调成正常
   - 应急号池平时建议保留 30% 容量不上线，专门应急用

## 长期对策

- 保持号池冗余：可用容量至少是高峰需求的 **2x**
- 自动化注册流水线（todo `upstream_*` 系列）
- 多家上游分散风险，不要 all-in 一家
- **官方付费 Key 兜底比例 ≥ 30%**

## 事后复盘

- 失效号数 / 失效原因分布：
- 应急号池补充用时：
- 期间额外成本（流量打到付费分组）：$
- 需要补购号数：
- 是否需要扩展号池上游：
