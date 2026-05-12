# ============================================================================
# Writer Function App（昇格権限 / Function キー保護）
# ============================================================================
# 役割:
#   - POST /api/secret （JSON ボディ {"value": "..."}）でシークレットを更新
#   - auth_level=FUNCTION のため、呼び出しには Function キーが必須
# 権限:
#   - System-Assigned Managed Identity に "Key Vault Secrets Officer"（読み書き）
#   - Reader と違い、SDK で Key Vault を直接操作する

resource "azurerm_linux_function_app" "writer" {
  name                = var.writer_function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  service_plan_id = azurerm_service_plan.func.id

  storage_account_name       = azurerm_storage_account.writer.name
  storage_account_access_key = azurerm_storage_account.writer.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"              = "python"
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.func.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.func.connection_string
    "AzureWebJobsFeatureFlags"              = "EnableWorkerIndexing"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "true"

    # ------------------------------------------------------------------
    # Key Vault SDK 経由で操作するための設定
    # ------------------------------------------------------------------
    # Writer は Key Vault references を使わず、azure-identity + azure-keyvault-secrets
    # で「リクエスト時に」Key Vault に書き込む。
    # → 起動時の解決遅延問題（Reader 側のコメント参照）が発生しない。
    "KEY_VAULT_URL" = azurerm_key_vault.main.vault_uri
    "SECRET_NAME"   = var.secret_name
  }

  https_only = true

  tags = var.tags
}

# ============================================================================
# Writer の Managed Identity に Key Vault Secrets Officer を付与
# ============================================================================
# "Key Vault Secrets Officer" はシークレットの読み書き・削除が可能。
# Writer はこれによってシークレットを更新できる（= Reader の最小権限と対比）。
resource "azurerm_role_assignment" "writer_kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_function_app.writer.identity[0].principal_id
}
