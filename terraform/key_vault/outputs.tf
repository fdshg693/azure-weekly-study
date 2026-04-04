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
# Key Vault情報
# ----------------------------------------------------------------------------
output "key_vault_name" {
  description = "Key Vault名"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Key VaultのリソースID"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "Key VaultのURI（アプリケーションからのアクセスに使用）"
  value       = azurerm_key_vault.main.vault_uri
}

# ----------------------------------------------------------------------------
# シークレット情報
# ----------------------------------------------------------------------------
output "secret_name" {
  description = "作成されたシークレットの名前"
  value       = azurerm_key_vault_secret.sample.name
}

output "secret_id" {
  description = "シークレットのリソースID（バージョン付き）"
  value       = azurerm_key_vault_secret.sample.id
  sensitive   = true
}

output "secret_version" {
  description = "シークレットのバージョン"
  value       = azurerm_key_vault_secret.sample.version
}

# ----------------------------------------------------------------------------
# 動作確認用の CLI コマンド
# ----------------------------------------------------------------------------
output "verify_commands" {
  description = "デプロイ後の動作確認コマンド"
  value = <<-EOT
    # ============================================================
    # Key Vault 動作確認コマンド
    # ============================================================

    # 1. Key Vault の情報を確認
    az keyvault show --name ${azurerm_key_vault.main.name}

    # 2. シークレットの一覧を表示
    az keyvault secret list --vault-name ${azurerm_key_vault.main.name} --output table

    # 3. シークレットの値を取得
    az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name ${azurerm_key_vault_secret.sample.name} --query value --output tsv

    # 4. 新しいシークレットを手動で追加してみる
    az keyvault secret set --vault-name ${azurerm_key_vault.main.name} --name "manual-test" --value "created-by-cli"

    # 5. 追加したシークレットを確認
    az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name "manual-test" --query value --output tsv

    # 6. 手動で追加したシークレットを削除
    az keyvault secret delete --vault-name ${azurerm_key_vault.main.name} --name "manual-test"
  EOT
}
