// Pool Worker — SMS Provider 抽象 + 几家接码服务实现
//
// 实现：
//   - smsActivateProvider : sms-activate.org（最主流付费接码，俄系，需 API key, ~$0.05-0.5/号）
//   - fivesimProvider     : 5sim.net（付费，俄系，~$0.06-1/号）
//   - onlineSimProvider   : online-sim.io 免费但极不稳定，绝大多数大厂封号段
//   - mockSmsProvider     : 用于测试，立刻返回 +0000000000 / code=123456
//
// ⚠️ 务实建议：
//   - 国内手机号实名服务 (DeepSeek / Kimi / 智谱 / SiliconFlow / MiniMax / DashScope) 基本没法跑，
//     付费接码也大概率被风控。这些 Recipe 保留 manual_mode=true。
//   - 海外手机号 (OpenAI / Anthropic / Mistral / xAI) 付费接码勉强 30-60% 成功率。
//
// 选择策略：根据 OptionMap["PoolSmsProvider"] 选择具体实现；为空时跳过 SMS 流程（runner 必须处理"无可用 SMS"的退路）。

package service

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/QuantumNous/new-api/common"
)

// SmsRequest 一次申请号码的句柄
type SmsRequest struct {
	Provider     string `json:"provider"`
	ActivationID string `json:"activation_id"` // 服务商内部订单号
	PhoneNumber  string `json:"phone_number"`  // E.164 格式（+xxxxxxxxxx）
	Country      string `json:"country"`
	Service      string `json:"service"` // 服务商内部服务码（go=Google, op=OpenAI 等）
}

// SmsProvider 接码服务接口
type SmsProvider interface {
	Name() string
	// GetNumber 申请一个号码
	GetNumber(country, service string) (*SmsRequest, error)
	// WaitCode 阻塞等 OTP，超时返回错误
	WaitCode(req *SmsRequest, timeout time.Duration) (string, error)
	// Release 释放号码（成功 / 失败都要调，避免余额扣费）
	Release(req *SmsRequest, success bool) error
	// Balance 当前账户余额（USD），不支持的 provider 返回 -1
	Balance() (float64, error)
}

var smsProviders = map[string]SmsProvider{}

func registerSmsProvider(p SmsProvider) {
	smsProviders[p.Name()] = p
}

func init() {
	registerSmsProvider(&smsActivateProvider{})
	registerSmsProvider(&fivesimProvider{})
	registerSmsProvider(&onlineSimProvider{})
	registerSmsProvider(&mockSmsProvider{})
}

// GetSmsProvider 选 provider；返回 nil 表示当前未配置或不可用
func GetSmsProvider() SmsProvider {
	common.OptionMapRWMutex.RLock()
	preferred := common.OptionMap["PoolSmsProvider"]
	common.OptionMapRWMutex.RUnlock()
	if preferred == "" {
		return nil
	}
	p, ok := smsProviders[preferred]
	if !ok {
		return nil
	}
	return p
}

// ListSmsProviders 给前端列出已实现的 provider key
func ListSmsProviders() []string {
	out := []string{}
	for k := range smsProviders {
		out = append(out, k)
	}
	return out
}

// smsApiKey 从 OptionMap 拿对应 provider 的 api key
func smsApiKey(provider string) string {
	common.OptionMapRWMutex.RLock()
	defer common.OptionMapRWMutex.RUnlock()
	switch provider {
	case "smsactivate":
		return common.OptionMap["PoolSmsActivateApiKey"]
	case "5sim":
		return common.OptionMap["PoolFivesimApiKey"]
	case "onlinesim":
		return common.OptionMap["PoolOnlineSimApiKey"]
	}
	return ""
}

// ─────────────────────── sms-activate.org ───────────────────────
// 文档：https://sms-activate.org/en/api2
// 服务码：go = Google, op = OpenAI(ChatGPT), tg = Telegram, fb = Facebook ...
// 国家码：0 = Russia, 22 = India, 14 = China, 187 = USA, 16 = UK ...

type smsActivateProvider struct{}

func (p *smsActivateProvider) Name() string { return "smsactivate" }

const smsActivateAPI = "https://api.sms-activate.org/stubs/handler_api.php"

func (p *smsActivateProvider) call(params url.Values) (string, error) {
	apiKey := smsApiKey(p.Name())
	if apiKey == "" {
		return "", fmt.Errorf("sms-activate: PoolSmsActivateApiKey 未配置")
	}
	params.Set("api_key", apiKey)
	resp, err := http.Get(smsActivateAPI + "?" + params.Encode())
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return string(b), nil
}

func (p *smsActivateProvider) GetNumber(country, service string) (*SmsRequest, error) {
	if service == "" {
		service = "ot" // any service
	}
	if country == "" {
		country = "0"
	}
	body, err := p.call(url.Values{
		"action":  {"getNumber"},
		"service": {service},
		"country": {country},
	})
	if err != nil {
		return nil, err
	}
	// 返回："ACCESS_NUMBER:ID:PHONE"
	if !strings.HasPrefix(body, "ACCESS_NUMBER") {
		return nil, fmt.Errorf("sms-activate getNumber: %s", body)
	}
	parts := strings.SplitN(body, ":", 3)
	if len(parts) != 3 {
		return nil, fmt.Errorf("sms-activate getNumber 格式异常: %s", body)
	}
	return &SmsRequest{
		Provider:     p.Name(),
		ActivationID: parts[1],
		PhoneNumber:  "+" + parts[2],
		Country:      country,
		Service:      service,
	}, nil
}

func (p *smsActivateProvider) WaitCode(req *SmsRequest, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		body, err := p.call(url.Values{
			"action": {"getStatus"},
			"id":     {req.ActivationID},
		})
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}
		// STATUS_OK:CODE / STATUS_WAIT_CODE / STATUS_CANCEL
		if strings.HasPrefix(body, "STATUS_OK:") {
			return strings.TrimPrefix(body, "STATUS_OK:"), nil
		}
		if strings.HasPrefix(body, "STATUS_WAIT_CODE") || strings.HasPrefix(body, "STATUS_WAIT_RETRY") {
			time.Sleep(5 * time.Second)
			continue
		}
		return "", fmt.Errorf("sms-activate wait: %s", body)
	}
	return "", fmt.Errorf("sms-activate 等待 OTP 超时")
}

func (p *smsActivateProvider) Release(req *SmsRequest, success bool) error {
	status := "8" // CANCEL
	if success {
		status = "6" // FINISH
	}
	_, err := p.call(url.Values{
		"action": {"setStatus"},
		"status": {status},
		"id":     {req.ActivationID},
	})
	return err
}

func (p *smsActivateProvider) Balance() (float64, error) {
	body, err := p.call(url.Values{"action": {"getBalance"}})
	if err != nil {
		return -1, err
	}
	if !strings.HasPrefix(body, "ACCESS_BALANCE:") {
		return -1, fmt.Errorf("sms-activate balance: %s", body)
	}
	v, err := strconv.ParseFloat(strings.TrimPrefix(body, "ACCESS_BALANCE:"), 64)
	if err != nil {
		return -1, err
	}
	return v, nil
}

// ─────────────────────── 5sim.net ───────────────────────
// 文档：https://docs.5sim.net/

type fivesimProvider struct{}

func (p *fivesimProvider) Name() string { return "5sim" }

const fivesimAPI = "https://5sim.net/v1"

func (p *fivesimProvider) doJSON(method, path string, out any) error {
	apiKey := smsApiKey(p.Name())
	if apiKey == "" {
		return fmt.Errorf("5sim: PoolFivesimApiKey 未配置")
	}
	req, err := http.NewRequest(method, fivesimAPI+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Accept", "application/json")
	resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("5sim %s %s: %d %s", method, path, resp.StatusCode, string(raw))
	}
	if out != nil {
		return json.NewDecoder(resp.Body).Decode(out)
	}
	return nil
}

func (p *fivesimProvider) GetNumber(country, service string) (*SmsRequest, error) {
	if country == "" {
		country = "any"
	}
	if service == "" {
		service = "any"
	}
	var data struct {
		ID    int64  `json:"id"`
		Phone string `json:"phone"`
	}
	if err := p.doJSON("GET", fmt.Sprintf("/user/buy/activation/%s/any/%s", country, service), &data); err != nil {
		return nil, err
	}
	return &SmsRequest{
		Provider:     p.Name(),
		ActivationID: strconv.FormatInt(data.ID, 10),
		PhoneNumber:  data.Phone,
		Country:      country,
		Service:      service,
	}, nil
}

func (p *fivesimProvider) WaitCode(req *SmsRequest, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		var data struct {
			Status string `json:"status"`
			SMS    []struct {
				Code string `json:"code"`
			} `json:"sms"`
		}
		err := p.doJSON("GET", "/user/check/"+req.ActivationID, &data)
		if err == nil {
			if len(data.SMS) > 0 && data.SMS[0].Code != "" {
				return data.SMS[0].Code, nil
			}
			if data.Status == "CANCELED" || data.Status == "TIMEOUT" {
				return "", fmt.Errorf("5sim status=%s", data.Status)
			}
		}
		time.Sleep(5 * time.Second)
	}
	return "", fmt.Errorf("5sim 等待 OTP 超时")
}

func (p *fivesimProvider) Release(req *SmsRequest, success bool) error {
	verb := "cancel"
	if success {
		verb = "finish"
	}
	return p.doJSON("GET", "/user/"+verb+"/"+req.ActivationID, nil)
}

func (p *fivesimProvider) Balance() (float64, error) {
	var data struct {
		Balance float64 `json:"balance"`
	}
	if err := p.doJSON("GET", "/user/profile", &data); err != nil {
		return -1, err
	}
	return data.Balance, nil
}

// ─────────────────────── online-sim.io ───────────────────────
// 免费层：少数公开号，被各大平台封到死，仅供框架完整性

type onlineSimProvider struct{}

func (p *onlineSimProvider) Name() string { return "onlinesim" }

func (p *onlineSimProvider) GetNumber(country, service string) (*SmsRequest, error) {
	return nil, fmt.Errorf("onlinesim 免费层在 2026 年事实不可用，请配置 sms-activate / 5sim 付费 API")
}
func (p *onlineSimProvider) WaitCode(req *SmsRequest, timeout time.Duration) (string, error) {
	return "", fmt.Errorf("onlinesim 不支持")
}
func (p *onlineSimProvider) Release(req *SmsRequest, success bool) error { return nil }
func (p *onlineSimProvider) Balance() (float64, error)                   { return -1, nil }

// ─────────────────────── mock provider（用于测试） ───────────────────────

type mockSmsProvider struct{}

func (p *mockSmsProvider) Name() string { return "mock" }

func (p *mockSmsProvider) GetNumber(country, service string) (*SmsRequest, error) {
	return &SmsRequest{
		Provider:     p.Name(),
		ActivationID: "mock-" + strconv.FormatInt(time.Now().UnixNano(), 10),
		PhoneNumber:  "+10000000000",
		Country:      country,
		Service:      service,
	}, nil
}

func (p *mockSmsProvider) WaitCode(req *SmsRequest, timeout time.Duration) (string, error) {
	time.Sleep(2 * time.Second)
	return "123456", nil
}

func (p *mockSmsProvider) Release(req *SmsRequest, success bool) error { return nil }
func (p *mockSmsProvider) Balance() (float64, error)                   { return 999.99, nil }
