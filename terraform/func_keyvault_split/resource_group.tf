# ============================================================================
# リソースグループ + 共通データソース
# ============================================================================

# 現在の Azure ログイン情報（tenant_id / object_id）
# - terraform を実行しているユーザーに Key Vault Secrets Officer を付与し、
#   初期シークレットの作成と Writer 動作確認時のローカル CLI 操作を可能にする。
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
