# ============================================================================
# プライベートエンドポイントとPrivate DNS Zoneの定義
# ============================================================================
# Storage Accountへのセキュアなプライベートアクセスを実現する設定

# ============================================================================
# Private DNS Zone の作成
# ============================================================================
# プライベートエンドポイントのDNS名前解決用のPrivate DNS Zone
# Storage Accountの各サービスタイプごとに異なるDNSゾーンが必要

# Blob サービス用
resource "azurerm_private_dns_zone" "blob" {
  # name: Blobサービス用のPrivate DNS Zone名（固定値）
  # 各Azureサービスには特定のDNSゾーン名が必要:
  # - Blob: privatelink.blob.core.windows.net
  # - File: privatelink.file.core.windows.net
  # - Queue: privatelink.queue.core.windows.net
  # - Table: privatelink.table.core.windows.net
  # - Dfs (Data Lake Storage Gen2): privatelink.dfs.core.windows.net
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# ============================================================================
# Private DNS Zone を Virtual Network にリンク
# ============================================================================
# VNet内のリソースがPrivate DNS Zoneを使用してDNS解決できるようにする

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "vnet-link-blob"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.main.id

  # registration_enabled: VNet内のVMを自動的にDNSに登録するか
  # false: 手動登録のみ（プライベートエンドポイントには不要）
  # true: VNet内のVMのホスト名を自動登録
  registration_enabled = false

  tags = var.tags
}

# ============================================================================
# Private Endpoint の作成
# ============================================================================
# Storage AccountのBlobサービスへのプライベートエンドポイント

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-storage-blob"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoint.id
  tags                = var.tags

  # private_service_connection: プライベートエンドポイントの接続設定
  private_service_connection {
    # name: 接続の名前
    name = "psc-storage-blob"

    # private_connection_resource_id: 接続先リソースのID
    private_connection_resource_id = azurerm_storage_account.main.id

    # is_manual_connection: 手動承認が必要か
    # false: 自動承認（同じサブスクリプション内の場合）
    # true: リソース所有者の手動承認が必要
    is_manual_connection = false

    # subresource_names: 接続するサブリソースの種類
    # Storage Accountの場合のオプション:
    # - blob: Blob サービス
    # - file: File サービス
    # - queue: Queue サービス
    # - table: Table サービス
    # - dfs: Data Lake Storage Gen2
    # - web: 静的Webサイトホスティング
    subresource_names = ["blob"]

    # request_message: 手動接続の場合のリクエストメッセージ（オプション）
    # is_manual_connection = true の場合にのみ使用
    # request_message = "Please approve this connection"
  }

  # private_dns_zone_group: Private DNS Zoneとの統合
  # これにより、プライベートエンドポイントのIPアドレスが自動的にDNSに登録されます
  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  # custom_network_interface_name: カスタムNIC名（オプション）
  # 指定しない場合は自動生成されます
  # custom_network_interface_name = "nic-pe-storage-blob"

  # ip_configuration: 静的プライベートIPアドレスの設定（オプション）
  # 通常は動的割り当てで問題ありません
  # ip_configuration {
  #   name               = "ipconfig1"
  #   private_ip_address = "10.0.1.10"
  #   subresource_name   = "blob"
  # }
}

# ============================================================================
# 追加のPrivate Endpoint（他のストレージサービス用）の例
# ============================================================================
# 必要に応じて、File、Queue、Table、Dfsサービス用のプライベートエンドポイントも作成可能

# File サービス用
# resource "azurerm_private_dns_zone" "file" {
#   name                = "privatelink.file.core.windows.net"
#   resource_group_name = azurerm_resource_group.main.name
# }
#
# resource "azurerm_private_dns_zone_virtual_network_link" "file" {
#   name                  = "vnet-link-file"
#   resource_group_name   = azurerm_resource_group.main.name
#   private_dns_zone_name = azurerm_private_dns_zone.file.name
#   virtual_network_id    = azurerm_virtual_network.main.id
# }
#
# resource "azurerm_private_endpoint" "file" {
#   name                = "pe-storage-file"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#   subnet_id           = azurerm_subnet.private_endpoint.id
#
#   private_service_connection {
#     name                           = "psc-storage-file"
#     private_connection_resource_id = azurerm_storage_account.main.id
#     is_manual_connection           = false
#     subresource_names              = ["file"]
#   }
#
#   private_dns_zone_group {
#     name                 = "file-dns-zone-group"
#     private_dns_zone_ids = [azurerm_private_dns_zone.file.id]
#   }
# }
