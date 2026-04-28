// Pool Router — 号池管理 API 路由组
//
// 所有 /api/pool/* 路由均要求管理员鉴权（AdminAuth），
// 唯一例外：/api/pool/jobs/:id/callback —— 给外部 worker 回调用，靠 query token 校验。

package router

import (
	"github.com/QuantumNous/new-api/controller"
	"github.com/QuantumNous/new-api/middleware"

	"github.com/gin-gonic/gin"
)

func SetPoolRouter(router *gin.Engine) {
	// 公开路由（仅外部 worker 回调，token 校验）
	open := router.Group("/api/pool")
	open.Use(middleware.RouteTag("api"))
	{
		open.POST("/jobs/:id/callback", controller.ReceivePoolJobCallback)
	}

	pool := router.Group("/api/pool")
	pool.Use(middleware.RouteTag("api"))
	pool.Use(middleware.AdminAuth())
	{
		// 1. Overview
		pool.GET("/overview", controller.GetPoolOverview)

		// 2. Accounts
		pool.GET("/accounts", controller.GetPoolAccounts)
		pool.GET("/accounts/:id", controller.GetPoolAccount)
		pool.GET("/accounts/:id/full_key", controller.GetPoolAccountFullKey)
		pool.POST("/accounts/:id/bind", controller.BindPoolAccountChannel)
		pool.POST("/accounts", controller.AddPoolAccount)
		pool.PUT("/accounts/:id", controller.UpdatePoolAccount)
		pool.DELETE("/accounts/:id", controller.DeletePoolAccount)

		// 3. Recipes & Jobs
		pool.GET("/recipes", controller.GetPoolRecipes)
		pool.PUT("/recipes/:id", controller.UpdatePoolRecipe)
		pool.POST("/recipes/:key/enqueue", controller.EnqueuePoolRecipe)
		pool.POST("/jobs/:id/manual-result", controller.ManualSubmitJobResult)
		pool.POST("/jobs/:id/cancel", controller.CancelPoolJob)
		pool.POST("/jobs/:id/retry", controller.RetryPoolJob)
		pool.GET("/worker/status", controller.GetPoolWorkerStatus)
		pool.GET("/automation/config", controller.GetPoolAutomationConfig)
		pool.PUT("/automation/config", controller.SetPoolAutomationConfig)

		// 4. Billing
		pool.GET("/billing/summary", controller.GetPoolBillingSummary)

		// 5. Alerts
		pool.GET("/alerts", controller.GetPoolAlerts)
		pool.POST("/alerts/run", controller.TriggerPoolHealthCheck)
		pool.POST("/alerts/:id/resolve", controller.ResolvePoolAlert)
		pool.GET("/alerts/telegram", controller.GetPoolTelegramConfig)
		pool.PUT("/alerts/telegram", controller.SetPoolTelegramConfig)
		pool.POST("/alerts/telegram/test", controller.TestPoolTelegram)
	}
}
