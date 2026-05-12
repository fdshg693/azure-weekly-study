# ============================================================================
# Service Bus（キュー）の定義
# ============================================================================
# Logic App（入口）から Worker Function（ワーカー）へジョブを橋渡しするキュー。
#
# 全体像:
#   Client → Logic App → [Service Bus Queue "jobs"] → Worker Function
#                ▲                                          │
#                └────── Until ループで /api/status をポーリング ─┐
#                                                                ▼
#                                                          Table Storage
#
# Tier 選択:
#   - Basic:    キューのみ・低コスト。今回のシンプルな PUSH/PULL には十分。
#   - Standard: Topic/Subscription、セッション、Logic Apps の "Send and Wait" など
#               高度な機能が必要なら Standard 以上。

resource "azurerm_servicebus_namespace" "main" {
  name                = var.servicebus_namespace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku = "Basic"

  tags = var.tags
}

# ----------------------------------------------------------------------------
# ジョブ用キュー
# ----------------------------------------------------------------------------
# Logic App が enqueue し、Worker Function（azure_func/python/function_app.py）
# の ServiceBusQueueTrigger で受信する。
resource "azurerm_servicebus_queue" "jobs" {
  name         = "jobs"
  namespace_id = azurerm_servicebus_namespace.main.id

  # Worker のスリープがあるので、ロック時間は余裕を持って 1 分にする
  lock_duration = "PT1M"

  # 配信失敗時の再試行上限。学習用は少なめでOK
  max_delivery_count = 5
}

# ----------------------------------------------------------------------------
# 認可ルール（Send 用と Listen 用を 1 つのルールに）
# ----------------------------------------------------------------------------
# Logic App: send（メッセージ送信）
# Worker Function: listen（メッセージ受信）
# 学習用に 1 つのルールでまとめている。本番では送信用/受信用を分けるのが望ましい。
resource "azurerm_servicebus_namespace_authorization_rule" "shared" {
  name         = "logicapp-and-worker"
  namespace_id = azurerm_servicebus_namespace.main.id

  listen = true
  send   = true
  manage = false
}
