# 上线 Checklist 与灰度 SOP

> 这是**最后一道关**。这一章不全则不许上线。

## 上线四阶段

```mermaid
flowchart LR
    Build[构建期 - 完成所有模块] --> P1
    P1[P1 内测 1周 5人] --> P2[P2 白名单 2周 50人]
    P2 --> P3[P3 邀请码 4周 500人]
    P3 --> P4[P4 公开]

    P1 -.|不达标| Halt1[修复后重测]
    P2 -.|不达标| P1
    P3 -.|不达标| P2
    P4 -.|事故| Rollback[紧急回滚]
```

每阶段定**晋级标准**和**回滚条件**，一个不过就停在原阶段。

## 文件

- [`pre-launch-checklist.md`](./pre-launch-checklist.md) 上线前 100+ 项检查
- [`gray-release-sop.md`](./gray-release-sop.md) 灰度发布 SOP（4 阶段）
- [`runbook-launch-day.md`](./runbook-launch-day.md) 上线当天值班手册
- [`go-no-go.md`](./go-no-go.md) Go/No-Go 决策模板
- [`post-launch-7day.md`](./post-launch-7day.md) 上线后 7 天巡检

## 决策门

每阶段晋级要 4 方签字：
- 技术负责人（CTO / Tech Lead）
- 运营负责人
- 财务（涉及计费）
- 法务（涉及合规）

任一 No-Go 就回到上一阶段。
