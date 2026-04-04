# Blobコンテナの作成
resource "azurerm_storage_container" "example" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.example.name
  container_access_type = "private"
}

# ローカルファイルをBlobストレージにアップロード
resource "azurerm_storage_blob" "example" {
  name                   = var.blob_name
  storage_account_name   = azurerm_storage_account.example.name
  storage_container_name = azurerm_storage_container.example.name
  type                   = "Block"
  source                 = var.local_file_path
  content_md5            = filemd5(var.local_file_path)  # ファイル内容変更の検出用
}

# ----------------------------------------------------------------------------
# SASトークンの生成
# ----------------------------------------------------------------------------
# SAS (Shared Access Signature) は、Storage Accountのリソースへの
# 期限付きアクセス権を付与するためのトークン
data "azurerm_storage_account_sas" "example" {
  connection_string = azurerm_storage_account.example.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  # resource_types: SASトークンでアクセスを許可するリソースの種類
  #   - service:   サービスレベルのAPI（コンテナ一覧取得など）
  #   - container: コンテナレベルのAPI（Blob一覧取得など）
  #   - object:    オブジェクトレベルのAPI（Blobの読み書きなど）
  resource_types {
    service   = false
    container = false
    object    = true
  }

  # services: SASトークンでアクセスを許可するサービスの種類
  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  # SASトークンの有効期間
  start  = timestamp()
  expiry = timeadd(timestamp(), var.sas_token_expiry)

  # permissions: SASトークンで許可する操作
  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}