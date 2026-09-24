// Pool Management — 巡检告警历史（PoolAlertHistory）
//
// 巡检引擎每次发现异常会写入一条记录；同时支持手动消除（resolved）。
// Telegram bot 配置存在 option 表（key: PoolTelegramBotToken / PoolTelegramChatId），不单独建表。

package model

import (
	"github.com/QuantumNous/new-api/common"
)

const (
	PoolAlertSeverityInfo     = "info"
	PoolAlertSeverityWarning  = "warning"
	PoolAlertSeverityCritical = "critical"
)

type PoolAlertHistory struct {
	Id          int    `json:"id"`
	RuleKey     string `json:"rule_key" gorm:"size:64;index"` // health_check / channel_down / balance_low / fail_rate_high
	Severity    string `json:"severity" gorm:"size:16;default:'info';index"`
	Title       string `json:"title" gorm:"size:255"`
	Message     string `json:"message" gorm:"type:text"`
	TargetType  string `json:"target_type" gorm:"size:32"` // channel / pool_account / group / system
	TargetId    int    `json:"target_id" gorm:"default:0"`
	Resolved    bool   `json:"resolved" gorm:"default:false;index"`
	ResolvedAt  int64  `json:"resolved_at" gorm:"bigint;default:0"`
	CreatedTime int64  `json:"created_time" gorm:"bigint;index"`
}

func (h *PoolAlertHistory) Insert() error {
	if h.CreatedTime == 0 {
		h.CreatedTime = common.GetTimestamp()
	}
	return DB.Create(h).Error
}

func (h *PoolAlertHistory) Resolve() error {
	h.Resolved = true
	h.ResolvedAt = common.GetTimestamp()
	return DB.Save(h).Error
}

// SearchPoolAlertHistory 列表 / 过滤
func SearchPoolAlertHistory(severity string, resolved *bool, offset, limit int) ([]*PoolAlertHistory, int64, error) {
	db := DB.Model(&PoolAlertHistory{})
	if severity != "" {
		db = db.Where("severity = ?", severity)
	}
	if resolved != nil {
		db = db.Where("resolved = ?", *resolved)
	}
	var total int64
	if err := db.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var items []*PoolAlertHistory
	if err := db.Offset(offset).Limit(limit).Order("id DESC").Find(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func CountPoolAlertOpen() (int64, error) {
	var c int64
	err := DB.Model(&PoolAlertHistory{}).Where("resolved = ?", false).Count(&c).Error
	return c, err
}
