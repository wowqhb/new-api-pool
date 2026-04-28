// Pool Worker — RecipeRunner 接口 + 注册表
//
// 每个全自动 Recipe 在这里登记一个 RecipeRunner 实现。
// Worker dispatcher 根据 Recipe.Key 找到对应 Runner 跑流程。
//
// ⚠️ 真实经验（2026-04 验证）：
//   - 主流大厂 SaaS（OpenAI / Anthropic / OpenRouter / Together / Cohere / Mistral）
//     均部署了 Cloudflare Turnstile + 设备指纹检测，chromedp 无法绕过，自动 Runner 几乎必败。
//   - 因此本仓库目前**不内置任何针对商业站点的全自动 Runner**，避免误导。
//   - 商业账号一律走「半自动模式」：UI 给步骤 + 文档链接 + 必备材料，用户线下完成
//     → 在 Pool 后台点「录入结果」回填 Key → 系统自动入号池 + 同步建 Channel。
//   - 如果你有打码服务 / 住宅代理 / 真实 SMS 池，再实现并 RegisterRunner() 进来。

package service

import (
	"context"
	"fmt"
	"sync"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/model"
)

// RecipeResult Runner 成功后填充的标准结果
type RecipeResult struct {
	AccountName string
	KeyRaw      string
	BalanceUSD  float64
	ExpireAt    int64 // unix sec, 0 = 永久
	Notes       string
}

// RecipeRunner 单个站点自动注册流程的执行器
type RecipeRunner interface {
	// Key 必须与 model.PoolRecipe.Key 一致
	Key() string
	// Description 给前端 / 日志展示
	Description() string
	// Run 执行注册流程，超时由 ctx 控制
	Run(ctx context.Context, recipe *model.PoolRecipe) (*RecipeResult, error)
}

// runnerRegistry 全局注册表
var (
	runnerRegistry   = map[string]RecipeRunner{}
	runnerRegistryMu sync.RWMutex
)

// RegisterRunner 在 init 阶段注册一个 Runner
func RegisterRunner(r RecipeRunner) {
	runnerRegistryMu.Lock()
	defer runnerRegistryMu.Unlock()
	runnerRegistry[r.Key()] = r
	common.SysLog(fmt.Sprintf("[pool-worker] runner registered: %s", r.Key()))
}

// GetRunner 查询一个 Runner（不存在返回 nil）
func GetRunner(key string) RecipeRunner {
	runnerRegistryMu.RLock()
	defer runnerRegistryMu.RUnlock()
	return runnerRegistry[key]
}

// ListRunnerKeys 当前已注册的全自动 Runner key 列表
func ListRunnerKeys() []string {
	runnerRegistryMu.RLock()
	defer runnerRegistryMu.RUnlock()
	out := make([]string, 0, len(runnerRegistry))
	for k := range runnerRegistry {
		out = append(out, k)
	}
	return out
}
