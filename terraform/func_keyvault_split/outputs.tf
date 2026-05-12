# ============================================================================
# Output 定義
# ============================================================================
# デプロイ後に動作確認で使う情報をまとめて出力する。

output "resource_group_name" {
  description = "リソースグループ名（justfile / Azure CLI で参照）"
  value       = azurerm_resource_group.main.name
}

output "key_vault_name" {
  description = "Key Vault 名（justfile / Azure CLI で参照）"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault の URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "secret_name" {
  description = "Reader/Writer が共通で操作するシークレット名"
  value       = azurerm_key_vault_secret.greeting_name.name
}

output "reader_function_url" {
  description = "Reader Function App の GET /api/message URL（匿名公開）"
  value       = "https://${azurerm_linux_function_app.reader.default_hostname}/api/message"
}

output "writer_function_url" {
  description = "Writer Function App の POST /api/secret URL（Function キー必須）"
  value       = "https://${azurerm_linux_function_app.writer.default_hostname}/api/secret"
}

output "reader_function_app_name" {
  description = "Reader Function App 名（コードデプロイや再起動コマンドで使う）"
  value       = azurerm_linux_function_app.reader.name
}

output "writer_function_app_name" {
  description = "Writer Function App 名（コードデプロイや再起動コマンドで使う）"
  value       = azurerm_linux_function_app.writer.name
}

# ----------------------------------------------------------------------------
# 動作確認用コマンド
# ----------------------------------------------------------------------------
# func azure functionapp publish の後で順番に試すと、Reader → Writer → Reader の
# 動きが体感できる。
output "verify_commands" {
  description = "動作確認用の Azure CLI コマンド"
  value       = <<-EOT
    # 1. Reader / Writer それぞれに関数コードをデプロイ
    cd python/reader && func azure functionapp publish ${azurerm_linux_function_app.reader.name} --python && cd ../..
    cd python/writer && func azure functionapp publish ${azurerm_linux_function_app.writer.name} --python && cd ../..

    # 2. Reader を呼ぶ（最初は 503 が返ることがあるので、その場合は数十秒待って再試行 or 再起動）
    curl https://${azurerm_linux_function_app.reader.default_hostname}/api/message

    # 3. Writer の Function キーを取得
    az functionapp keys list --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.writer.name} --query functionKeys.default --output tsv

    # 4. Writer でシークレットを更新（<KEY> は上で取得したキー）
    curl -X POST "https://${azurerm_linux_function_app.writer.default_hostname}/api/secret?code=<KEY>" \
      -H "Content-Type: application/json" \
      -d '{"value": "Updated-World"}'

    # 5. Key Vault 側で更新を確認
    az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name ${azurerm_key_vault_secret.greeting_name.name} --query value --output tsv

    # 6. Reader に新しい値が反映されるよう再起動（Key Vault references のキャッシュをリセット）
    az functionapp restart --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.reader.name}

    # 7. もう一度 Reader を呼ぶと "Hello, Updated-World!" が返る
    curl https://${azurerm_linux_function_app.reader.default_hostname}/api/message
  EOT
}
