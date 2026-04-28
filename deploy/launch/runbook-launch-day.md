# 上线当天值班手册

> 这是 P1 / P2 / P3 / P4 任一阶段开始的当天必备 SOP。

## T-7 天：准备

- [ ] 与团队对齐**当天值班排班**（至少 12 小时，最好 24 小时）
- [ ] 通知客服 / 工单值班
- [ ] 准备好用户公告（中英文）
- [ ] CDN 提前预热（如果有静态资源）
- [ ] 容量预估 + 提前扩容（如预期 100 人，扩到 200 人配置）

## T-1 天：最后检查

- [ ] 所有告警通道测试一遍（人为触发一个 fake alert）
- [ ] 一键回滚演练一次（不实际执行，但确认脚本能跑）
- [ ] 上游所有渠道 ping 一次
- [ ] 数据库做一次手动备份（额外的）
- [ ] 通知值班人员明天到岗时间

## T-2 小时：进入 war room 状态

- [ ] 所有相关人员上线（开 zoom / google meet / 飞书会议）
- [ ] Grafana 大盘投屏
- [ ] 客服系统打开
- [ ] Telegram 告警群专注
- [ ] 准备好 RCA 模板（万一需要）

## T-30 分钟：最后一轮

- [ ] 看 SLO 仪表板，无飘红
- [ ] 看待办告警，全部已处理
- [ ] 上游账户余额 ≥ 一周用量
- [ ] 客服话术再过一遍
- [ ] 公告文案准备好（草稿）

## T+0：开闸

```bash
# 实际"开闸"操作（按你的机制选）

# 选项 A：开放邀请码注册
deploy/scripts/enable-registration.sh

# 选项 B：发邀请码到目标用户
deploy/scripts/send-invitation-batch.sh --batch p2-whitelist.csv

# 选项 C：解除邀请码（公开）
deploy/scripts/disable-invitation-required.sh

# 然后发公告
deploy/scripts/publish-announcement.sh announcements/p2-launch.md
```

## T+5 分钟：观察

- [ ] 第一批用户注册成功？
- [ ] 错误率 < 1%？
- [ ] 客服系统接到工单？
- [ ] 告警没乱响？

## T+30 分钟：回顾

- [ ] 累计注册人数（vs 预期）
- [ ] 累计 API 调用（vs 预期）
- [ ] 客服累计工单数（vs 预期）
- [ ] 第一波退款 / 投诉

如果数据偏差大（实际 < 预期 50% 或 > 200%），调整策略：
- 太冷：检查公告是否送达 / 邀请码是否生效
- 太热：考虑限流 / 排队 / 临时关注册

## T+1 小时：值班轮换

- 第一班值班可下线（保持随时可叫）
- 第二班接管
- Grafana / 工单 / 告警群焦点不变

## T+24 小时：第一次复盘

要素：
- 实际 vs 预期（注册 / 调用 / 退款 / 客服）
- P0 / P1 事件清单
- 用户反馈 Top 5（好评 + 差评）
- 决策：继续 / 暂停 / 回滚？
- 改进项 + owner

## 紧急处置预案

### 流量超出预期 5 倍

```bash
# 1. 立刻扩容（Ansible 一键加 2 个网关）
ansible-playbook -i inventories/production.yml playbooks/scale-up.yml -e "count=2"

# 2. 启用排队模式（让请求排队，避免雪崩）
deploy/risk-control/scripts/enable-queue.sh --rate 100

# 3. 提升缓存命中（更激进 TTL）
deploy/cost-cache/scripts/aggressive-mode.sh

# 4. 公告：流量超预期，正在扩容，请耐心等待
```

### 上游突发限流

```bash
# 1. 提升备用分组优先级
deploy/scripts/route-override.sh --from official --to claude-oauth

# 2. 启用阶梯降级（小模型替代）
deploy/sidecar/scripts/enable-fallback.sh

# 3. 公告：上游临时限流，已切换备用线路
```

### 客服爆单

```bash
# 1. 启用 AI 客服一线（让 GPT-4 自动回常见问题）
deploy/customer-ops/scripts/ai-frontline.sh on

# 2. 临时召回外包
# 3. 把"邀请码注册"暂停，避免新用户继续涌入

# 4. 公告：因咨询量大，工单可能延迟，请见谅
```

### 出现 P0 事故

按 [`dr/`](../dr/) 对应 runbook 执行。

不要犹豫**立即回滚**比"边修边查"安全。

## 24 小时后

- 写当日复盘报告（即使一切顺利）
- 决定：继续观察 / 进入下一阶段 / 暂停修复
- 给所有团队成员发感谢
- 用户群发"上线 24h 阶段性总结"

---

## 心态贴士

- **当天不要做新功能**：只稳定，不新增
- **当天不要做配置变更**：除非紧急
- **当天不要在生产做数据库 schema 变更**：除非紧急
- **不慌**：99% 的意外都是已知问题，按 runbook 来
- **诚实**：出问题马上发公告，比沉默好十倍

> "上线那天最大的风险，是过度自信和过度紧张。
> 该干啥干啥，按 runbook 走，留好回滚路径。"
