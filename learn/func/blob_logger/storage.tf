# ============================================================================
# Storage Account + 2 つの Blob コンテナ（uploads / logs）
# ============================================================================
# Function App のランタイムストレージを兼ねつつ、データ用コンテナも同居させる
# （学習をシンプルにするための構成。本番ではランタイム用とデータ用を分ける）。

resource "azurerm_storage_account" "main" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = var.tags
}

# ----------------------------------------------------------------------------
# 入力コンテナ: ここにファイルをアップロードすると Blob トリガーが発火する
# ----------------------------------------------------------------------------
resource "azurerm_storage_container" "uploads" {
  name                  = var.uploads_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ----------------------------------------------------------------------------
# 出力コンテナ: アップロードのたびにここへログファイルが書き込まれる
# ----------------------------------------------------------------------------
# トリガー監視対象（uploads）と別コンテナにすることが重要。
# 同じコンテナにログを書くと、書いたログ自身が再びトリガーを発火させて
# 無限ループになる恐れがある。
resource "azurerm_storage_container" "logs" {
  name                  = var.logs_container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}
