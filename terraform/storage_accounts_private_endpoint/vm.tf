# ============================================================================
# テスト用仮想マシンの作成（オプション）
# ============================================================================
# プライベートエンドポイント経由でStorage Accountにアクセスできることを
# 確認するためのテスト用Linux VM
# 
# 注意: VMのデプロイにはコストがかかります
# テストが不要な場合は、このファイル全体をコメントアウトまたは削除してください

# ----------------------------------------------------------------------------
# Public IP Address（VM管理用）
# ----------------------------------------------------------------------------
# VMにSSH接続するためのパブリックIPアドレス
# 本番環境ではBastion Hostの使用を推奨
resource "azurerm_public_ip" "vm" {
  name                = "pip-test-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # allocation_method: IPアドレスの割り当て方法
  # Static: 固定IPアドレス（推奨）
  # Dynamic: 動的IPアドレス（VM停止時に解放される）
  allocation_method   = "Static"
  
  # sku: Public IPのSKU
  # Standard: 標準SKU（ゾーン冗長、固定割り当て）
  # Basic: 基本SKU（レガシー）
  sku                 = "Standard"
  
  tags = var.tags
}

# ----------------------------------------------------------------------------
# Network Interface Card (NIC)
# ----------------------------------------------------------------------------
# VMに接続するネットワークインターフェース
resource "azurerm_network_interface" "vm" {
  name                = "nic-test-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  
  # ip_configuration: NICのIP設定
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    
    # private_ip_address_allocation: プライベートIPの割り当て方法
    # Dynamic: 自動割り当て（推奨）
    # Static: 手動指定
    private_ip_address_allocation = "Dynamic"
    
    # 静的IPを使用する場合:
    # private_ip_address_allocation = "Static"
    # private_ip_address            = "10.0.2.10"
    
    # public_ip_address_id: パブリックIPアドレスのID（SSH接続用）
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
  
  # enable_accelerated_networking: 高速ネットワーキングの有効化
  # 対応するVMサイズでのみ使用可能、ネットワークパフォーマンスが向上
  # enable_accelerated_networking = false
  
  # enable_ip_forwarding: IP転送の有効化（ルーティング用）
  # enable_ip_forwarding = false
}

# ----------------------------------------------------------------------------
# Linux Virtual Machine
# ----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "test" {
  name                = "vm-test-private-endpoint"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # size: VMのサイズ（CPU、メモリ、ストレージの構成）
  # 一般的なサイズ:
  # - Standard_B1s: 1vCPU, 1GB RAM（最小構成、開発/テスト用）
  # - Standard_B2s: 2vCPU, 4GB RAM
  # - Standard_D2s_v3: 2vCPU, 8GB RAM（汎用ワークロード）
  size                = var.vm_size
  
  # admin_username: 管理者ユーザー名
  admin_username      = var.admin_username
  
  # network_interface_ids: VMに接続するNICのID（複数可能）
  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]
  
  # ============================================================================
  # 認証設定
  # ============================================================================
  # disable_password_authentication: パスワード認証の無効化
  # true: SSH公開鍵認証のみ（推奨、セキュア）
  # false: パスワード認証を許可
  disable_password_authentication = false
  
  # admin_password: 管理者パスワード（disable_password_authentication = false の場合）
  admin_password      = var.admin_password
  
  # SSH公開鍵認証を使用する場合（推奨）:
  # admin_ssh_key {
  #   username   = var.admin_username
  #   public_key = file("~/.ssh/id_rsa.pub")  # または tls_private_key リソースから生成
  # }
  
  # ============================================================================
  # OSディスクの設定
  # ============================================================================
  os_disk {
    # name: OSディスクの名前（オプション、指定しない場合は自動生成）
    name                 = "osdisk-test-vm"
    
    # caching: ディスクキャッシュの種類
    # ReadWrite: 読み書き両方キャッシュ（OSディスク推奨）
    # ReadOnly: 読み取りのみキャッシュ
    # None: キャッシュなし
    caching              = "ReadWrite"
    
    # storage_account_type: ストレージの種類
    # Standard_LRS: HDD、最も安価
    # StandardSSD_LRS: Standard SSD、バランス型
    # Premium_LRS: Premium SSD、高性能
    # StandardSSD_ZRS: ゾーン冗長Standard SSD
    # Premium_ZRS: ゾーン冗長Premium SSD
    storage_account_type = "Standard_LRS"
    
    # disk_size_gb: ディスクサイズ（GB）、イメージのデフォルトサイズより大きい場合のみ指定
    # disk_size_gb = 30
    
    # disk_encryption_set_id: ディスク暗号化セットのID（カスタマーマネージドキー使用時）
    # disk_encryption_set_id = azurerm_disk_encryption_set.example.id
  }
  
  # ============================================================================
  # ソースイメージの設定
  # ============================================================================
  source_image_reference {
    # publisher: イメージの発行元
    # 一般的な発行元: Canonical (Ubuntu), RedHat, OpenLogic (CentOS), Debian, SUSE
    publisher = "Canonical"
    
    # offer: イメージの提供名
    # Ubuntuの場合: UbuntuServer, 0001-com-ubuntu-server-focal, 0001-com-ubuntu-server-jammy
    offer     = "0001-com-ubuntu-server-jammy"
    
    # sku: イメージのSKU
    # Ubuntu 22.04 LTS: 22_04-lts, 22_04-lts-gen2
    # Ubuntu 20.04 LTS: 20_04-lts, 20_04-lts-gen2
    sku       = "22_04-lts-gen2"
    
    # version: イメージのバージョン
    # latest: 最新バージョンを自動選択（推奨）
    # または特定バージョン: "22.04.202301010"
    version   = "latest"
  }
  
  # カスタムイメージを使用する場合:
  # source_image_id = azurerm_image.custom.id
  
  # ============================================================================
  # その他の設定
  # ============================================================================
  
  # computer_name: VMのホスト名（オプション、指定しない場合はnameを使用）
  # computer_name = "testvm"
  
  # custom_data: クラウドイニットスクリプト（base64エンコード）
  # VMの初回起動時に実行されるスクリプト
  # 例: Azure CLI、curlなどのツールをインストール
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    # システムパッケージの更新
    apt-get update
    
    # Azure CLIのインストール
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    
    # curlとjqのインストール（APIテスト用）
    apt-get install -y curl jq
    
    # Storage Accountへのアクセステスト用スクリプトの作成
    cat > /home/${var.admin_username}/test_storage.sh << 'SCRIPT'
    #!/bin/bash
    # このスクリプトは、プライベートエンドポイント経由でStorage Accountに
    # アクセスできることを確認します
    
    STORAGE_ACCOUNT="${azurerm_storage_account.main.name}"
    
    echo "Testing DNS resolution for Storage Account..."
    nslookup $STORAGE_ACCOUNT.blob.core.windows.net
    
    echo ""
    echo "Testing connectivity to private endpoint..."
    curl -I https://$STORAGE_ACCOUNT.blob.core.windows.net/
    
    echo ""
    echo "Private IP address should be in the 10.0.0.0/16 range"
    SCRIPT
    
    chmod +x /home/${var.admin_username}/test_storage.sh
    chown ${var.admin_username}:${var.admin_username} /home/${var.admin_username}/test_storage.sh
  EOF
  )
  
  # boot_diagnostics: ブート診断の設定
  # VMの起動問題をトラブルシューティングするために使用
  boot_diagnostics {
    # storage_account_uri: 診断データを保存するストレージアカウントのURI
    # 指定しない場合は、マネージドストレージを使用（推奨）
    # storage_account_uri = azurerm_storage_account.diagnostics.primary_blob_endpoint
  }
  
  # identity: マネージドIDの設定
  # Azure リソースへの認証に使用
  # identity {
  #   type = "SystemAssigned"
  #   # または
  #   # type         = "UserAssigned"
  #   # identity_ids = [azurerm_user_assigned_identity.example.id]
  # }
  
  # patch_mode: OSパッチの適用方法
  # ImageDefault: イメージのデフォルト設定を使用
  # AutomaticByPlatform: Azureが自動的にパッチを適用
  # patch_mode = "ImageDefault"
  
  # provision_vm_agent: Azure VM エージェントのインストール
  # VM拡張機能を使用する場合はtrueにする必要があります
  # provision_vm_agent = true
  
  # zone: 可用性ゾーン（高可用性が必要な場合）
  # zone = "1"  # または "2", "3"
  
  tags = var.tags
  
  # 依存関係の明示的な定義
  depends_on = [
    azurerm_network_interface.vm,
    azurerm_private_endpoint.blob
  ]
}

# ============================================================================
# VM拡張機能の例（オプション）
# ============================================================================
# VM拡張機能を使用して、追加のソフトウェアをインストールしたり、
# スクリプトを実行したりできます

# カスタムスクリプト拡張機能の例
# resource "azurerm_virtual_machine_extension" "custom_script" {
#   name                 = "custom-script"
#   virtual_machine_id   = azurerm_linux_virtual_machine.test.id
#   publisher            = "Microsoft.Azure.Extensions"
#   type                 = "CustomScript"
#   type_handler_version = "2.1"
#   
#   settings = jsonencode({
#     commandToExecute = "echo 'Hello from custom script extension' > /tmp/hello.txt"
#   })
#   
#   # protected_settings: 機密情報を含む設定（暗号化される）
#   # protected_settings = jsonencode({
#   #   storageAccountName = azurerm_storage_account.scripts.name
#   #   storageAccountKey  = azurerm_storage_account.scripts.primary_access_key
#   #   fileUris           = ["https://example.blob.core.windows.net/scripts/setup.sh"]
#   # })
# }

# Azure Monitor エージェント拡張機能の例
# resource "azurerm_virtual_machine_extension" "monitor" {
#   name                       = "AzureMonitorLinuxAgent"
#   virtual_machine_id         = azurerm_linux_virtual_machine.test.id
#   publisher                  = "Microsoft.Azure.Monitor"
#   type                       = "AzureMonitorLinuxAgent"
#   type_handler_version       = "1.0"
#   auto_upgrade_minor_version = true
# }
