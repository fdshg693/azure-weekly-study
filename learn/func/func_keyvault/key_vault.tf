# ============================================================================
# Key Vault（RBAC モード）+ 初期シークレット
# ============================================================================
# Reader / Writer 両方の Function App から参照される共有 Key Vault。
# RBAC ロールはこのファイルではなく function_app_reader.tf / function_app_writer.tf
# 側で各 Function App の Managed Identity に対して付与する。

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  # RBAC モード（アクセスポリシーではなく Azure RBAC ロールで権限管理）
  enable_rbac_authorization = true

  # 開発環境向け：ソフトデリート最短、パージ保護なし
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Function App から Key Vault references 経由でアクセスするため、パブリック有効
  # （本番はプライベートエンドポイントを併用すること）
  public_network_access_enabled = true

  tags = var.tags
}

# ----------------------------------------------------------------------------
# 現在のユーザー（terraform 実行者）に Secrets Officer を付与
# ----------------------------------------------------------------------------
# 用途:
#   1. Terraform が azurerm_key_vault_secret.greeting_name を作成するため
#   2. デプロイ後、CLI から Writer の動作結果を `az keyvault secret show` 等で確認するため
resource "azurerm_role_assignment" "current_user_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ----------------------------------------------------------------------------
# 初期シークレット
# ----------------------------------------------------------------------------
# Reader は Key Vault reference 経由で「最新バージョン」を読み取る。
# Writer は SDK で同名シークレットの新バージョンを作成する（= 値の更新）。
#
# 注意: versionless_id を使うと、Writer がシークレットを更新しても Function App の
# app_settings は古いバージョンの値をキャッシュし続ける可能性がある。
# その場合は Reader Function App を再起動するか、最大 24 時間待つと自動で
# 最新版に切り替わる（Key Vault references の挙動）。
resource "azurerm_key_vault_secret" "greeting_name" {
  name         = var.secret_name
  value        = var.secret_initial_value
  key_vault_id = azurerm_key_vault.main.id

  # RBAC ロール反映を待ってから作成（反映には数秒かかることがある）
  depends_on = [azurerm_role_assignment.current_user_kv_officer]

  tags = var.tags

  # Writer が値を更新した後の terraform plan で「差分あり」と判定されないよう、
  # value の変更は無視する（初期作成のみ Terraform 管理）。
  lifecycle {
    ignore_changes = [value]
  }
}
