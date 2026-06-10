# ============================================================================
# Reader Function App（最小権限 / 匿名公開）
# ============================================================================
# 役割:
#   - GET /api/message を匿名で公開
#   - Key Vault reference 経由で app_settings にシークレット値を注入し、
#     関数コードは os.environ.get("GREETING_NAME") として参照する
# 権限:
#   - System-Assigned Managed Identity に "Key Vault Secrets User"（読み取り専用）
#   - 書き込み権限は持たない（万一コードが侵害されても更新できない）

resource "azurerm_linux_function_app" "reader" {
  name                = var.reader_function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  service_plan_id = azurerm_service_plan.func.id

  storage_account_name       = azurerm_storage_account.reader.name
  storage_account_access_key = azurerm_storage_account.reader.primary_access_key

  # System-Assigned Managed Identity を有効化
  # → Key Vault references の解決に使われる principal
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
    # Key Vault reference によるシークレット注入
    # ------------------------------------------------------------------
    # 書式: @Microsoft.KeyVault(SecretUri=<versionless-id>)
    # - versionless_id を指定すると Functions は「最新バージョン」を取り続ける
    # - 解決には Reader Function App の Managed Identity が必要（下で付与）
    # - 解決失敗時は app_settings の値が「参照式そのままの文字列」になる
    #   → 関数コードは先頭が "@Microsoft.KeyVault" の場合をエラー扱いする
    "GREETING_NAME" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.greeting_name.versionless_id})"
  }

  https_only = true

  tags = var.tags
}

# ============================================================================
# Reader の Managed Identity に Key Vault Secrets User を付与
# ============================================================================
# "Key Vault Secrets User" はシークレットの読み取りのみ可能（最小権限）。
# Officer / Administrator と違い、書き込み・削除は不可。
resource "azurerm_role_assignment" "reader_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.reader.identity[0].principal_id
}

# 注意:
# 上記の role_assignment は Function App 作成後に行われるため、
# 「Function App 作成直後の最初の数十秒〜数分は Key Vault reference が解決できない」
# 状態が発生する。その間 GREETING_NAME には参照式の文字列が入る。
# 解決手段:
#   - 数分待ってから Function App を再起動する（または初回デプロイのタイミングで再起動される）
#   - もしくは `az functionapp restart` を実行する
# これは Azure の RBAC 反映遅延と Key Vault references の解決タイミングに由来する
# 「学習ポイント」として README に明記している。
