# ============================================================================
# 出力値の定義
# ============================================================================
# 作成されたリソースの重要な情報を出力します
# terraform apply 後に確認できます

# ----------------------------------------------------------------------------
# リソースグループ情報
# ----------------------------------------------------------------------------
output "resource_group_name" {
  description = "リソースグループ名"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "デプロイされたリージョン"
  value       = azurerm_resource_group.main.location
}

# ----------------------------------------------------------------------------
# Function App 情報
# ----------------------------------------------------------------------------
output "function_app_name" {
  description = "Function App 名"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Function App のリソース ID"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Function App のデフォルト URL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_random_url" {
  description = "乱数生成エンドポイント URL（同期版・比較用）"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/random"
}

output "function_app_status_url" {
  description = "ステータス確認エンドポイント URL（Logic App の Until がポーリングする先）"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/status"
}

output "function_app_async_random_url" {
  description = "非同期版プロキシ URL（HTMX から叩く先・Logic App を内部で呼ぶ）"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/async-random"
}

# ----------------------------------------------------------------------------
# Service Bus 情報
# ----------------------------------------------------------------------------
output "servicebus_namespace_name" {
  description = "Service Bus Namespace 名"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_queue_name" {
  description = "ジョブ用 Service Bus キュー名"
  value       = azurerm_servicebus_queue.jobs.name
}

# ----------------------------------------------------------------------------
# Logic App 情報（入口）
# ----------------------------------------------------------------------------
output "logic_app_name" {
  description = "Logic App ワークフロー名"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_callback_url" {
  description = "Logic App の HTTP トリガー呼び出し URL（SAS 署名付き・機密）"
  value       = azurerm_logic_app_trigger_http_request.request.callback_url
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Static Web Apps 情報
# ----------------------------------------------------------------------------
output "static_web_app_name" {
  description = "Static Web App 名"
  value       = azurerm_static_web_app.main.name
}

output "static_web_app_default_host_name" {
  description = "Static Web App のホスト名"
  value       = azurerm_static_web_app.main.default_host_name
}

output "static_web_app_url" {
  description = "Static Web App の公開 URL"
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "static_web_app_api_key" {
  description = "Static Web App のデプロイトークン（swa CLI で使用、機密情報）"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Storage Account 情報
# ----------------------------------------------------------------------------
output "storage_account_name" {
  description = "Function App 用 Storage Account 名"
  value       = azurerm_storage_account.func.name
}

# ----------------------------------------------------------------------------
# Application Insights 情報
# ----------------------------------------------------------------------------
output "application_insights_name" {
  description = "Application Insights 名"
  value       = azurerm_application_insights.func.name
}

output "application_insights_connection_string" {
  description = "Application Insights の接続文字列（機密情報）"
  value       = azurerm_application_insights.func.connection_string
  sensitive   = true
}

# ----------------------------------------------------------------------------
# デプロイ・テスト用のコマンド例
# ----------------------------------------------------------------------------
output "deploy_command" {
  description = "デプロイコマンド（justfile 経由を推奨）"
  value       = <<-EOT
    # === 推奨: just でまとめてデプロイ ===
    just deploy            # Function App + Static Web App を両方デプロイ

    # === 個別実行 ===
    just deploy-func       # Function App のみ
    just deploy-web        # Static Web Apps のみ

    # === 素のコマンドで実行する場合 ===
    # Function App（Azure Functions Core Tools）
    cd python
    func azure functionapp publish ${azurerm_linux_function_app.main.name} --python

    # Static Web Apps（SWA CLI、デプロイトークンは terraform output -raw static_web_app_api_key）
    swa deploy ./web-dist --deployment-token <TOKEN> --env production
  EOT
}

output "test_command" {
  description = "デプロイ後の動作確認コマンド"
  value       = <<-EOT
    # === 同期版（既存）: 乱数 API を直接叩く ===
    curl "https://${azurerm_linux_function_app.main.default_hostname}/api/random?min=1&max=10"

    # === 非同期版（案B: Logic App → Service Bus → Worker → Table → Until ポーリング）===
    # callback_url は SAS 署名付きなので terraform output -raw で取り出す
    $url = terraform output -raw logic_app_callback_url
    curl.exe -X POST $url -H "Content-Type: application/json" -d '{\"min\":1,\"max\":100}'

    # === HTMX ページを開く ===
    start https://${azurerm_static_web_app.main.default_host_name}
  EOT
}
