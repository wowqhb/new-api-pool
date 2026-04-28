// Pool Management — 巡检引擎 + Telegram 推送
//
// 设计：
//  - RunPoolHealthCheck: 同步执行一轮巡检，检查渠道、上游账号余额、失败率
//  - StartPoolHealthCron: 后台 cron，每 N 分钟触发一次（在 main.go 启动）
//  - SendTelegramMessage: 给 Telegram bot API 发文本
//  - NotifyExternalRecipeWorker: 触发外部 worker 的 webhook（自动注册 Recipe）

package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/model"
)

// 防止并发巡检
var poolHealthMu sync.Mutex

// RunPoolHealthCheck 执行一轮巡检
// trigger: "manual" / "cron"
func RunPoolHealthCheck(trigger string) {
	if !poolHealthMu.TryLock() {
		common.SysLog("[pool-health] previous check still running, skip")
		return
	}
	defer poolHealthMu.Unlock()

	startedAt := time.Now()
	common.SysLog(fmt.Sprintf("[pool-health] start (trigger=%s)", trigger))

	var alerts []*model.PoolAlertHistory

	// ── 1. 渠道禁用检查 ───────────────────
	var disabledChannels []model.Channel
	model.DB.Model(&model.Channel{}).
		Where("status <> ?", common.ChannelStatusEnabled).
		Limit(50).
		Find(&disabledChannels)
	for _, ch := range disabledChannels {
		alerts = append(alerts, &model.PoolAlertHistory{
			RuleKey:    "channel_down",
			Severity:   model.PoolAlertSeverityWarning,
			Title:      fmt.Sprintf("渠道 #%d 处于非启用状态", ch.Id),
			Message:    fmt.Sprintf("渠道 [%s] (id=%d) status=%d", ch.Name, ch.Id, ch.Status),
			TargetType: "channel",
			TargetId:   ch.Id,
		})
	}

	// ── 2. 失败率告警 ───────────────────
	now := time.Now()
	tenMinAgo := now.Add(-10 * time.Minute).Unix()
	var recentReq, recentFail int64
	model.LOG_DB.Model(&model.Log{}).
		Where("created_at >= ? AND type = ?", tenMinAgo, model.LogTypeConsume).
		Count(&recentReq)
	model.LOG_DB.Model(&model.Log{}).
		Where("created_at >= ? AND type = ?", tenMinAgo, model.LogTypeError).
		Count(&recentFail)
	if recentReq > 50 { // 最近 10 分钟超 50 单才参与计算，避免抖动
		failRate := float64(recentFail) / float64(recentReq) * 100
		threshold, _ := strconv.ParseFloat(common.OptionMap["PoolFailRateAlertThreshold"], 64)
		if threshold == 0 {
			threshold = 10 // 默认 10%
		}
		if failRate >= threshold {
			alerts = append(alerts, &model.PoolAlertHistory{
				RuleKey:    "fail_rate_high",
				Severity:   model.PoolAlertSeverityCritical,
				Title:      fmt.Sprintf("最近 10 分钟失败率 %.2f%% 超过阈值 %.2f%%", failRate, threshold),
				Message:    fmt.Sprintf("requests=%d, failures=%d", recentReq, recentFail),
				TargetType: "system",
			})
		}
	}

	// ── 3. 上游账号到期检查 ───────────────────
	soonTs := now.AddDate(0, 0, 7).Unix() // 7 天内到期
	var expiringAccounts []model.PoolAccount
	model.DB.Model(&model.PoolAccount{}).
		Where("expire_at > 0 AND expire_at <= ? AND status = ?", soonTs, model.PoolAccountStatusActive).
		Limit(50).
		Find(&expiringAccounts)
	for _, a := range expiringAccounts {
		days := (a.ExpireAt - now.Unix()) / 86400
		alerts = append(alerts, &model.PoolAlertHistory{
			RuleKey:    "account_expiring",
			Severity:   model.PoolAlertSeverityWarning,
			Title:      fmt.Sprintf("上游账号 %s 将在 %d 天后过期", a.Name, days),
			Message:    fmt.Sprintf("provider=%s, type=%s", a.Provider, a.AccountType),
			TargetType: "pool_account",
			TargetId:   a.Id,
		})
	}

	// ── 4. 上游账号低余额 ───────────────────
	balanceThreshold, _ := strconv.ParseFloat(common.OptionMap["PoolBalanceAlertUSD"], 64)
	if balanceThreshold == 0 {
		balanceThreshold = 5.0 // 默认 5 USD
	}
	var lowBalanceAccounts []model.PoolAccount
	model.DB.Model(&model.PoolAccount{}).
		Where("balance_usd > 0 AND balance_usd < ? AND status = ?", balanceThreshold, model.PoolAccountStatusActive).
		Limit(50).
		Find(&lowBalanceAccounts)
	for _, a := range lowBalanceAccounts {
		alerts = append(alerts, &model.PoolAlertHistory{
			RuleKey:    "balance_low",
			Severity:   model.PoolAlertSeverityWarning,
			Title:      fmt.Sprintf("上游账号 %s 余额低于 $%.2f", a.Name, balanceThreshold),
			Message:    fmt.Sprintf("当前余额 $%.4f", a.BalanceUSD),
			TargetType: "pool_account",
			TargetId:   a.Id,
		})
	}

	// ── 写入告警历史 + 推送 Telegram ───────────────────
	persisted := 0
	for _, a := range alerts {
		// 去重：30 分钟内相同 (rule_key + target_type + target_id) 不重复推送
		var dup int64
		model.DB.Model(&model.PoolAlertHistory{}).
			Where("rule_key = ? AND target_type = ? AND target_id = ? AND created_time >= ?",
				a.RuleKey, a.TargetType, a.TargetId, now.Add(-30*time.Minute).Unix()).
			Count(&dup)
		if dup > 0 {
			continue
		}
		if err := a.Insert(); err != nil {
			common.SysLog("[pool-health] insert alert failed: " + err.Error())
			continue
		}
		persisted++
		go pushAlertToTelegram(a)
	}

	common.SysLog(fmt.Sprintf("[pool-health] done in %s, alerts=%d (new=%d)",
		time.Since(startedAt), len(alerts), persisted))
}

// StartPoolHealthCron 启动后台巡检任务（main.go 调用）
func StartPoolHealthCron(ctx context.Context) {
	intervalMin, _ := strconv.Atoi(common.OptionMap["PoolHealthCheckInterval"])
	if intervalMin <= 0 {
		intervalMin = 5
	}
	ticker := time.NewTicker(time.Duration(intervalMin) * time.Minute)
	common.SysLog(fmt.Sprintf("[pool-health] cron started, interval=%dm", intervalMin))

	go func() {
		// 启动 30 秒后跑首次（避免和 db migrate 抢资源）
		select {
		case <-ctx.Done():
			return
		case <-time.After(30 * time.Second):
		}
		RunPoolHealthCheck("cron")
		for {
			select {
			case <-ctx.Done():
				ticker.Stop()
				common.SysLog("[pool-health] cron stopped")
				return
			case <-ticker.C:
				RunPoolHealthCheck("cron")
			}
		}
	}()
}

// pushAlertToTelegram 单条告警推送
func pushAlertToTelegram(a *model.PoolAlertHistory) {
	token := common.OptionMap["PoolTelegramBotToken"]
	chatId := common.OptionMap["PoolTelegramChatId"]
	if token == "" || chatId == "" {
		return
	}
	emoji := "ℹ️"
	switch a.Severity {
	case model.PoolAlertSeverityWarning:
		emoji = "⚠️"
	case model.PoolAlertSeverityCritical:
		emoji = "🚨"
	}
	msg := fmt.Sprintf("%s *new-api 号池告警*\n*[%s]* %s\n%s",
		emoji, a.Severity, a.Title, a.Message)
	if err := SendTelegramMessage(token, chatId, msg); err != nil {
		common.SysLog("[pool-health] telegram push failed: " + err.Error())
	}
}

// SendTelegramMessage 调用 Telegram Bot API 发送 markdown 文本
// 失败时返回带使用引导的中文错误，常见 case:
//   - chat not found: 用户从未与 Bot 对话过，需先在 Telegram 中给 Bot 发 /start
//   - Unauthorized: Token 错误
//   - Forbidden: 用户已 block bot
func SendTelegramMessage(token, chatId, text string) error {
	endpoint := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", token)
	body := url.Values{}
	body.Set("chat_id", chatId)
	body.Set("text", text)
	// 不强制 markdown：避免对一般文本做转义校验失败
	// body.Set("parse_mode", "Markdown")

	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewBufferString(body.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	cli := &http.Client{Timeout: 10 * time.Second}
	resp, err := cli.Do(req)
	if err != nil {
		return fmt.Errorf("网络错误：%s（请检查服务器是否可访问 api.telegram.org）", err.Error())
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		var parsed struct {
			Description string `json:"description"`
			ErrorCode   int    `json:"error_code"`
		}
		_ = json.Unmarshal(raw, &parsed)
		desc := parsed.Description
		if desc == "" {
			desc = string(raw)
		}
		// 友好化常见错误
		hint := ""
		switch {
		case strings.Contains(desc, "chat not found"):
			hint = "原因：Bot 还不知道这个 Chat ID。请在 Telegram 中搜索你的 Bot（@xxx_bot）→ 点开 Start，然后再点这里测试。"
		case strings.Contains(desc, "Unauthorized"):
			hint = "原因：Bot Token 无效，请检查是否复制完整。"
		case strings.Contains(desc, "Forbidden"):
			hint = "原因：用户已屏蔽 Bot 或没有发起过对话。"
		case strings.Contains(desc, "bot was blocked"):
			hint = "原因：用户已屏蔽该 Bot，请重新启用。"
		}
		if hint != "" {
			return fmt.Errorf("Telegram 拒绝：%s\n%s", desc, hint)
		}
		return fmt.Errorf("Telegram 拒绝：%s (HTTP %d)", desc, resp.StatusCode)
	}
	return nil
}

// NotifyExternalRecipeWorker 通知外部 worker 执行注册任务
// stub：仅 POST job 元数据到 webhook，外部 worker 自行处理 + 异步回调
// 外部服务未启动时会失败，但任务仍保留为 pending，可重试。
func NotifyExternalRecipeWorker(r *model.PoolRecipe, job *model.PoolJob) {
	if r.WebhookURL == "" {
		return
	}
	payload := map[string]any{
		"job_id":     job.Id,
		"recipe_key": r.Key,
		"provider":   r.Provider,
		"version":    r.Version,
		"params":     job.ParamsJSON,
		"config":     r.ConfigJSON,
		"callback_url": fmt.Sprintf("%s/api/pool/jobs/%d/callback?token=%s",
			common.OptionMap["ServerAddress"],
			job.Id,
			common.OptionMap["PoolWorkerSharedToken"]),
	}
	b, _ := json.Marshal(payload)
	cli := &http.Client{Timeout: 10 * time.Second}
	resp, err := cli.Post(r.WebhookURL, "application/json", bytes.NewBuffer(b))
	if err != nil {
		_ = job.UpdateStatus(model.PoolJobStatusFailed, "", "notify worker failed: "+err.Error())
		common.SysLog("[pool-recipe] notify worker failed: " + err.Error())
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		_ = job.UpdateStatus(model.PoolJobStatusFailed, "", fmt.Sprintf("worker http %d: %s", resp.StatusCode, string(body)))
		return
	}
	_ = job.UpdateStatus(model.PoolJobStatusRunning, "", "")
}
