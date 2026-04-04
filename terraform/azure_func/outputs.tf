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
# Function App情報
# ----------------------------------------------------------------------------
output "function_app_name" {
  description = "Function App名"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Function AppのリソースID"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Function AppのデフォルトURL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_http_trigger_url" {
  description = "MyHttpTrigger関数のエンドポイントURL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/MyHttpTrigger"
}

# ----------------------------------------------------------------------------
# Storage Account情報
# ----------------------------------------------------------------------------
output "storage_account_name" {
  description = "Function App用Storage Account名"
  value       = azurerm_storage_account.func.name
}

output "storage_account_id" {
  description = "Storage AccountのリソースID"
  value       = azurerm_storage_account.func.id
}

# ----------------------------------------------------------------------------
# App Service Plan情報
# ----------------------------------------------------------------------------
output "service_plan_name" {
  description = "App Service Plan名"
  value       = azurerm_service_plan.func.name
}

output "service_plan_id" {
  description = "App Service PlanのリソースID"
  value       = azurerm_service_plan.func.id
}

# ----------------------------------------------------------------------------
# Application Insights情報
# ----------------------------------------------------------------------------
output "application_insights_name" {
  description = "Application Insights名"
  value       = azurerm_application_insights.func.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insightsのインストルメンテーションキー（機密情報）"
  value       = azurerm_application_insights.func.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insightsの接続文字列（機密情報）"
  value       = azurerm_application_insights.func.connection_string
  sensitive   = true
}

# ----------------------------------------------------------------------------
# デプロイ・テスト用のコマンド例
# ----------------------------------------------------------------------------
output "deploy_command" {
  description = "Azure Functions Core Tools を使用したデプロイコマンド"
  value = <<-EOT
    # Function App へのデプロイ手順:

    # 1. Azure Functions Core Tools でデプロイ
    cd azure_func/projects/simple
    func azure functionapp publish ${azurerm_linux_function_app.main.name}

    # 2. または Azure CLI でZipデプロイ
    cd azure_func/projects/simple
    zip -r deploy.zip . -x "*.pyc" "__pycache__/*" ".venv/*" "tests/*"
    az functionapp deployment source config-zip \
      --resource-group ${azurerm_resource_group.main.name} \
      --name ${azurerm_linux_function_app.main.name} \
      --src deploy.zip
  EOT
}

output "test_command" {
  description = "デプロイ後の動作確認コマンド"
  value = <<-EOT
    # HTTP Trigger の動作確認:

    # 1. クエリパラメータでテスト
    curl "https://${azurerm_linux_function_app.main.default_hostname}/api/MyHttpTrigger?name=Azure"

    # 2. リクエストボディでテスト
    curl -X POST "https://${azurerm_linux_function_app.main.default_hostname}/api/MyHttpTrigger" \
      -H "Content-Type: application/json" \
      -d '{"name": "Azure"}'

    # 3. pytest で統合テストを実行
    cd azure_func/projects/simple
    AZURE_FUNCTION_URL="https://${azurerm_linux_function_app.main.default_hostname}" \
      pytest tests/ -v
  EOT
}
