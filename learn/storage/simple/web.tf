# ============================================================================
# 静的Webサイト用 Blob のアップロード
# ============================================================================
# $web コンテナは azurerm_storage_account の static_website ブロックを有効にすると
# Azure 側で自動的に作成される特殊コンテナ。Terraform 側で
# azurerm_storage_container として明示的に作成する必要はない（作るとエラーになる）。
#
# 公開範囲についての重要な前提:
#   - $web コンテナの中身は https://<account>.z.web.core.windows.net/ 経由で匿名公開される
#   - 公開されるのは「$web コンテナにアップロードされたファイル」だけ
#   - したがって、ここでは index.html と error.html の 2 つだけをアップロードする
#   - 他のコンテナ（例: private なコンテナ）の Blob は Web エンドポイント経由では
#     一切配信されない（さらに main.tf の allow_nested_items_to_be_public = false で
#     Blob エンドポイント経由の匿名アクセスも禁止している）

resource "azurerm_storage_blob" "index_html" {
  name                   = var.index_document
  storage_account_name   = azurerm_storage_account.example.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = var.index_html_local_path
  content_type           = "text/html"
  content_md5            = filemd5(var.index_html_local_path)
}

resource "azurerm_storage_blob" "error_html" {
  name                   = var.error_document
  storage_account_name   = azurerm_storage_account.example.name
  storage_container_name = "$web"
  type                   = "Block"
  source                 = var.error_html_local_path
  content_type           = "text/html"
  content_md5            = filemd5(var.error_html_local_path)
}
