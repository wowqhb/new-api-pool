# 法务文档模板

> ⚠️ **最重要的免责声明**：本目录下所有文档都是**模板**，不是法律建议。
> 上线前必须找当地律师过一遍：管辖法院/争议解决/退款条款/数据合规细则都要按你的注册主体所在地定制。

## 推荐的最低法律文档集

| 文档 | 必备 | 受众 |
|---|---|---|
| 服务条款（Terms of Service）| ✅ | 所有用户，注册必勾 |
| 隐私政策（Privacy Policy）| ✅ | 所有用户，含 GDPR/CCPA/PIPL |
| 可接受使用政策（AUP）| ✅ | 所有用户 |
| 退款政策（Refund Policy）| ✅ | 付费用户 |
| Cookie 政策 | ⚠️ EU/UK/CA 用户必备 | 网站访客 |
| DPA（数据处理协议） | ⚠️ B2B 客户要求时 | 企业客户 |
| 未成年人禁入声明 | ✅ | 注册页 |

## 文件清单

- [`terms-of-service.md`](./terms-of-service.md) ToS 模板（中英）
- [`privacy-policy.md`](./privacy-policy.md) 隐私政策模板（中英）
- [`acceptable-use.md`](./acceptable-use.md) AUP 模板
- [`refund-policy.md`](./refund-policy.md) 退款政策模板
- [`cookie-policy.md`](./cookie-policy.md) Cookie 政策模板
- [`dmca.md`](./dmca.md) DMCA 通知模板
- [`takedown-process.md`](./takedown-process.md) 侵权下架流程

## 选择管辖法

| 注册主体 | 推荐管辖 | 理由 |
|---|---|---|
| 香港公司 | 香港法 | 与上游司法互通 |
| 新加坡公司 | 新加坡法 | 仲裁友好 |
| 美国 LLC | Delaware | 默认 |
| 开曼/BVI | 开曼/BVI | 离岸友好 |
| 国内主体 | 中国法 | 但需通过备案 |

> 💡 **不推荐**用"任何司法辖区均可"或"由我方决定"这种含糊条款 — 法庭多半判无效。

## 注册必勾选项

注册页面必须有不可缺勾选框，绑定到这些文档：

```html
<label>
  <input type="checkbox" required />
  我已年满 18 周岁，并阅读并同意
  <a href="/legal/terms" target="_blank">服务条款</a>、
  <a href="/legal/privacy" target="_blank">隐私政策</a>、
  <a href="/legal/aup" target="_blank">可接受使用政策</a>。
</label>
```

存证：注册时记录 `agreed_terms_version` 与 `agreed_at` 进 `users` 表。

## 版本管理

每次修改：
1. Bump version：`v1.2.3 → v1.3.0`
2. 老用户在登录时弹出"条款已更新"页，**必须重新勾选**才能继续使用
3. 旧版本归档到 `legal/archive/<version>/` 永久保留（应对历史用户索赔）

## 数据合规快查表

| 法域 | 关键义务 |
|---|---|
| **GDPR**（EU）| 用户访问/删除/导出权 + 60 天内响应 + DPO + 跨境传输保护（SCCs / TIA）|
| **CCPA**（加州）| Do Not Sell + 删除权 + 隐私政策披露列表 |
| **PIPL**（中国）| 单独同意 + 数据出境申报 + 独立第三方评估 |
| **COPPA**（美儿童）| 13 岁以下禁止收集 |

实施细节见 [`../compliance/`](../compliance/)。
