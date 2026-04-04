output "storage_account_id" {
  value = azurerm_storage_account.example.id
}

# SASトークン付きのBlobアクセスURL
output "blob_url_with_sas" {
  description = "SASトークン付きのBlobアクセスURL（このURLでブラウザからファイルにアクセス可能）"
  value       = "${azurerm_storage_blob.example.url}${data.azurerm_storage_account_sas.example.sas}"
  sensitive   = true
}