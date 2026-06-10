# ============================================================================
# 開発環境（Development）用の Terraform 変数設定ファイル
# ============================================================================
# このファイルは terraform apply -var-file="terraform.tfvars.dev" で使用されます
# 開発環境用の設定値を定義しています

# リソースグループ名（開発環境用）
resource_group_name = "rg-storage-private-endpoint-dev"

# デプロイするリージョン（開発用：日本東部）
location = "Japan East"

# Storage Account 名（開発環境用・グローバルで一意である必要があります）
storage_account_name = "storagedevendpoint001"

# パフォーマンスティア（開発環境はStandardで十分）
account_tier = "Standard"

# レプリケーション戦略（開発環境：LRS でコスト最適化）
# LRS: ローカル冗長ストレージ（同一データセンター内での冗長化）
account_replication_type = "LRS"

# Virtual Network アドレス空間
vnet_address_space = ["10.0.0.0/16"]

# Private Endpoint 用サブネット
subnet_address_prefix = "10.0.1.0/24"

# VM 用サブネット
vm_subnet_address_prefix = "10.0.2.0/24"

# Blobコンテナ名
container_name = "dev-data-container"

# コンテナアクセスタイプ（プライベートエンドポイント使用時は private）
container_access_type = "private"

# アップロード対象の Blob 名
blob_name = "dev-data-file.txt"

# ローカルファイルパス
local_file_path = "./sample.txt"

# タグ（リソース管理用）
tags = {
  Environment = "Development"
  Project     = "PrivateEndpointDev"
  ManagedBy   = "Terraform"
  CostCenter  = "Development"
}

# VM 管理ユーザー名
admin_username = "azureuser"

# VM 管理者パスワード（開発環境用）
admin_password = "P@ssw0rd2024Dev!"

# VM サイズ（開発環境用：最小構成でコスト削減）
vm_size = "Standard_B1s"
