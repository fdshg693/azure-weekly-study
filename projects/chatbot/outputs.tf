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

# ----------------------------------------------------------------------------
# Web App 情報
# ----------------------------------------------------------------------------
output "web_app_name" {
  description = "Web App 名"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_url" {
  description = "Web App の URL（ブラウザでアクセス可能）"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_default_hostname" {
  description = "Web App のデフォルトホスト名"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_principal_id" {
  description = "Web App のシステム割り当てマネージド ID の principal_id"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

# ----------------------------------------------------------------------------
# Azure OpenAI 情報
# ----------------------------------------------------------------------------
output "openai_endpoint" {
  description = "Azure OpenAI エンドポイント（アプリの AZURE_OPENAI_ENDPOINT と同じ）"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_account_name" {
  description = "Azure OpenAI アカウント名"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_deployment_name" {
  description = "デプロイ済みモデル名（規約A: app/config/models.js の chat.deployment と一致）"
  value       = azurerm_cognitive_deployment.chat.name
}

output "openai_gpt5_deployment_name" {
  description = "gpt-5 デプロイ名（規約A: app/config/models.js の reasoning.deployment と一致 / Responses API 用）"
  value       = azurerm_cognitive_deployment.gpt5.name
}

# ----------------------------------------------------------------------------
# Key Vault 情報
# ----------------------------------------------------------------------------
output "key_vault_name" {
  description = "Key Vault 名（az keyvault secret set の --vault-name に使う）"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault の URI（アプリの KEY_VAULT_URI と同じ）"
  value       = azurerm_key_vault.main.vault_uri
}

# ----------------------------------------------------------------------------
# 動作確認用の CLI コマンド
# ----------------------------------------------------------------------------
output "verify_commands" {
  description = "デプロイ後の動作確認コマンド"
  value       = <<-EOT
    # ============================================================
    # チャットボット 動作確認コマンド
    # ============================================================

    # 1. ブラウザでチャット UI を開く
    az webapp browse --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}

    # 2. Web App の情報を確認
    az webapp show --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name} --output table

    # 3. アプリのログをストリーミング（OpenAI 呼び出しのエラーもここに出る）
    az webapp log tail --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}

    # 4. Azure OpenAI へ curl で疎通確認（要: 自分のアカウントに OpenAI User ロール）
    curl -sI https://${azurerm_linux_web_app.main.default_hostname}

    # 5. ロール割り当てを確認
    az role assignment list --scope ${azurerm_cognitive_account.openai.id} --output table
  EOT
}
