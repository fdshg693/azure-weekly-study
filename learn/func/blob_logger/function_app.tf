# ============================================================================
# Function App（Blob トリガー）
# ============================================================================
# 役割:
#   - uploads コンテナへの Blob アップロードを監視（Blob トリガー）
#   - 発火するたびに logs コンテナへログファイルを書き出す（Blob 出力バインディング）
#
# 認証について（このプロジェクトがシンプルな理由）:
#   トリガーも出力バインディングも接続名 "AzureWebJobsStorage" を使う。
#   azurerm_linux_function_app は storage_account_name / access_key を指定すると
#   AzureWebJobsStorage（接続文字列）を自動で app_settings に注入する。
#   → 入出力ともに Function ランタイムが接続文字列で処理するため、
#     Managed Identity や RBAC ロール付与が不要になる。
#   （本番でキーレス化したい場合は identity ベース接続 + Storage Blob Data
#     ロールに切り替える。それは別プロジェクトの発展課題）

resource "azurerm_linux_function_app" "main" {
  name                = var.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  service_plan_id = azurerm_service_plan.func.id

  # この指定により AzureWebJobsStorage が接続文字列として自動設定される
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  site_config {
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"              = "python"
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.func.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.func.connection_string

    # Python v2 プログラミングモデル（デコレーターでの関数定義）を有効化
    "AzureWebJobsFeatureFlags" = "EnableWorkerIndexing"

    # func publish 時にリモートでビルド（依存解決）を行う
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"

    # 関数コードからコンテナ名を参照できるよう渡す（path のハードコードを避ける）
    "UPLOADS_CONTAINER" = var.uploads_container_name
    "LOGS_CONTAINER"    = var.logs_container_name
  }

  https_only = true

  tags = var.tags

  # コンテナが先に存在している状態でデプロイされるようにする
  depends_on = [
    azurerm_storage_container.uploads,
    azurerm_storage_container.logs,
  ]
}
