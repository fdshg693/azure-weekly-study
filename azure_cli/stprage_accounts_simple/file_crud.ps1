# ローカルファイルをBLOBストレージにアップロード
az storage blob upload `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name> `
  --file <local-file-path>

# ファイルをダウンロード
az storage blob download `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name> `
  --file <local-file-path>

# ファイル情報を表示
az storage blob show `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name>

# コンテナ内のファイル一覧を表示
az storage blob list `
  --account-name <storage-account-name> `
  --container-name <container-name>

# 同じ名前で新しいファイルをアップロード（上書き）
az storage blob upload `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name> `
  --file <new-file-path> `
  --overwrite

# ファイルを削除
az storage blob delete `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name>

# コンテナ内の全ファイルを削除
az storage blob delete-batch `
  --account-name <storage-account-name> `
  --source <container-name>