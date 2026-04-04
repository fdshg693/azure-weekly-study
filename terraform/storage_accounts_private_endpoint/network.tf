# ============================================================================
# ネットワークリソースの定義
# ============================================================================
# Virtual Network、サブネット、Network Security Groupの設定

# ----------------------------------------------------------------------------
# Virtual Networkの作成
# ----------------------------------------------------------------------------
# プライベートエンドポイントはVNet内のプライベートIPアドレスを使用します
resource "azurerm_virtual_network" "main" {
  # name: Virtual Networkの名前
  name = "vnet-storage-private"

  # address_space: VNetで使用するIPアドレス範囲（CIDR表記）
  # 例: ["10.0.0.0/16"] は 10.0.0.0 から 10.0.255.255 までの65,536個のIPアドレス
  address_space = var.vnet_address_space

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # dns_servers: カスタムDNSサーバーのリスト（オプション）
  # 指定しない場合は、AzureのデフォルトDNSが使用されます
  # dns_servers = ["10.0.0.4", "10.0.0.5"]
}

# ----------------------------------------------------------------------------
# サブネットの作成（プライベートエンドポイント用）
# ----------------------------------------------------------------------------
# プライベートエンドポイントを配置するサブネット
resource "azurerm_subnet" "private_endpoint" {
  name                 = "snet-private-endpoint"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name

  # address_prefixes: サブネットのアドレス範囲（VNetのアドレス空間内である必要があります）
  address_prefixes = [var.subnet_address_prefix]

  # プライベートエンドポイント用の重要な設定
  # private_endpoint_network_policies: プライベートエンドポイントに対する
  # ネットワークポリシー（NSG、UDR）の動作を制御
  # オプション:
  #   - Disabled: ネットワークポリシーを無効化（推奨、プライベートエンドポイントの接続を妨げない）
  #   - Enabled: ネットワークポリシーを有効化（NSG、UDRが適用される）
  #   - NetworkSecurityGroupEnabled: NSGのみ有効
  #   - RouteTableEnabled: ルートテーブル（UDR）のみ有効
  private_endpoint_network_policies = "Disabled"

  # service_endpoints: サービスエンドポイントのリスト（オプション）
  # プライベートエンドポイントとは異なり、サービスエンドポイントはパブリックIP経由
  # service_endpoints = ["Microsoft.Storage"]
}

# ----------------------------------------------------------------------------
# サブネットの作成（VM用）
# ----------------------------------------------------------------------------
# プライベートエンドポイント経由でStorage Accountにアクセスするテスト用VM配置サブネット
resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.vm_subnet_address_prefix]
}

# ----------------------------------------------------------------------------
# Network Security Group (NSG) の作成
# ----------------------------------------------------------------------------
# VMサブネット用のファイアウォールルール
resource "azurerm_network_security_group" "vm" {
  name                = "nsg-vm-subnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # インバウンドルール: SSH接続を許可（本番環境では必ずIP制限を実施）
  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000  # 優先度（100-4096、小さいほど優先）
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # 本番環境では特定のIPアドレスに制限すべき
    destination_address_prefix = "*"
  }

  # アウトバウンドルール: すべてのアウトバウンド通信を許可（デフォルト動作）
  # 必要に応じて制限可能
}

# NSGをVMサブネットに関連付け
resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}
