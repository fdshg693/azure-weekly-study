# ============================================================================
# Storage Accountの定義
# ============================================================================
# Azure Functionsのランタイムに必要なStorage Account
# 関数コード、トリガー状態、ログなどの保存に使用されます

resource "azurerm_storage_account" "func" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # パフォーマンスと冗長性の設定
  # Azure Functions の Consumption プランでは Standard ティアが必要
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # StorageV2: 汎用v2、Azure Functionsで推奨
  account_kind = "StorageV2"

  # セキュリティ設定
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = var.tags
}
