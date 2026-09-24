// Pool Worker — 邮箱 Provider 抽象 + 多家临时邮箱实现
//
// 实现：
//   - mailTmProvider     : mail.tm（免费、稳定，但被部分大厂封域）
//   - oneSecMailProvider : 1secmail.com 兼容站（mailseven / vremailbox 等同协议）
//   - guerrillaProvider  : guerrillamail.com（兼容性最好的之一）
//
// 所有 provider 都返回统一的 EmailMailbox / EmailMessage，Runner 不需要关心后端。
//
// 选择策略：根据 OptionMap["PoolEmailProvider"] 选择具体实现；为空时按 mailtm → guerrilla → onesec 顺序尝试，
// 第一个能成功创建邮箱的胜出。

package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/QuantumNous/new-api/common"
)

// EmailMailbox 通用邮箱抽象
type EmailMailbox struct {
	Provider string `json:"provider"`
	Address  string `json:"address"`
	Password string `json:"password,omitempty"` // 仅部分 provider 有
	Token    string `json:"-"`                  // 内部 JWT / session
	State    string `json:"-"`                  // provider 私有状态（onesec: login@domain）
}

// EmailMessage 通用邮件抽象
type EmailMessage struct {
	From    string `json:"from"`
	Subject string `json:"subject"`
	Text    string `json:"text"`
	HTML    string `json:"html"`
}

// EmailProvider 临时邮箱后端接口
type EmailProvider interface {
	Name() string
	Create() (*EmailMailbox, error)
	Wait(box *EmailMailbox, senderContains, subjectContains string, timeout time.Duration) (*EmailMessage, error)
}

// providerRegistry 全局
var emailProviders = map[string]EmailProvider{}

func registerEmailProvider(p EmailProvider) {
	emailProviders[p.Name()] = p
}

func init() {
	registerEmailProvider(&mailTmProvider{})
	registerEmailProvider(&oneSecMailProvider{})
	registerEmailProvider(&guerrillaProvider{})
}

// GetEmailProvider 根据 OptionMap["PoolEmailProvider"] 选具体 provider
// 缺省 fallback 链：mailtm → guerrilla → 1secmail，第一个能创建邮箱的胜出
func GetEmailProvider() (EmailProvider, *EmailMailbox, error) {
	common.OptionMapRWMutex.RLock()
	preferred := common.OptionMap["PoolEmailProvider"]
	common.OptionMapRWMutex.RUnlock()

	tryOrder := []string{"mailtm", "guerrilla", "1secmail"}
	if preferred != "" {
		tryOrder = append([]string{preferred}, tryOrder...)
	}
	var lastErr error
	tried := map[string]bool{}
	for _, key := range tryOrder {
		if tried[key] {
			continue
		}
		tried[key] = true
		p, ok := emailProviders[key]
		if !ok {
			continue
		}
		box, err := p.Create()
		if err == nil {
			common.SysLog(fmt.Sprintf("[pool-email] using provider=%s address=%s", key, box.Address))
			return p, box, nil
		}
		lastErr = fmt.Errorf("[%s] %w", key, err)
		common.SysLog("[pool-email] " + lastErr.Error())
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("没有可用的邮箱 provider")
	}
	return nil, nil, lastErr
}

// ListEmailProviders 提供给前端
func ListEmailProviders() []string {
	out := []string{}
	for k := range emailProviders {
		out = append(out, k)
	}
	return out
}

// ─────────────────────── mail.tm provider ───────────────────────

type mailTmProvider struct{}

func (p *mailTmProvider) Name() string { return "mailtm" }

func (p *mailTmProvider) Create() (*EmailMailbox, error) {
	acc, err := CreateMailTmAccount()
	if err != nil {
		return nil, err
	}
	return &EmailMailbox{
		Provider: p.Name(),
		Address:  acc.Address,
		Password: acc.Password,
		Token:    acc.Token,
		State:    acc.ID,
	}, nil
}

func (p *mailTmProvider) Wait(box *EmailMailbox, senderContains, subjectContains string, timeout time.Duration) (*EmailMessage, error) {
	acc := &MailTmAccount{
		Address:  box.Address,
		Password: box.Password,
		Token:    box.Token,
		ID:       box.State,
	}
	msg, err := WaitForMessage(acc, senderContains, subjectContains, timeout)
	if err != nil {
		return nil, err
	}
	html := ""
	if len(msg.HTML) > 0 {
		html = strings.Join(msg.HTML, "\n")
	}
	return &EmailMessage{
		From:    msg.From.Address,
		Subject: msg.Subject,
		Text:    msg.Text,
		HTML:    html,
	}, nil
}

// ─────────────────────── 1secmail.com 兼容协议 ───────────────────────
// API: https://www.1secmail.com/api/v1/?action=getMessages&login=xxx&domain=xxx
// 注意：1secmail 在 2024 年关停过，可能需要替代域。本实现保留接口供未来兼容站点使用。

type oneSecMailProvider struct{}

func (p *oneSecMailProvider) Name() string { return "1secmail" }

func (p *oneSecMailProvider) Create() (*EmailMailbox, error) {
	domains := []string{"1secmail.com", "1secmail.org", "1secmail.net"}
	domain := domains[time.Now().UnixNano()%int64(len(domains))]
	login := mailTmRandLocalPart(10)
	addr := login + "@" + domain
	// 用 getMessages 试一下 API 是否还活着
	resp, err := http.Get(fmt.Sprintf(
		"https://www.1secmail.com/api/v1/?action=getMessages&login=%s&domain=%s",
		login, domain))
	if err != nil {
		return nil, fmt.Errorf("1secmail api unreachable: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("1secmail api %d", resp.StatusCode)
	}
	return &EmailMailbox{
		Provider: p.Name(),
		Address:  addr,
		State:    login + "|" + domain,
	}, nil
}

func (p *oneSecMailProvider) Wait(box *EmailMailbox, senderContains, subjectContains string, timeout time.Duration) (*EmailMessage, error) {
	parts := strings.SplitN(box.State, "|", 2)
	if len(parts) != 2 {
		return nil, fmt.Errorf("1secmail invalid state")
	}
	login, domain := parts[0], parts[1]
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		listURL := fmt.Sprintf("https://www.1secmail.com/api/v1/?action=getMessages&login=%s&domain=%s", login, domain)
		resp, err := http.Get(listURL)
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}
		var msgs []struct {
			ID      int    `json:"id"`
			From    string `json:"from"`
			Subject string `json:"subject"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&msgs)
		_ = resp.Body.Close()
		for _, m := range msgs {
			if senderContains != "" && !strings.Contains(strings.ToLower(m.From), strings.ToLower(senderContains)) {
				continue
			}
			if subjectContains != "" && !strings.Contains(strings.ToLower(m.Subject), strings.ToLower(subjectContains)) {
				continue
			}
			detailURL := fmt.Sprintf("https://www.1secmail.com/api/v1/?action=readMessage&login=%s&domain=%s&id=%d", login, domain, m.ID)
			r2, err := http.Get(detailURL)
			if err != nil {
				continue
			}
			var detail struct {
				From     string `json:"from"`
				Subject  string `json:"subject"`
				Body     string `json:"body"`
				HTMLBody string `json:"htmlBody"`
				TextBody string `json:"textBody"`
			}
			_ = json.NewDecoder(r2.Body).Decode(&detail)
			_ = r2.Body.Close()
			return &EmailMessage{
				From:    detail.From,
				Subject: detail.Subject,
				Text:    firstNonEmpty(detail.TextBody, detail.Body),
				HTML:    detail.HTMLBody,
			}, nil
		}
		time.Sleep(4 * time.Second)
	}
	return nil, fmt.Errorf("1secmail wait timeout")
}

// ─────────────────────── guerrillamail.com ───────────────────────
// API: https://api.guerrillamail.com/ajax.php
// 比 mail.tm / 1secmail 更老牌；很多 SaaS 把这个域加白名单（因为本身就被多人合法用）

type guerrillaProvider struct{}

func (p *guerrillaProvider) Name() string { return "guerrilla" }

const gmAPI = "https://api.guerrillamail.com/ajax.php"

func (p *guerrillaProvider) Create() (*EmailMailbox, error) {
	resp, err := http.Get(gmAPI + "?f=get_email_address&lang=en")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var data struct {
		EmailAddr string `json:"email_addr"`
		SidToken  string `json:"sid_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, err
	}
	if data.EmailAddr == "" {
		return nil, fmt.Errorf("guerrilla api empty email")
	}
	return &EmailMailbox{
		Provider: p.Name(),
		Address:  data.EmailAddr,
		Token:    data.SidToken,
	}, nil
}

func (p *guerrillaProvider) Wait(box *EmailMailbox, senderContains, subjectContains string, timeout time.Duration) (*EmailMessage, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		listURL := fmt.Sprintf("%s?f=get_email_list&offset=0&sid_token=%s", gmAPI, url.QueryEscape(box.Token))
		resp, err := http.Get(listURL)
		if err != nil {
			time.Sleep(5 * time.Second)
			continue
		}
		var data struct {
			List []struct {
				MailID      string `json:"mail_id"`
				MailFrom    string `json:"mail_from"`
				MailSubject string `json:"mail_subject"`
			} `json:"list"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&data)
		_ = resp.Body.Close()
		for _, m := range data.List {
			if senderContains != "" && !strings.Contains(strings.ToLower(m.MailFrom), strings.ToLower(senderContains)) {
				continue
			}
			if subjectContains != "" && !strings.Contains(strings.ToLower(m.MailSubject), strings.ToLower(subjectContains)) {
				continue
			}
			detailURL := fmt.Sprintf("%s?f=fetch_email&email_id=%s&sid_token=%s", gmAPI, m.MailID, url.QueryEscape(box.Token))
			r2, err := http.Get(detailURL)
			if err != nil {
				continue
			}
			var d struct {
				MailFrom    string `json:"mail_from"`
				MailSubject string `json:"mail_subject"`
				MailBody    string `json:"mail_body"`
			}
			_ = json.NewDecoder(r2.Body).Decode(&d)
			_ = r2.Body.Close()
			return &EmailMessage{
				From:    d.MailFrom,
				Subject: d.MailSubject,
				HTML:    d.MailBody,
				Text:    stripHTMLTags(d.MailBody),
			}, nil
		}
		time.Sleep(5 * time.Second)
	}
	return nil, fmt.Errorf("guerrilla wait timeout")
}

// ─────────────────────── helpers ───────────────────────

func firstNonEmpty(items ...string) string {
	for _, s := range items {
		if s != "" {
			return s
		}
	}
	return ""
}

func stripHTMLTags(s string) string {
	out := s
	for strings.Contains(out, "<") && strings.Contains(out, ">") {
		l := strings.Index(out, "<")
		r := strings.Index(out[l:], ">")
		if r < 0 {
			break
		}
		out = out[:l] + out[l+r+1:]
	}
	return out
}

// ExtractFirstURLFromEmail 通用邮件抽链接（用于 magic-link / verify URL）
func ExtractFirstURLFromEmail(m *EmailMessage, prefix string) string {
	corpus := m.Text + "\n" + m.HTML
	if corpus == "" {
		return ""
	}
	pl := strings.ToLower(prefix)
	cl := strings.ToLower(corpus)
	idx := strings.Index(cl, pl)
	if idx < 0 {
		return ""
	}
	end := idx
	for end < len(corpus) {
		c := corpus[end]
		if c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '"' || c == '\'' || c == '<' || c == '>' || c == ')' || c == ']' {
			break
		}
		end++
	}
	out := corpus[idx:end]
	// HTML 实体解码（最常见的）
	out = strings.ReplaceAll(out, "&amp;", "&")
	out = strings.ReplaceAll(out, "&#x2F;", "/")
	out = strings.ReplaceAll(out, "&#x3D;", "=")
	out = strings.ReplaceAll(out, "&#61;", "=")
	return out
}

// ExtractCodeFromEmail 通用 OTP 验证码抽取（4-8 位数字、字母数字混合）
func ExtractCodeFromEmail(m *EmailMessage, length int) string {
	if length <= 0 {
		length = 6
	}
	corpus := m.Text + "\n" + m.HTML
	if corpus == "" {
		return ""
	}
	// 简单状态机：找连续 length 个数字
	for i := 0; i+length <= len(corpus); i++ {
		ok := true
		for j := 0; j < length; j++ {
			c := corpus[i+j]
			if c < '0' || c > '9' {
				ok = false
				break
			}
		}
		if !ok {
			continue
		}
		// 前后必须不是数字（防止误匹配长 ID 中的子串）
		if i > 0 {
			prev := corpus[i-1]
			if prev >= '0' && prev <= '9' {
				continue
			}
		}
		if i+length < len(corpus) {
			next := corpus[i+length]
			if next >= '0' && next <= '9' {
				continue
			}
		}
		return corpus[i : i+length]
	}
	return ""
}
