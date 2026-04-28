# GDPR 数据主体权利处理

GDPR 给用户 7 项核心权利：

| 权利 | 我们的实现 |
|---|---|
| Right to be informed | 隐私政策 + 注册时强制阅读 |
| Right of access | 用户中心"导出我的数据" |
| Right to rectification | 用户中心"修改信息" |
| Right to erasure (被遗忘权) | 用户中心"删除账户" |
| Right to restrict processing | 用户中心"暂停处理" |
| Right to data portability | 导出 JSON / CSV |
| Right to object | 退订营销邮件 |

## 用户侧入口（产品要做的）

用户登录后能看到：

```
账号设置
├── 个人信息（修改）
├── 数据导出（一键下载所有数据 JSON）
├── 隐私设置
│   ├── 是否记录调用日志（默认开）
│   ├── 是否参与产品改进（统计匿名化）
│   └── 是否接收营销邮件（默认关）
├── 暂停处理（不删但停止提供服务）
└── 删除账户（30 天 buffer 期）
```

实现脚本（admin 紧急执行用）：

```bash
# 用户要导出数据
bash compliance/scripts/user-export.sh <username|email>
# 输出 user-export-<id>-<timestamp>.zip （加密）

# 用户要删除账户
bash compliance/scripts/user-delete.sh <username|email>
# 立即匿名化，30 天后硬删
```

## 跨境传输

| 用户位置 | 数据存储位置 | 合规要求 |
|---|---|---|
| EU | EU 或 Adequacy Decision 国家 | SCCs 或 BCRs |
| 中国 | 中国境内（关键信息基础设施）| 网信办评估 |
| 其它 | 任意 | 隐私政策披露 |

如果服务器在美国但接 EU 用户，**必须签 SCCs（标准合同条款）**或用美国 EU-US Data Privacy Framework 认证厂商。

## DPO（数据保护官）

- 团队 < 250 人 + 不处理特殊类别数据：可不设
- 但建议指定一个**对外的 privacy@example.com**
- 隐私事件 72h 内必须通知监管机构（GDPR Art. 33）

## DPIA（数据保护影响评估）

涉及大规模处理特殊类别数据（健康/政治/宗教/性向），上线前必须做 DPIA。

AI 网关默认不做 → 在 ToS 里**明确禁止用户提交此类数据**，转嫁责任给用户。
