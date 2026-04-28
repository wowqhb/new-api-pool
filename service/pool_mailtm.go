// Pool Worker — 临时邮箱客户端 (mail.tm)
//
// mail.tm 是一个免费 disposable 邮箱 API（GDPR 合规、无需注册）。
// 用于自动注册场景接收激活/魔链邮件。
//
// 局限：mail.tm 的域被部分大厂封禁（OpenAI / Anthropic 都封）。
// 对中等门槛站点（OpenRouter / Together / Cohere / Mistral 等）目前可工作。
//
// 文档：https://docs.mail.tm/

package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"strings"
	"time"
)

const (
	mailTmAPI    = "https://api.mail.tm"
	mailTmPoll   = 3 * time.Second
	mailTmMaxLen = 5 * 60 * time.Second // 5 min 等单封邮件
)

// MailTmAccount 已创建的临时邮箱
type MailTmAccount struct {
	Address  string `json:"address"`
	Password string `json:"password"`
	Token    string `json:"-"` // 登录后 JWT
	ID       string `json:"id,omitempty"`
}

// MailTmMessage 邮件元数据 + 正文
type MailTmMessage struct {
	ID       string `json:"id"`
	From     struct {
		Address string `json:"address"`
		Name    string `json:"name"`
	} `json:"from"`
	Subject  string   `json:"subject"`
	Intro    string   `json:"intro"`
	Text     string   `json:"text"`
	HTML     []string `json:"html"`
	HasSeen  bool     `json:"seen"`
	CreateAt string   `json:"createdAt"`
}

// CreateMailTmAccount 申请一个新的临时邮箱
func CreateMailTmAccount() (*MailTmAccount, error) {
	// 1) 拿可用域
	domains, err := mailTmGetDomains()
	if err != nil {
		return nil, err
	}
	if len(domains) == 0 {
		return nil, fmt.Errorf("mail.tm 当前没有可用域")
	}
	domain := domains[0]

	// 2) 用 8 位随机本地名，固定密码模式
	local := mailTmRandLocalPart(10)
	pwd := mailTmRandLocalPart(16) + "Aa1!"
	address := local + "@" + domain

	// 3) 创建账号
	body, _ := json.Marshal(map[string]string{
		"address":  address,
		"password": pwd,
	})
	resp, err := mailTmDo("POST", "/accounts", body, "")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("mail.tm create %d: %s", resp.StatusCode, string(raw))
	}
	var created struct {
		ID      string `json:"id"`
		Address string `json:"address"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&created)

	// 4) 登录拿 JWT
	tokenBody, _ := json.Marshal(map[string]string{
		"address":  address,
		"password": pwd,
	})
	tResp, err := mailTmDo("POST", "/token", tokenBody, "")
	if err != nil {
		return nil, err
	}
	defer tResp.Body.Close()
	if tResp.StatusCode >= 300 {
		raw, _ := io.ReadAll(tResp.Body)
		return nil, fmt.Errorf("mail.tm token %d: %s", tResp.StatusCode, string(raw))
	}
	var tk struct {
		Token string `json:"token"`
	}
	_ = json.NewDecoder(tResp.Body).Decode(&tk)

	return &MailTmAccount{
		Address:  address,
		Password: pwd,
		Token:    tk.Token,
		ID:       created.ID,
	}, nil
}

// WaitForMessage 阻塞等待匹配 sender / subject 关键字的邮件
//   senderContains: 发件人地址子串（例如 "openrouter.ai"），传 "" 不过滤
//   subjectContains: 主题子串（例如 "verify"），传 "" 不过滤
//   timeout: 超时
//
// 返回首封匹配邮件（含正文）。
func WaitForMessage(acc *MailTmAccount, senderContains, subjectContains string, timeout time.Duration) (*MailTmMessage, error) {
	if timeout <= 0 {
		timeout = mailTmMaxLen
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		msgs, err := listMessages(acc)
		if err == nil {
			for _, m := range msgs {
				okSender := senderContains == "" ||
					strings.Contains(strings.ToLower(m.From.Address), strings.ToLower(senderContains))
				okSubject := subjectContains == "" ||
					strings.Contains(strings.ToLower(m.Subject), strings.ToLower(subjectContains))
				if !okSender || !okSubject {
					continue
				}
				// 拉完整正文
				full, err := fetchMessage(acc, m.ID)
				if err == nil {
					return full, nil
				}
			}
		}
		time.Sleep(mailTmPoll)
	}
	return nil, fmt.Errorf("mail.tm 等待邮件超时（%s, sender~%s subject~%s）",
		timeout, senderContains, subjectContains)
}

// ─────────────────────── helpers ───────────────────────

func mailTmGetDomains() ([]string, error) {
	resp, err := mailTmDo("GET", "/domains", nil, "")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var doc struct {
		Member []struct {
			Domain   string `json:"domain"`
			IsActive bool   `json:"isActive"`
		} `json:"hydra:member"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
		return nil, err
	}
	out := []string{}
	for _, m := range doc.Member {
		if m.IsActive {
			out = append(out, m.Domain)
		}
	}
	return out, nil
}

func listMessages(acc *MailTmAccount) ([]MailTmMessage, error) {
	resp, err := mailTmDo("GET", "/messages?page=1", nil, acc.Token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var doc struct {
		Member []MailTmMessage `json:"hydra:member"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
		return nil, err
	}
	return doc.Member, nil
}

func fetchMessage(acc *MailTmAccount, id string) (*MailTmMessage, error) {
	resp, err := mailTmDo("GET", "/messages/"+id, nil, acc.Token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("mail.tm fetch %d: %s", resp.StatusCode, string(raw))
	}
	var m MailTmMessage
	if err := json.NewDecoder(resp.Body).Decode(&m); err != nil {
		return nil, err
	}
	return &m, nil
}

func mailTmDo(method, path string, body []byte, token string) (*http.Response, error) {
	var rdr io.Reader
	if body != nil {
		rdr = bytes.NewBuffer(body)
	}
	req, err := http.NewRequest(method, mailTmAPI+path, rdr)
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", "application/ld+json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	cli := &http.Client{Timeout: 30 * time.Second}
	return cli.Do(req)
}

func mailTmRandLocalPart(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyz0123456789"
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[r.Intn(len(letters))]
	}
	return string(b)
}

// ExtractFirstURLFromMail 从 Text/HTML 邮件中找到第一个匹配前缀的链接（用于 magic-link / verify URL）
func ExtractFirstURLFromMail(m *MailTmMessage, prefix string) string {
	corpus := m.Text
	for _, h := range m.HTML {
		corpus += "\n" + h
	}
	prefix = strings.ToLower(prefix)
	low := strings.ToLower(corpus)
	idx := strings.Index(low, prefix)
	if idx < 0 {
		return ""
	}
	// 截到第一个空白 / 引号 / < / > 为止
	end := idx
	for end < len(corpus) {
		c := corpus[end]
		if c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '"' || c == '\'' || c == '<' || c == '>' || c == ')' {
			break
		}
		end++
	}
	return corpus[idx:end]
}
