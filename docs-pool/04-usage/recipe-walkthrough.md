# 各内置 Recipe 人工注册指引

> 19 个内置剧本均为半自动 (`ManualMode=true`)：UI 给步骤、用户线下完成、回填 Key。本文是给运营 / 老板看的"手把手注册手册"。

剧本完整源数据见 `model/pool_recipe.go::buildDefaultRecipeSeeds()`。

按推荐度分组：

---

## ⭐ 第一波（5 分钟即可，无需信用卡）

### 1. Google AI Studio (免费 Gemini)

- Provider：gemini · Channel Type：24 · BaseURL：`https://generativelanguage.googleapis.com`
- 文档：<https://aistudio.google.com/app/apikey>
- 必备：Google 账号（Gmail）+ 非中国大陆 IP（机场 / VPN）
- 默认模型：`gemini-2.5-pro,gemini-2.5-flash,gemini-2.5-flash-lite,gemini-2.0-flash,gemini-1.5-pro,...,text-embedding-004`
- 步骤：
  1. 翻墙打开 <https://aistudio.google.com/app/apikey>
  2. 登录 Google 账号（首次同意条款）
  3. 蓝色按钮「Create API key」→「Create API key in new project」
  4. 复制弹窗里 `AIza...` 开头的 39 字符 Key
  5. 后台「自动注册」→ 找到该剧本 → 入队 → 录入结果，粘贴

### 2. Groq Cloud (免费 Llama / Mixtral)

- Provider：groq · Channel Type：1（OpenAI 兼容）· BaseURL：`https://api.groq.com/openai/v1`
- 文档：<https://console.groq.com/keys>
- 必备：GitHub 或 Google 账号
- 默认模型：Llama-3.3-70B-versatile / Llama-3.1-8B / Mixtral-8x7B / Gemma2-9B / Whisper / DeepSeek-R1-Distill
- 免费额度：30 RPM / 14400 RPD
- 步骤：
  1. <https://console.groq.com/login> → Continue with GitHub（最快）
  2. 进 console → 左侧 API Keys → Create API Key → 起名
  3. 弹窗仅显示一次，立刻复制 `gsk_...` 56 字符
  4. 录入

### 3. Cerebras Inference (免费 Llama 超快)

- Provider：cerebras · Channel Type：1 · BaseURL：`https://api.cerebras.ai/v1`
- 文档：<https://cloud.cerebras.ai/platform>
- 必备：GitHub / Google 账号
- 模型：`llama3.1-8b,llama-3.3-70b,llama-4-scout-17b-16e-instruct,qwen-3-32b`
- 免费、超低延迟（~2200 tok/s 70B）
- 步骤：Sign in with Google → Platform → API Keys → Generate → 复制 `csk-...` 56 字符 → 录入

> ⚠️ 中国大陆 IP 注册时 reCAPTCHA 可能 timeout（gstatic.com 被墙）。建议挂梯子。

### 4. DeepSeek Platform (国内便宜)

- Provider：deepseek · Channel Type：43 · BaseURL：`https://api.deepseek.com`
- 文档：<https://platform.deepseek.com/api_keys>
- 必备：国内手机号 + ¥1 充值
- 模型：`deepseek-chat,deepseek-reasoner`
- 步骤：注册 → 实名 → 充值 ≥ ¥1 → API Keys → Create → 录入 `sk-...`

### 5. SiliconFlow (硅基流动)

- Provider：siliconflow · Channel Type：40 · BaseURL：`https://api.siliconflow.cn`
- 文档：<https://cloud.siliconflow.cn/account/ak>
- 必备：国内手机号
- 新用户送 ¥14 体验金，部分模型有免费层
- 模型：DeepSeek-V3 / R1, Qwen2.5-72B / Coder-32B / QwQ, GLM-4-9B, Llama-3.1, BAAI/bge-m3
- 步骤：注册（送 14 元）→ 账户管理 → API 密钥 → 新建 → 复制

---

## 国内（手机号实名）

### 6. Moonshot (Kimi)

- Provider：moonshot · Channel Type：25 · BaseURL：`https://api.moonshot.cn`
- 必备：国内手机号
- 模型：`moonshot-v1-8k/32k/128k, kimi-k2-0905-preview, kimi-latest`
- 新用户送 ¥15
- 步骤：<https://platform.moonshot.cn/> → 注册 → API Key 管理 → 新建 → 录入 `sk-...` 51 字符

### 7. 智谱 GLM

- Provider：zhipu · Channel Type：26 · BaseURL：`https://open.bigmodel.cn`
- 必备：国内手机号 / 实名（拿免费额度）
- 模型：`glm-4-plus,glm-4,glm-4-air,glm-4-flash,glm-4v-plus,glm-z1-air`
- GLM-4-Flash 实名后免费
- 步骤：<https://open.bigmodel.cn/> → 注册 + 实名 → API Keys → 添加 → 录入 `{id}.{secret}`

### 8. 阿里 DashScope (通义)

- Provider：ali · Channel Type：17 · BaseURL：`https://dashscope.aliyuncs.com`
- 必备：阿里云账号 + 实名
- 模型：`qwen-max/plus/turbo/long, qwen2.5-72b/coder-32b, qwen-vl-plus/max`
- 多模型有免费额度
- 步骤：登录阿里云 → DashScope → 开通服务 → API-KEY 管理 → 创建 → 录入 `sk-...` 32 字符

### 9. MiniMax

- Provider：minimax · Channel Type：35 · BaseURL：`https://api.minimax.chat`
- 必备：国内手机号 + 实名
- 模型：`abab6.5s/g/t-chat, minimax-m1`
- 实名送 50 万 tokens 体验
- 步骤：<https://www.minimaxi.com/> → 注册 + 实名 → 接口密钥 → 新建 → 录入（长 JWT token）

---

## OAuth（订阅型，已有就 30 秒）

### 10. OpenAI Codex CLI (OAuth)

- Provider：openai · Channel Type：57 · BaseURL：留空
- 必备：ChatGPT Plus / Team / Enterprise 订阅 + Node.js
- 模型：`gpt-5,gpt-5-mini,gpt-5-codex,o3,o4-mini,gpt-4o,gpt-4o-mini`
- 不消耗 API 额度，走订阅授权
- 步骤：
  ```
  npm i -g @openai/codex
  codex auth login   # 会拉浏览器 OAuth
  cat ~/.codex/auth.json   # 拿 refresh_token
  ```
  录入 `refresh_token` 字段（粘贴整个 token 字符串）。系统会自动 refresh access_token。

### 11. Claude Pro / Max OAuth

- Provider：claude · Channel Type：14 · BaseURL：`https://api.anthropic.com`
- 必备：Claude Pro 或 Max 订阅 + claude-code CLI
- 模型：Claude-Sonnet-4.5 / Opus-4.5 / 3.7-Sonnet / 3.5-Haiku
- 步骤：
  ```
  npm i -g @anthropic-ai/claude-code
  claude /login           # 浏览器授权
  cat ~/.claude/credentials.json | grep oat01    # 拿 sk-ant-oat01-...
  ```
  录入这个 token。

---

## 海外付费 / 强反爬（必须手动）

### 12. OpenAI Platform API

- Provider：openai · Channel Type：1 · BaseURL：`https://api.openai.com`
- ⚠️ 实测：Cloudflare Turnstile + 设备指纹，自动化必败。
- 必备：**住宅 IP（机房 IP 必失败）** + 海外手机号 + Visa/Mastercard
- 模型：`gpt-5/-mini/-nano, gpt-4o/-mini, o4-mini/o3/o3-mini, gpt-4-turbo, gpt-3.5-turbo, text-embedding-3-...`
- 步骤：
  1. 住宅 IP 打开 <https://platform.openai.com/signup>
  2. 邮箱注册并验证 → 海外手机号 OTP
  3. Settings → Billing → Add Payment Method → 充值 $5 解锁 GPT-4
  4. API Keys → Create new secret key → 复制 `sk-...` 或 `sk-proj-...`

### 13. Anthropic Console API

- Provider：claude · Channel Type：14 · BaseURL：`https://api.anthropic.com`
- ⚠️ 极强 Cloudflare 校验 + 信用卡验证
- 必备：住宅 IP + Visa/Mastercard
- 步骤：注册 + 手机 OTP → Plans & Billing 充 ≥ $5 → API Keys → Create Key → 录入 `sk-ant-api03-...` 95 字符

### 14. OpenRouter

- Provider：openrouter · Channel Type：20 · BaseURL：`https://openrouter.ai/api/v1`
- ⚠️ 自动化失败（Turnstile），手动 2 分钟。
- 模型：聚合 100+ 含若干免费（DeepSeek-R1:free / Llama-3.3-70b:free / Gemini-2.0-Flash:free 等）+ 付费 GPT-4o / Claude-3.5
- 步骤：邮箱/GitHub/Google 注册 → Keys → Create Key → 录入 `sk-or-v1-...` 73 字符

### 15. Together AI

- Provider：together · Channel Type：1 · BaseURL：`https://api.together.xyz/v1`
- ⚠️ 自动注册被 Cloudflare 拦
- 必备：邮箱
- 新用户赠 $1 + 部分模型免费
- 步骤：<https://api.together.xyz/signup> → 邮箱 → API Keys → Reveal → 录入 64 位 hex

### 16. Mistral La Plateforme

- Provider：mistral · Channel Type：42 · BaseURL：`https://api.mistral.ai`
- ⚠️ Cloudflare 校验
- 必备：邮箱（部分场景手机）
- 模型：`mistral-large/small-latest, codestral-latest, pixtral-large-latest, ministral-8b/3b-latest, mistral-embed`
- 步骤：注册 → API Keys → Create new key → 录入 32 字符

### 17. Cohere (Trial)

- Provider：cohere · Channel Type：34 · BaseURL：`https://api.cohere.ai`
- ⚠️ hCaptcha 拦自动化，手动 3 分钟
- 必备：邮箱
- 模型：`command-r-plus-08-2024, command-r-08-2024, embed-english-v3.0, rerank-english-v3.0` 等
- Trial Key 限速 20 RPM 但**免费**
- 步骤：注册 → API Keys → Trial Key 已生成 → 复制 → 录入 40 字符

### 18. xAI (Grok)

- Provider：xai · Channel Type：48 · BaseURL：`https://api.x.ai/v1`
- ⚠️ X.com 设备指纹严格
- 必备：有效 X.com（Twitter）账号 + 海外信用卡
- 新账号送 $25/月
- 模型：`grok-4, grok-4-fast, grok-3, grok-3-mini, grok-2-vision-1212`
- 步骤：<https://console.x.ai/> → X.com 账号登录 → Workspace → Billing 绑卡 → API Keys → Create → 录入 `xai-...` 88 字符

### 19. Google Vertex AI (Paid)

- Provider：gemini · Channel Type：41 · BaseURL：留空（用 GCP project + region）
- 必备：GCP 计费账号 + Service Account（roles/aiplatform.user）
- 模型：`gemini-2.5-pro/flash, gemini-1.5-pro/flash, imagen-3.0-generate-002`
- 步骤：
  1. GCP 启用 Vertex AI API
  2. IAM → 创建 Service Account → 授予 `roles/aiplatform.user`
  3. 下载 JSON Key
  4. 整个 JSON 文件粘进「录入结果」的 `key_raw` 字段

---

## 通用录入流程（所有 Recipe 都一样）

```
1. 后台「号池管理 → 自动注册」找到对应剧本
2. （首次）确认 Enabled 已勾上
3. 点「入队」→ 跳到「任务历史」tab → 看到 manual_pending 任务
4. 点该任务的「查看步骤」复习一遍
5. 线下按步骤拿到 Key
6. 回任务行，点「录入结果」
7. 填：
   - pool_account_name : 你给账号起的辨识名（如 openai-personal-2）
   - key_raw : 完整明文 Key（不要带空格）
   - balance_usd : 可选，$5
   - notes : 可选，例如 "billing card: visa-1234"
8. 提交。系统会：
   ✓ 写 pool_accounts 一条
   ✓ 自动建一个 channel.tag=pool-manual（用 Recipe.DefaultModels 填 Models, Group="default,<provider>"）
   ✓ pool_accounts.ChannelId 回填
   ✓ Job → success
9. 回「上游账号」页应能看到新行
10. 回 new-api 原生「渠道管理」页应能看到新渠道
11. 用 default 组的 user token 调一次该 model 验证路由通了
```

## 失败 / 重试

任务 status=failed → error_msg 字段说明原因。点「重试」可以把 status 重置为 pending（自动模式）或 manual_pending（半自动）。

> 半自动场景下"重试"通常没意义——账号已经在上游建了，直接录入 Key 即可。只有 typo 误录的场景才点重试。
