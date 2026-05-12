# ============================================================================
# Storage Accounts（Reader / Writer それぞれ専用）
# ============================================================================
# Azure Functions Consumption Plan は Function App ごとに専用の Storage Account
# を必要とする（関数コード、トリガー状態、リース、ログの保存に使用）。
#
# Reader / Writer は権限スコープを分離するのが目的なので、ストレージも分けて
# 「障害の影響範囲（blast radius）」を狭くしておく。

resource "azurerm_storage_account" "reader" {
  name                = var.reader_storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = var.tags
}

resource "azurerm_storage_account" "writer" {
  name                = var.writer_storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = var.tags
}
