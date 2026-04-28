# 运营 SOP

号池"养"出来的，不是搭出来的。这一目录是日常 / 月度 / 季度的标准操作流程。

## 文件清单

| 文件 | 频率 | 责任人 |
|---|---|---|
| [`channel-onboarding.md`](./channel-onboarding.md) | 每次入池 | 运营 |
| [`channel-offboarding.md`](./channel-offboarding.md) | 每次离池 | 运营 |
| [`canary-release.md`](./canary-release.md) | 每次新分组上线 | 运营 + SRE |
| [`monthly-reconciliation.md`](./monthly-reconciliation.md) | 每月 1 号 | 财务 + 运营 |
| [`weekly-review.md`](./weekly-review.md) | 每周一 | 全员 |
| [`capacity-planning.md`](./capacity-planning.md) | 每周 | 运营 |
| [`incident-response.md`](./incident-response.md) | 故障时 | 值班 |
| [`oncall-rotation.md`](./oncall-rotation.md) | 每月排班 | 主管 |

## 黄金法则

1. **任何号池操作都要在 Wiki 留痕**（谁/何时/做了什么/为什么）
2. **新号必经灰度**，绝不直接进正式池
3. **故障第一动作是发公告**（5 分钟内），不是修
4. **每月演练一次**故障，不演练 = 不能用
