# ============================================================================
# Logic App (Consumption) — 入口（同期ラッパー）
# ============================================================================
# クライアントから HTTP を受け取り、
#   1. jobId を採番（guid）
#   2. ジョブ内容を Service Bus キューに送信（ServiceBus connector）
#   3. Until ループで Function の /api/status?jobId=... を 3 秒間隔でポーリング
#   4. status=done を確認したら結果を Response アクションで返却
# という流れで「キュー越しに同期 RPC っぽく見せる」のが目的。
#
# Logic App Consumption は使った分だけ課金されるため学習用に適している。
# Until ループの間も従量課金がかかる点に注意（→ count/timeout で歯止め）。

# ----------------------------------------------------------------------------
# サブスクリプション情報（API connection の managed_api_id を組み立てるのに使用）
# ----------------------------------------------------------------------------
data "azurerm_subscription" "current" {}

locals {
  # 'Japan East' → 'japaneast' のようにマネージドAPIのlocation表記へ正規化
  managed_api_location = lower(replace(azurerm_resource_group.main.location, " ", ""))

  # ServiceBus マネージドAPIのリソースID
  servicebus_managed_api_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Web/locations/${local.managed_api_location}/managedApis/servicebus"

  # ステータス確認用 Function のURL（クエリで jobId を渡す）
  status_function_url = "https://${azurerm_linux_function_app.main.default_hostname}/api/status"
}

# ----------------------------------------------------------------------------
# API Connection: Service Bus
# ----------------------------------------------------------------------------
# Logic App から Service Bus を呼び出すための「管理 API 接続」。
# Logic App 側からは parameters('$connections')['servicebus']['connectionId'] で参照する。
resource "azurerm_api_connection" "servicebus" {
  name                = "servicebus-jobs"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = local.servicebus_managed_api_id

  display_name = "servicebus-jobs"

  parameter_values = {
    connectionString = azurerm_servicebus_namespace_authorization_rule.shared.primary_connection_string
  }

  # connectionString は state に平文で残るので tags 等で機密扱いを明示
  tags = var.tags

  # 初回作成後、Azureポータルで status が "Connected" にならないと Logic App から呼べない
  # 大抵は parameter_values に有効な接続文字列があれば自動で Connected になる
}

# ----------------------------------------------------------------------------
# Logic App ワークフロー本体（中身は空 → trigger/action リソースで肉付け）
# ----------------------------------------------------------------------------
resource "azurerm_logic_app_workflow" "main" {
  name                = var.logic_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # ワークフロー内で API connection を参照するための $connections パラメータ。
  # workflow_parameters: パラメータの「定義」（型・デフォルト）
  # parameters:          パラメータの「値」
  workflow_parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type         = "Object"
    })
  }

  parameters = {
    "$connections" = jsonencode({
      servicebus = {
        connectionId   = azurerm_api_connection.servicebus.id
        connectionName = "servicebus"
        id             = local.servicebus_managed_api_id
      }
    })
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# トリガー: HTTP リクエスト（manual）
# ----------------------------------------------------------------------------
# POST のボディに { "min": <int>, "max": <int> } を期待する。
# 実行URLは azurerm_logic_app_trigger_http_request.callback_url（output 参照）。
resource "azurerm_logic_app_trigger_http_request" "request" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.main.id

  schema = jsonencode({
    type = "object"
    properties = {
      min = { type = "integer" }
      max = { type = "integer" }
    }
  })

  method = "POST"
}

# ----------------------------------------------------------------------------
# Action 1: jobId を採番（InitializeVariable + guid()）
# ----------------------------------------------------------------------------
resource "azurerm_logic_app_action_custom" "init_job_id" {
  name         = "Init_jobId"
  logic_app_id = azurerm_logic_app_workflow.main.id

  body = jsonencode({
    type = "InitializeVariable"
    inputs = {
      variables = [
        {
          name  = "jobId"
          type  = "string"
          value = "@{guid()}"
        }
      ]
    }
    runAfter = {}
  })
}

# ----------------------------------------------------------------------------
# Action 2: 送信メッセージの中身（JSON）を組み立てる（Compose）
# ----------------------------------------------------------------------------
# 送信したい payload を Compose アクションで作っておくと、Service Bus 送信側で
# base64(string(outputs(...))) と書くだけで済む（式のネストが浅くなる）。
resource "azurerm_logic_app_action_custom" "compose_message" {
  name         = "Compose_message"
  logic_app_id = azurerm_logic_app_workflow.main.id

  body = jsonencode({
    type = "Compose"
    inputs = {
      jobId = "@variables('jobId')"
      min   = "@triggerBody()?['min']"
      max   = "@triggerBody()?['max']"
    }
    runAfter = {
      Init_jobId = ["Succeeded"]
    }
  })
}

# ----------------------------------------------------------------------------
# Action 3: Service Bus にメッセージ送信（ApiConnection）
# ----------------------------------------------------------------------------
# host.connection.name で $connections から servicebus を選んでいる。
# path に URL エンコードしたキュー名を埋め、ContentData にメッセージ本文を base64 で渡す。
resource "azurerm_logic_app_action_custom" "send_message" {
  name         = "Send_message"
  logic_app_id = azurerm_logic_app_workflow.main.id

  body = jsonencode({
    type = "ApiConnection"
    inputs = {
      host = {
        connection = {
          name = "@parameters('$connections')['servicebus']['connectionId']"
        }
      }
      method = "post"
      path   = "/@{encodeURIComponent('${azurerm_servicebus_queue.jobs.name}')}/messages"
      body = {
        ContentData = "@{base64(string(outputs('Compose_message')))}"
        ContentType = "application/json"
      }
    }
    runAfter = {
      Compose_message = ["Succeeded"]
    }
  })
}

# ----------------------------------------------------------------------------
# Action 4: Until ループ — /api/status を 3 秒間隔でポーリング
# ----------------------------------------------------------------------------
# 終了条件:  body('Get_status')?['status'] == 'done'
# 上限:      count=60, timeout=PT5M（最大 5 分。worker のスリープが長くなった時の安全弁）
# 中の Get_status は HTTP GET。Function 側は常に 200 を返し、本文の status で進捗を伝える。
resource "azurerm_logic_app_action_custom" "until_done" {
  name         = "Wait_for_result"
  logic_app_id = azurerm_logic_app_workflow.main.id

  body = jsonencode({
    type       = "Until"
    expression = "@equals(body('Get_status')?['status'], 'done')"
    limit = {
      count   = 60
      timeout = "PT5M"
    }
    actions = {
      Delay = {
        type = "Wait"
        inputs = {
          interval = {
            count = 3
            unit  = "Second"
          }
        }
        runAfter = {}
      }
      Get_status = {
        type = "Http"
        inputs = {
          method = "GET"
          uri    = local.status_function_url
          queries = {
            jobId = "@variables('jobId')"
          }
        }
        runAfter = {
          Delay = ["Succeeded"]
        }
      }
    }
    runAfter = {
      Send_message = ["Succeeded"]
    }
  })
}

# ----------------------------------------------------------------------------
# Action 5: クライアントへのレスポンス
# ----------------------------------------------------------------------------
# Until 内最後の Get_status の本文をそのまま返す（{status:"done", value:N}）。
resource "azurerm_logic_app_action_custom" "respond" {
  name         = "Response"
  logic_app_id = azurerm_logic_app_workflow.main.id

  body = jsonencode({
    type = "Response"
    kind = "Http"
    inputs = {
      statusCode = 200
      headers = {
        "Content-Type" = "application/json"
      }
      body = "@body('Get_status')"
    }
    runAfter = {
      Wait_for_result = ["Succeeded"]
    }
  })
}
