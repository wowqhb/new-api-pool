package constant

import "github.com/QuantumNous/new-api/const_var"

type ContextKey string

const (
	ContextKeyTokenCountMeta  ContextKey = const_var.REDIS_KEY_PREFIX + ":token_count_meta"
	ContextKeyPromptTokens    ContextKey = const_var.REDIS_KEY_PREFIX + ":prompt_tokens"
	ContextKeyEstimatedTokens ContextKey = const_var.REDIS_KEY_PREFIX + ":estimated_tokens"

	ContextKeyOriginalModel    ContextKey = const_var.REDIS_KEY_PREFIX + ":original_model"
	ContextKeyRequestStartTime ContextKey = const_var.REDIS_KEY_PREFIX + ":request_start_time"

	/* token related keys */
	ContextKeyTokenUnlimited         ContextKey = const_var.REDIS_KEY_PREFIX + ":token_unlimited_quota"
	ContextKeyTokenKey               ContextKey = const_var.REDIS_KEY_PREFIX + ":token_key"
	ContextKeyTokenId                ContextKey = const_var.REDIS_KEY_PREFIX + ":token_id"
	ContextKeyTokenGroup             ContextKey = const_var.REDIS_KEY_PREFIX + ":token_group"
	ContextKeyTokenSpecificChannelId ContextKey = const_var.REDIS_KEY_PREFIX + ":specific_channel_id"
	ContextKeyTokenModelLimitEnabled ContextKey = const_var.REDIS_KEY_PREFIX + ":token_model_limit_enabled"
	ContextKeyTokenModelLimit        ContextKey = const_var.REDIS_KEY_PREFIX + ":token_model_limit"
	ContextKeyTokenCrossGroupRetry   ContextKey = const_var.REDIS_KEY_PREFIX + ":token_cross_group_retry"

	/* channel related keys */
	ContextKeyChannelId                ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_id"
	ContextKeyChannelName              ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_name"
	ContextKeyChannelCreateTime        ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_create_time"
	ContextKeyChannelBaseUrl           ContextKey = const_var.REDIS_KEY_PREFIX + ":base_url"
	ContextKeyChannelType              ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_type"
	ContextKeyChannelSetting           ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_setting"
	ContextKeyChannelOtherSetting      ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_other_setting"
	ContextKeyChannelParamOverride     ContextKey = const_var.REDIS_KEY_PREFIX + ":param_override"
	ContextKeyChannelHeaderOverride    ContextKey = const_var.REDIS_KEY_PREFIX + ":header_override"
	ContextKeyChannelOrganization      ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_organization"
	ContextKeyChannelAutoBan           ContextKey = const_var.REDIS_KEY_PREFIX + ":auto_ban"
	ContextKeyChannelModelMapping      ContextKey = const_var.REDIS_KEY_PREFIX + ":model_mapping"
	ContextKeyChannelStatusCodeMapping ContextKey = const_var.REDIS_KEY_PREFIX + ":status_code_mapping"
	ContextKeyChannelIsMultiKey        ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_is_multi_key"
	ContextKeyChannelMultiKeyIndex     ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_multi_key_index"
	ContextKeyChannelKey               ContextKey = const_var.REDIS_KEY_PREFIX + ":channel_key"

	ContextKeyAutoGroup           ContextKey = const_var.REDIS_KEY_PREFIX + ":auto_group"
	ContextKeyAutoGroupIndex      ContextKey = const_var.REDIS_KEY_PREFIX + ":auto_group_index"
	ContextKeyAutoGroupRetryIndex ContextKey = const_var.REDIS_KEY_PREFIX + ":auto_group_retry_index"

	/* user related keys */
	ContextKeyUserId      ContextKey = const_var.REDIS_KEY_PREFIX + ":id"
	ContextKeyUserSetting ContextKey = const_var.REDIS_KEY_PREFIX + ":user_setting"
	ContextKeyUserQuota   ContextKey = const_var.REDIS_KEY_PREFIX + ":user_quota"
	ContextKeyUserStatus  ContextKey = const_var.REDIS_KEY_PREFIX + ":user_status"
	ContextKeyUserEmail   ContextKey = const_var.REDIS_KEY_PREFIX + ":user_email"
	ContextKeyUserGroup   ContextKey = const_var.REDIS_KEY_PREFIX + ":user_group"
	ContextKeyUsingGroup  ContextKey = const_var.REDIS_KEY_PREFIX + ":group"
	ContextKeyUserName    ContextKey = const_var.REDIS_KEY_PREFIX + ":username"

	ContextKeyLocalCountTokens ContextKey = const_var.REDIS_KEY_PREFIX + ":local_count_tokens"

	ContextKeySystemPromptOverride ContextKey = const_var.REDIS_KEY_PREFIX + ":system_prompt_override"

	// ContextKeyFileSourcesToCleanup stores file sources that need cleanup when request ends
	ContextKeyFileSourcesToCleanup ContextKey = const_var.REDIS_KEY_PREFIX + ":file_sources_to_cleanup"

	// ContextKeyAdminRejectReason stores an admin-only reject/block reason extracted from upstream responses.
	// It is not returned to end users, but can be persisted into consume/error logs for debugging.
	ContextKeyAdminRejectReason ContextKey = const_var.REDIS_KEY_PREFIX + ":admin_reject_reason"

	// ContextKeyLanguage stores the user's language preference for i18n
	ContextKeyLanguage ContextKey = const_var.REDIS_KEY_PREFIX + ":language"
	ContextKeyIsStream ContextKey = const_var.REDIS_KEY_PREFIX + ":is_stream"
)
