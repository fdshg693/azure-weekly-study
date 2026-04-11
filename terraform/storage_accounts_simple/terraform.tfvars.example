# ============================================================================
# 開発環境（Development）用の Terraform 変数設定ファイル
# ============================================================================
# このファイルは terraform apply -var-file="terraform.tfvars.dev" で使用されます
# Storage Account シンプル構成の開発環境用設定値を定義しています

# Storage Account 名（開発環境用・グローバルで一意である必要があります）
# 命名規則: 小文字と数字のみ、3-24文字
storage_account_name = "storagedevbasic001"

# Blob Storageコンテナ名
# 命名規則: 小文字、数字、ハイフンのみ、3-63文字
container_name = "dev-container"

# アップロードするBlobの名前
blob_name = "dev-data.txt"

# ローカルファイルシステム上のアップロード対象ファイルのパス
local_file_path = "./sample.txt"
