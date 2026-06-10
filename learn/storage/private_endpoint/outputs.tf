# ============================================================================
# 出力値の定義
# ============================================================================
# 作成されたリソースの重要な情報を出力します
# terraform apply 後に確認できます

# ----------------------------------------------------------------------------
# リソースグループ情報
# ----------------------------------------------------------------------------
output "resource_group_name" {
  description = "リソースグループ名"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "デプロイされたリージョン"
  value       = azurerm_resource_group.main.location
}

# ----------------------------------------------------------------------------
# Storage Account情報
# ----------------------------------------------------------------------------
output "storage_account_name" {
  description = "Storage Account名"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Storage AccountのリソースID"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Blobストレージのプライマリエンドポイント"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Storage Accountのプライマリアクセスキー（機密情報）"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true  # 出力時に値を隠す
}

output "storage_account_primary_connection_string" {
  description = "Storage Accountのプライマリ接続文字列（機密情報）"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Blobコンテナ情報
# ----------------------------------------------------------------------------
output "container_name" {
  description = "作成されたBlobコンテナ名"
  value       = azurerm_storage_container.main.name
}

output "blob_name" {
  description = "アップロードされたBlob名"
  value       = azurerm_storage_blob.sample.name
}

output "blob_url" {
  description = "アップロードされたBlobのURL"
  value       = azurerm_storage_blob.sample.url
}

# ----------------------------------------------------------------------------
# ネットワーク情報
# ----------------------------------------------------------------------------
output "virtual_network_name" {
  description = "Virtual Network名"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "Virtual NetworkのリソースID"
  value       = azurerm_virtual_network.main.id
}

output "private_endpoint_subnet_id" {
  description = "プライベートエンドポイント用サブネットのID"
  value       = azurerm_subnet.private_endpoint.id
}

output "vm_subnet_id" {
  description = "VM用サブネットのID"
  value       = azurerm_subnet.vm.id
}

# ----------------------------------------------------------------------------
# Private Endpoint情報
# ----------------------------------------------------------------------------
output "private_endpoint_name" {
  description = "プライベートエンドポイント名"
  value       = azurerm_private_endpoint.blob.name
}

output "private_endpoint_id" {
  description = "プライベートエンドポイントのリソースID"
  value       = azurerm_private_endpoint.blob.id
}

output "private_endpoint_private_ip" {
  description = "プライベートエンドポイントのプライベートIPアドレス"
  value       = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
}

# ----------------------------------------------------------------------------
# Private DNS Zone情報
# ----------------------------------------------------------------------------
output "private_dns_zone_name" {
  description = "Private DNS Zone名"
  value       = azurerm_private_dns_zone.blob.name
}

output "private_dns_zone_id" {
  description = "Private DNS ZoneのリソースID"
  value       = azurerm_private_dns_zone.blob.id
}

# ----------------------------------------------------------------------------
# VM情報（vm.tfが有効な場合）
# ----------------------------------------------------------------------------
output "vm_name" {
  description = "テスト用VM名"
  value       = azurerm_linux_virtual_machine.test.name
}

output "vm_id" {
  description = "テスト用VMのリソースID"
  value       = azurerm_linux_virtual_machine.test.id
}

output "vm_public_ip" {
  description = "テスト用VMのパブリックIPアドレス（SSH接続用）"
  value       = azurerm_public_ip.vm.ip_address
}

output "vm_private_ip" {
  description = "テスト用VMのプライベートIPアドレス"
  value       = azurerm_network_interface.vm.private_ip_address
}

# ----------------------------------------------------------------------------
# 接続情報とコマンド例
# ----------------------------------------------------------------------------
output "ssh_command" {
  description = "VMへのSSH接続コマンド"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.vm.ip_address}"
}

output "test_storage_command" {
  description = "VMからStorage Accountへのアクセステストコマンド"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.vm.ip_address} './test_storage.sh'"
}

output "azure_cli_upload_example" {
  description = "Azure CLIを使用したファイルアップロードの例（VMから実行）"
  value = <<-EOT
    # VMにSSHで接続後、以下のコマンドを実行:
    
    # 1. Azureにログイン
    az login
    
    # 2. ファイルをアップロード
    az storage blob upload \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.main.name} \
      --name test-from-vm.txt \
      --file /etc/hostname \
      --auth-mode login
    
    # 3. Blobリストを確認
    az storage blob list \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.main.name} \
      --auth-mode login \
      --output table
  EOT
}

output "powershell_upload_example" {
  description = "PowerShellを使用したファイルアップロードの例"
  value = <<-EOT
    # ローカル環境から実行（プライベートエンドポイント経由でアクセスできる場合）:
    
    # 接続文字列を環境変数に設定（機密情報注意）
    # $env:AZURE_STORAGE_CONNECTION_STRING = "<terraform output -raw storage_account_primary_connection_string の出力>"
    
    # または、アカウント名とキーを使用:
    $storageAccount = "${azurerm_storage_account.main.name}"
    $storageKey = "<terraform output -raw storage_account_primary_access_key の出力>"
    $ctx = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey
    
    # ファイルをアップロード
    Set-AzStorageBlobContent `
      -File "C:\path\to\file.txt" `
      -Container "${azurerm_storage_container.main.name}" `
      -Blob "uploaded-file.txt" `
      -Context $ctx
    
    # Blobリストを確認
    Get-AzStorageBlob -Container "${azurerm_storage_container.main.name}" -Context $ctx
  EOT
}

# ----------------------------------------------------------------------------
# 重要な注意事項
# ----------------------------------------------------------------------------
output "important_notes" {
  description = "重要な注意事項"
  value = <<-EOT
    ========================================
    プライベートエンドポイント使用時の注意事項
    ========================================
    
    1. パブリックアクセスの制限:
       - このStorage Accountは public_network_access_enabled = false に設定されています
       - インターネット経由での直接アクセスはできません
       - アクセスにはプライベートエンドポイントが必要です
    
    2. アクセス方法:
       - VNet内のVM（例: ${azurerm_linux_virtual_machine.test.name}）からアクセス
       - VPNまたはExpressRoute経由でオンプレミスからアクセス
       - VNetピアリングを使用して他のVNetからアクセス
    
    3. DNS解決:
       - VNet内からは ${azurerm_storage_account.main.name}.blob.core.windows.net が
         プライベートIPアドレス（${azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address}）に解決されます
       - VNet外からは依然としてパブリックIPアドレスに解決されますが、接続は拒否されます
    
    4. コスト:
       - プライベートエンドポイント: 約 $7-10/月
       - Private DNS Zone: 約 $0.50/月
       - VM: サイズによって変動（Standard_B1s: 約 $10-15/月）
       - ストレージ: 使用量に応じて課金
    
    5. セキュリティ推奨事項:
       - VM管理者パスワードは必ず変更してください
       - 本番環境ではSSH公開鍵認証を使用してください
       - NSGルールでSSHアクセスを特定のIPアドレスに制限してください
       - Storage Accountのアクセスキーは安全に管理してください
    
    ========================================
  EOT
}
