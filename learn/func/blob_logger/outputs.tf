# ============================================================================
# Output 定義
# ============================================================================
# デプロイ後の動作確認（justfile / Azure CLI）で使う情報をまとめて出力する。

output "resource_group_name" {
  description = "リソースグループ名"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Storage Account 名（ファイルのアップロードやログ確認で使う）"
  value       = azurerm_storage_account.main.name
}

output "uploads_container" {
  description = "ファイルをアップロードする入力コンテナ名"
  value       = azurerm_storage_container.uploads.name
}

output "logs_container" {
  description = "ログが書き出される出力コンテナ名"
  value       = azurerm_storage_container.logs.name
}

output "function_app_name" {
  description = "Function App 名（コードデプロイやログ確認コマンドで使う）"
  value       = azurerm_linux_function_app.main.name
}

# ----------------------------------------------------------------------------
# 動作確認用コマンド
# ----------------------------------------------------------------------------
output "verify_commands" {
  description = "動作確認用の Azure CLI コマンド"
  value       = <<-EOT
    # 1. 関数コードをデプロイ
    cd python && func azure functionapp publish ${azurerm_linux_function_app.main.name} --python && cd ..

    # 2. ストレージキーを取得
    $KEY = az storage account keys list -g ${azurerm_resource_group.main.name} -n ${azurerm_storage_account.main.name} --query "[0].value" -o tsv

    # 3. テストファイルを uploads コンテナにアップロード
    "hello blob trigger" | Out-File -Encoding utf8 sample.txt
    az storage blob upload --account-name ${azurerm_storage_account.main.name} --account-key $KEY -c ${azurerm_storage_container.uploads.name} -n sample.txt -f sample.txt --overwrite

    # 4. 数十秒待ってから logs コンテナを確認（Consumption Plan は発火まで遅延あり）
    az storage blob list --account-name ${azurerm_storage_account.main.name} --account-key $KEY -c ${azurerm_storage_container.logs.name} -o table

    # 5. 生成されたログの中身を確認
    az storage blob download --account-name ${azurerm_storage_account.main.name} --account-key $KEY -c ${azurerm_storage_container.logs.name} -n sample.txt.log -f - 2>$null
  EOT
}
