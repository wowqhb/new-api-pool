# 模型清单与价格

> 价格按"计费倍率"展示。最终价格 = 上游官方价 × 模型倍率 × 用户分组倍率。
> 实时价格请以 [{{pricing_url}}] 为准（每周自动同步）。

## 用户分组倍率

| 分组 | 倍率 | 适用 |
|---|---|---|
| free | 0.5 | 免费试用 / 学生 |
| default | 1.0 | 普通付费用户 |
| vip | 1.3 | 高优官方通道 |

## 价格表（2026-Q2 参考）

### OpenAI 系列

| 模型 | Context | 输入价 ($/1M) | 输出价 ($/1M) | 备注 |
|---|---|---|---|---|
| gpt-4o | 128K | 2.50 | 10.00 | 默认 |
| gpt-4o-mini | 128K | 0.15 | 0.60 | 性价比首选 |
| gpt-4-turbo | 128K | 10.00 | 30.00 | 老款 |
| gpt-3.5-turbo | 16K | 0.50 | 1.50 | 仅向后兼容 |
| o1-preview | 128K | 15.00 | 60.00 | reasoning 强但慢 |
| o1-mini | 128K | 3.00 | 12.00 | reasoning |
| o3-mini | 128K | 1.10 | 4.40 | 最新 |

### Anthropic Claude 系列

| 模型 | Context | 输入价 ($/1M) | 输出价 ($/1M) | 备注 |
|---|---|---|---|---|
| claude-sonnet-4-5 | 200K | 3.00 | 15.00 | 推荐默认 |
| claude-opus-4-5 | 200K | 15.00 | 75.00 | 复杂任务 |
| claude-haiku-4-5 | 200K | 0.25 | 1.25 | 快速 |
| claude-3-5-sonnet | 200K | 3.00 | 15.00 | 老版 |
| claude-3-5-haiku | 200K | 0.80 | 4.00 | 老版 |

### Google Gemini

| 模型 | Context | 输入价 ($/1M) | 输出价 ($/1M) | 备注 |
|---|---|---|---|---|
| gemini-2.0-flash | 1M | 0.075 | 0.30 | 性价比 |
| gemini-2.0-flash-lite | 1M | 0.0375 | 0.15 | 极便宜 |
| gemini-1.5-pro | 2M | 1.25 | 5.00 | 长上下文 |
| gemini-1.5-flash | 1M | 0.075 | 0.30 | 平衡 |

### DeepSeek（国产）

| 模型 | Context | 输入 ($/1M) | 输出 ($/1M) | 备注 |
|---|---|---|---|---|
| deepseek-chat | 128K | 0.14 | 0.28 | 极便宜 |
| deepseek-reasoner | 64K | 0.55 | 2.19 | reasoning |

### 阿里 Qwen

| 模型 | Context | 输入 ($/1M) | 输出 ($/1M) | 备注 |
|---|---|---|---|---|
| qwen-max | 32K | 1.40 | 5.60 | 旗舰 |
| qwen-plus | 32K | 0.40 | 1.20 | 平衡 |
| qwen-turbo | 8K | 0.05 | 0.20 | 快速 |

## Embedding 价格

| 模型 | 维度 | 价格 ($/1M tokens) |
|---|---|---|
| text-embedding-3-small | 1536 | 0.02 |
| text-embedding-3-large | 3072 | 0.13 |
| text-embedding-ada-002 | 1536 | 0.10 |
| voyage-3-large | 1024 | 0.18 |
| gemini-embedding-001 | 768 | 0.025 |

## 图像 / 多模态

| 模型 | 输入图片 | 输入文 | 输出文 |
|---|---|---|---|
| gpt-4o-vision | 计入 token | 2.50/1M | 10.00/1M |
| claude-sonnet-4-5 vision | 计入 token | 3.00/1M | 15.00/1M |
| gemini-1.5-pro vision | 0.0026/张 + token | 1.25/1M | 5.00/1M |

## 选择建议

| 场景 | 推荐 | 备注 |
|---|---|---|
| 通用聊天 | gemini-2.0-flash | 又快又便宜 |
| 复杂推理 | claude-sonnet-4-5 / o3-mini | 平衡价格 / 质量 |
| 长文档总结 | gemini-1.5-pro | 2M 上下文 |
| 代码生成 | claude-sonnet-4-5 / gpt-4o | 实测 Claude 略好 |
| 中文 | qwen-plus / deepseek-chat | 国产理解中文好 |
| 极便宜批处理 | deepseek-chat / gemini-flash-lite | <$0.5/1M |
| 翻译 | gemini-2.0-flash | 大上下文一次过 |

## 模型生命周期

- **新模型**：上线后 7 天内为"灰度"，可能不稳定
- **deprecated**：会提前 90 天公告，建议尽快迁移
- **EOL**：到期后请求自动重定向到推荐替代模型，**也会同时通知**

历史版本见 [`changelog/models.md`](./changelog/models.md)。
