output "storage_account_id" {
  value = azurerm_storage_account.example.id
}

# ----------------------------------------------------------------------------
# 静的Webサイトのエンドポイント（匿名公開）
# ----------------------------------------------------------------------------
# $web コンテナにアップロードした index.html / error.html だけがここで配信される。
output "static_website_url" {
  description = "静的Webサイトのトップページ URL（index.html が返る）"
  value       = azurerm_storage_account.example.primary_web_endpoint
}

output "static_website_host" {
  description = "静的Webサイトのホスト名（カスタムドメイン設定などで使用）"
  value       = azurerm_storage_account.example.primary_web_host
}

# ----------------------------------------------------------------------------
# 非公開ファイル用の SAS 付き URL
# ----------------------------------------------------------------------------
# private コンテナにアップロードしたファイルは Web エンドポイントからは配信されない。
# 一時的に共有したい場合だけ、この SAS 付き URL を発行して使う。
output "blob_url_with_sas" {
  description = "private コンテナ内 Blob への SAS 付きアクセス URL（24 時間限定 / 読み取り専用）"
  value       = "${azurerm_storage_blob.example.url}${data.azurerm_storage_account_sas.example.sas}"
  sensitive   = true
}
