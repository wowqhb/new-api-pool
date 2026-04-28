# 用户数据请求处理 SOP

## 受理渠道

- 邮件：`privacy@example.com`（专用邮箱）
- 用户中心自助：账号设置 → 数据请求

## 请求类型与 SLA

| 类型 | SLA | 操作 |
|---|---|---|
| 查看 / 导出 | 30 天（GDPR） / 推荐 7 天 | `compliance/scripts/user-export.sh` |
| 修改 | 立刻 | UI 自助 |
| 删除（被遗忘）| 30 天 | `compliance/scripts/user-delete.sh` |
| 暂停处理 | 立刻 | 改 user.status |
| 反对 / 退订 | 立刻 | 改 user.preferences |

## 处理流程（删除请求）

### 1. 身份核实（防社工攻击）

- 必须从注册邮箱发请求
- 如有 2FA 已开，要 OTP 验证码
- 大额账户（消耗 > $1000）建议视频核身

### 2. 同意 30 天 buffer 期

回复用户：

> 我们已收到您的删除请求。账户将在 30 天后被永久删除。
> 期间您可以登录撤销请求。
> 30 天后，财务相关记录将根据法律要求保留 5-7 年（已匿名化），其它数据全部删除。

### 3. 立即软删除

```bash
bash compliance/scripts/user-delete.sh <user> --soft
```

效果：
- 账号封禁，不能登录
- 所有 token 禁用
- 余额清零（如有，邮件通知用户最后申请退款）

### 4. 30 天后硬删

cron 自动跑（`retention-clean.sh deleted-users`）：
- 用户邮箱/用户名匿名化
- 个人资料字段清空
- 调用日志已根据 90 天保留期清掉
- 财务记录保留但通过匿名化解绑

### 5. 完成回执

发邮件确认已删除，附时间戳和**删除证书**（含 case ID）：

```
Subject: 您的删除请求已完成 (Case #DEL-2026-04-27-001)

我们已于 2026-05-27 03:14:00 UTC 完成您账号 user@example.com 的删除请求。

已删除：
- 个人资料（用户名、邮箱、电话、地址）
- 已绑定的第三方账号
- 偏好设置和会话数据
- 90 天内的 API 调用日志（元数据）

按法律要求保留（已匿名化）：
- 财务交易记录（保留 7 年）
- 涉及法律诉讼的相关记录（如适用）

如有疑问请回复此邮件。
```

## 被拒绝的情况

依法可以拒绝（GDPR Art. 17(3)）：

- 法律义务保留（财务/税务）
- 公共利益
- 法律诉讼相关
- 言论自由

拒绝时要书面回复并说明法律依据。

## 监管机构通知

涉及数据泄漏 / 大规模事件，72h 内通知：

- EU: 用户所在国监管机构（如德国 BfDI、法国 CNIL）
- 中国：网信办
- 美国：FTC（涉及未成年人）

模板见 [`legal/breach-notification-template.md`](../legal/breach-notification-template.md)。

## 案件跟踪

每个请求一个 case ID（`DEL-YYYY-MM-DD-NNN`），记入 [`compliance/cases/`](./cases/)。

CSV 模板：

```csv
case_id,received_at,user_email,request_type,status,assigned_to,resolved_at,note
DEL-2026-04-27-001,2026-04-27 10:23,user@example.com,delete,resolved,@privacy_officer,2026-05-27,正常处理
```
