# ============================================================================
# 出力値の定義
# ============================================================================
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
# App Service Plan 情報
# ----------------------------------------------------------------------------
output "app_service_plan_name" {
  description = "App Service Plan 名"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_sku" {
  description = "App Service Plan の SKU"
  value       = azurerm_service_plan.main.sku_name
}

output "app_service_plan_os" {
  description = "App Service Plan の OS タイプ"
  value       = azurerm_service_plan.main.os_type
}

# ----------------------------------------------------------------------------
# Web App 情報
# ----------------------------------------------------------------------------
output "web_app_name" {
  description = "Web App 名"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_id" {
  description = "Web App のリソースID"
  value       = azurerm_linux_web_app.main.id
}

output "web_app_url" {
  description = "Web App の URL（ブラウザでアクセス可能）"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_default_hostname" {
  description = "Web App のデフォルトホスト名"
  value       = azurerm_linux_web_app.main.default_hostname
}

# ----------------------------------------------------------------------------
# 動作確認用の CLI コマンド
# ----------------------------------------------------------------------------
output "verify_commands" {
  description = "デプロイ後の動作確認コマンド"
  value = <<-EOT
    # ============================================================
    # App Service 動作確認コマンド
    # ============================================================

    # 1. ブラウザでサイトを開く
    az webapp browse --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}

    # 2. Web App の情報を確認
    az webapp show --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name} --output table

    # 3. App Service Plan の情報を確認
    az appservice plan show --name ${azurerm_service_plan.main.name} --resource-group ${azurerm_resource_group.main.name} --output table

    # 4. アプリのログをストリーミング
    az webapp log tail --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}

    # 5. curl でサイトの応答を確認
    curl -sI https://${azurerm_linux_web_app.main.default_hostname}
  EOT
}
