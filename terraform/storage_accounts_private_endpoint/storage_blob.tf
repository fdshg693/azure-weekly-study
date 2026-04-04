# ============================================================================
# Blob コンテナとBlobストレージの定義
# ============================================================================
# Storage Accountのコンテナとサンプルファイルのアップロード

# ----------------------------------------------------------------------------
# Blobコンテナの作成
# ----------------------------------------------------------------------------
resource "azurerm_storage_container" "main" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.main.name

  # container_access_type: コンテナのアクセスレベル
  # private: 認証が必要（デフォルト、推奨）
  # blob: Blob への匿名読み取りアクセス
  # container: コンテナとBlobへの匿名読み取りアクセス
  container_access_type = var.container_access_type

  # metadata: コンテナに関するカスタムメタデータ（キー・バリューペア）
  # metadata = {
  #   department = "IT"
  #   project    = "DataLake"
  # }
}

# ----------------------------------------------------------------------------
# ローカルファイルをBlobストレージにアップロード
# ----------------------------------------------------------------------------
resource "azurerm_storage_blob" "sample" {
  name                   = var.blob_name
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.main.name

  # type: Blobのタイプ
  # Block: 一般的なファイル（最大4.75TB）、大きなファイルをブロックに分けてアップロード
  # Page: ランダムアクセス用（VHDディスクなど、最大8TB）
  # Append: 追記専用（ログファイルなど、最大195GB）
  type = "Block"

  # source: ローカルファイルのパス
  source = var.local_file_path

  # content_md5: ファイル内容のMD5ハッシュ（整合性チェックと変更検出用）
  # filemd5() 関数を使用してファイル変更時に自動的に再アップロード
  content_md5 = filemd5(var.local_file_path)

  # content_type: MIMEタイプ（オプション、ブラウザでの表示に影響）
  # 例: "text/plain", "application/json", "image/png"
  # content_type = "text/plain"

  # cache_control: キャッシュ制御ヘッダー（オプション）
  # cache_control = "max-age=3600"

  # content_encoding: コンテンツエンコーディング（オプション）
  # content_encoding = "gzip"

  # metadata: Blobに関するカスタムメタデータ
  # metadata = {
  #   uploaded_by = "terraform"
  #   timestamp   = timestamp()
  # }

  # access_tier: Blobレベルのアクセス階層（StorageV2でBlobタイプの場合のみ）
  # Hot: 頻繁なアクセス
  # Cool: 低頻度アクセス（最低30日保存）
  # Archive: アーカイブ（最低180日保存、読み取りには数時間かかる）
  # access_tier = "Hot"

  # 注意: このリソースは Storage Account が作成された後に実行されます
  # public_network_access_enabled = false の場合、Terraformの実行環境から
  # アクセスできない可能性があります
  depends_on = [azurerm_storage_account.main]
}
