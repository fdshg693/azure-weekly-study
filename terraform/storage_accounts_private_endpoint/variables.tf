# ============================================================================
# 変数定義ファイル
# ============================================================================
# このファイルでは、Terraformコードで使用する変数を定義します
# 変数を使用することで、コードの再利用性と柔軟性が向上します

# ----------------------------------------------------------------------------
# リソースグループ関連の変数
# ----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "リソースグループの名前"
  type        = string
  default     = "rg-storage-private-endpoint-seiwan"
}

variable "location" {
  description = "Azureリソースをデプロイするリージョン"
  type        = string
  default     = "Japan East"
  
  # 使用可能な主要リージョン:
  #   - Japan East: 東京（東日本）
  #   - Japan West: 大阪（西日本）
  #   - East US: 米国東部
  #   - West Europe: 西ヨーロッパ
  #   - Southeast Asia: 東南アジア
}

# ----------------------------------------------------------------------------
# Storage Account関連の変数
# ----------------------------------------------------------------------------
variable "storage_account_name" {
  description = <<-EOT
    Azure Storage Accountの名前。
    命名規則:
      - 小文字と数字のみ使用可能
      - 3-24文字の長さ制限
      - グローバルで一意である必要があります
  EOT
  type        = string
  default     = "gwoho11endpoint11seiwan"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage Account名は小文字と数字のみで、3-24文字の長さである必要があります。"
  }
}

variable "account_tier" {
  description = <<-EOT
    ストレージアカウントのパフォーマンスティア
    オプション:
      - Standard: 汎用的な用途、HDD ベース、コスト効率が良い
      - Premium: 高パフォーマンスが必要な場合、SSD ベース、高コスト
  EOT
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tierは 'Standard' または 'Premium' である必要があります。"
  }
}

variable "account_replication_type" {
  description = <<-EOT
    データの冗長性/レプリケーション戦略
    オプション:
      - LRS: Locally Redundant Storage (同一データセンター内で3コピー、最安)
      - GRS: Geo-Redundant Storage (プライマリ+セカンダリリージョン、6コピー)
      - RAGRS: Read-Access GRS (GRS + セカンダリリージョンへの読み取りアクセス)
      - ZRS: Zone-Redundant Storage (同一リージョンの3つの可用性ゾーンに分散)
      - GZRS: Geo-Zone-Redundant Storage (ZRS + 別リージョンへのレプリケーション)
      - RAGZRS: Read-Access GZRS (GZRS + セカンダリリージョンへの読み取りアクセス)
  EOT
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "無効なレプリケーションタイプです。"
  }
}

# ----------------------------------------------------------------------------
# ネットワーク関連の変数
# ----------------------------------------------------------------------------
variable "vnet_address_space" {
  description = "Virtual Networkのアドレス空間（CIDR表記）"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "サブネットのアドレスプレフィックス（CIDR表記）"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vm_subnet_address_prefix" {
  description = "VM用サブネットのアドレスプレフィックス（CIDR表記）"
  type        = string
  default     = "10.0.2.0/24"
}

# ----------------------------------------------------------------------------
# Blobコンテナおよびアップロード用の変数
# ----------------------------------------------------------------------------
variable "container_name" {
  description = <<-EOT
    Blob Storageコンテナの名前
    命名規則:
      - 小文字、数字、ハイフンのみ使用可能
      - 3-63文字の長さ制限
      - 先頭と末尾は英数字である必要があります
      - 連続するハイフンは使用不可
  EOT
  type        = string
  default     = "private-container"
  
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", var.container_name))
    error_message = "container_nameは小文字、数字、ハイフンのみで、3-63文字である必要があります。"
  }
}

variable "container_access_type" {
  description = <<-EOT
    コンテナのアクセスレベル
    オプション:
      - private: 認証されたアクセスのみ（デフォルト、最も安全）
      - blob: Blobへの匿名読み取りアクセスを許可
      - container: コンテナとBlobへの匿名読み取りアクセスを許可
    
    プライベートエンドポイントを使用する場合は 'private' を推奨
  EOT
  type        = string
  default     = "private"
  
  validation {
    condition     = contains(["private", "blob", "container"], var.container_access_type)
    error_message = "container_access_typeは 'private', 'blob', または 'container' である必要があります。"
  }
}

variable "blob_name" {
  description = "アップロードするBlobの名前"
  type        = string
  default     = "sample-file.txt"
}

variable "local_file_path" {
  description = "ローカルファイルシステム上のアップロード対象ファイルのパス"
  type        = string
  default     = "./sample.txt"
}

# ----------------------------------------------------------------------------
# タグ関連の変数
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグのマップ（コスト管理や整理に便利）"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "PrivateEndpointDemo"
    ManagedBy   = "Terraform"
  }
}

# ----------------------------------------------------------------------------
# VM関連の変数（プライベートエンドポイント経由でアクセステストする場合）
# ----------------------------------------------------------------------------
variable "admin_username" {
  description = "VM管理者ユーザー名"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = <<-EOT
    VM管理者パスワード
    要件:
      - 12文字以上
      - 大文字、小文字、数字、特殊文字のうち3種類を含む
    
    本番環境ではSSHキーの使用を推奨
  EOT
  type        = string
  sensitive   = true
  default     = "P@ssw0rd1234!"
  
  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "パスワードは12文字以上である必要があります。"
  }
}

variable "vm_size" {
  description = <<-EOT
    VMのサイズ
    一般的なサイズ:
      - Standard_B1s: 1vCPU, 1GB RAM（開発/テスト用、最小構成）
      - Standard_B2s: 2vCPU, 4GB RAM（小規模ワークロード）
      - Standard_D2s_v3: 2vCPU, 8GB RAM（汎用ワークロード）
      - Standard_D4s_v3: 4vCPU, 16GB RAM（中規模ワークロード）
  EOT
  type        = string
  default     = "Standard_B1s"
}
