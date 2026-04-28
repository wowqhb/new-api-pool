// Pool Management — 上游账号（PoolAccount）
//
// 统一登记所有外部上游账号：官方付费 Key、Claude/Codex/Gemini OAuth、免费配额、第三方代销。
// 与 channels 表通过 ChannelId 弱关联（0 = 未绑定）。
// 表名 pool_accounts。

package model

import (
	"github.com/QuantumNous/new-api/common"

	"gorm.io/gorm"
)

const (
	PoolAccountTypeOfficial = "official" // 官方付费 API Key
	PoolAccountTypeOAuth    = "oauth"    // Claude / Codex / Gemini OAuth
	PoolAccountTypeFree     = "free"     // 免费配额（Gemini Free 等）
	PoolAccountType3rd      = "third"    // 第三方代销 Key

	PoolAccountStatusActive   = 1
	PoolAccountStatusWarning  = 2
	PoolAccountStatusDisabled = 3
)

type PoolAccount struct {
	Id            int            `json:"id"`
	Name          string         `json:"name" gorm:"size:128;not null;uniqueIndex:uk_pool_account_name_delete_at,priority:1"`
	Provider      string         `json:"provider" gorm:"size:64;not null;index"`
	AccountType   string         `json:"account_type" gorm:"size:32;not null;default:'official'"`
	Status        int            `json:"status" gorm:"default:1;index"`
	KeyMasked     string         `json:"key_masked" gorm:"size:128"`
	BalanceUSD    float64        `json:"balance_usd" gorm:"default:0"`
	UsedQuota     int64          `json:"used_quota" gorm:"default:0"`
	ExpireAt      int64          `json:"expire_at" gorm:"bigint;default:0;index"`
	ChannelId     int            `json:"channel_id" gorm:"default:0;index"`
	GroupName     string         `json:"group_name" gorm:"size:64;default:'default'"`
	Notes         string         `json:"notes" gorm:"type:text"`
	LastCheckedAt int64          `json:"last_checked_at" gorm:"bigint;default:0"`
	CreatedTime   int64          `json:"created_time" gorm:"bigint"`
	UpdatedTime   int64          `json:"updated_time" gorm:"bigint"`
	DeletedAt     gorm.DeletedAt `json:"-" gorm:"index;uniqueIndex:uk_pool_account_name_delete_at,priority:2"`
}

func (a *PoolAccount) Insert() error {
	now := common.GetTimestamp()
	a.CreatedTime = now
	a.UpdatedTime = now
	if a.Status == 0 {
		a.Status = PoolAccountStatusActive
	}
	if a.AccountType == "" {
		a.AccountType = PoolAccountTypeOfficial
	}
	if a.GroupName == "" {
		a.GroupName = "default"
	}
	return DB.Create(a).Error
}

func (a *PoolAccount) Update() error {
	a.UpdatedTime = common.GetTimestamp()
	return DB.Save(a).Error
}

func (a *PoolAccount) Delete() error {
	return DB.Delete(a).Error
}

func GetPoolAccountByID(id int) (*PoolAccount, error) {
	var a PoolAccount
	err := DB.First(&a, id).Error
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// SearchPoolAccounts 按关键字 + provider + status 过滤
func SearchPoolAccounts(keyword, provider, accountType string, status int, offset, limit int) ([]*PoolAccount, int64, error) {
	db := DB.Model(&PoolAccount{})
	if keyword != "" {
		like := "%" + keyword + "%"
		db = db.Where("name LIKE ? OR notes LIKE ? OR key_masked LIKE ?", like, like, like)
	}
	if provider != "" {
		db = db.Where("provider = ?", provider)
	}
	if accountType != "" {
		db = db.Where("account_type = ?", accountType)
	}
	if status > 0 {
		db = db.Where("status = ?", status)
	}
	var total int64
	if err := db.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var items []*PoolAccount
	if err := db.Offset(offset).Limit(limit).Order("id DESC").Find(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// CountPoolAccountsByStatus 用于总览
func CountPoolAccountsByStatus() (total, active, warning, disabled int64, err error) {
	if e := DB.Model(&PoolAccount{}).Count(&total).Error; e != nil {
		err = e
		return
	}
	if e := DB.Model(&PoolAccount{}).Where("status = ?", PoolAccountStatusActive).Count(&active).Error; e != nil {
		err = e
		return
	}
	if e := DB.Model(&PoolAccount{}).Where("status = ?", PoolAccountStatusWarning).Count(&warning).Error; e != nil {
		err = e
		return
	}
	if e := DB.Model(&PoolAccount{}).Where("status = ?", PoolAccountStatusDisabled).Count(&disabled).Error; e != nil {
		err = e
		return
	}
	return
}

// MaskPoolAccountKey 把原始 key 转成展示用的脱敏串：sk-xxx....yyyy
func MaskPoolAccountKey(rawKey string) string {
	r := []rune(rawKey)
	if len(r) <= 8 {
		return "****"
	}
	return string(r[:4]) + "..." + string(r[len(r)-4:])
}
