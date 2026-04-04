# ============================================================================
# 変数定義ファイル
# ============================================================================
# このファイルでは、Terraformコードで使用する変数を定義します
# 変数を使用することで、コードの再利用性と柔軟性が向上します

# ----------------------------------------------------------------------------
# Storage Account名の変数
# ----------------------------------------------------------------------------
variable "storage_account_name" {
  # description: 変数の説明（ドキュメント目的）
  # この説明は terraform plan や terraform apply 時に表示されます
  description = "Azure Storage Accountの名前。小文字と数字のみ使用可能、3-24文字の長さ制限あり"
  
  # type: 変数のデータ型を指定
  # 利用可能な型:
  #   - string: 文字列
  #   - number: 数値
  #   - bool: 真偽値（true/false）
  #   - list(type): リスト（例: list(string)）
  #   - set(type): セット（重複なしリスト）
  #   - map(type): マップ/辞書（例: map(string)）
  #   - object({...}): 複雑な構造体
  #   - tuple([...]): 固定長・固定型のリスト
  type = string
  
  # default: デフォルト値（オプション）
  # デフォルト値を設定しない場合、terraform apply 時に値の入力を求められます
  default = "maikumastorageacct"  # ハイフン不可、小文字のみ
  
  # validation: 入力値の検証ルール（オプション）
  # Storage Accountの命名規則を強制
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage Account名は小文字と数字のみで、3-24文字の長さである必要があります。"
  }
  
  # sensitive: 値を秘密情報として扱うか（オプション、デフォルト: false）
  # true に設定すると、terraform plan や apply の出力時に値が隠されます
  # sensitive = false
}

# その他の変数定義の例:
# ----------------------------------------------------------------------------

# variable "location" {
#   description = "Azureリソースをデプロイするリージョン"
#   type        = string
#   default     = "Japan East"
#   
#   validation {
#     condition     = contains(["Japan East", "Japan West"], var.location)
#     error_message = "locationは 'Japan East' または 'Japan West' である必要があります。"
#   }
# }

# variable "tags" {
#   description = "リソースに適用するタグのマップ"
#   type        = map(string)
#   default = {
#     Environment = "Development"
#     ManagedBy   = "Terraform"
#   }
# }

# variable "enable_https_traffic_only" {
#   description = "HTTPS通信のみを許可するか"
#   type        = bool
#   default     = true
# }

# variable "allowed_ip_addresses" {
#   description = "Storage Accountへのアクセスを許可するIPアドレスのリスト"
#   type        = list(string)
#   default     = []
# }

# ============================================================================
# Blobコンテナおよびアップロード用の変数
# ============================================================================

variable "container_name" {
  description = "Blob Storageコンテナの名前。小文字、数字、ハイフンのみ使用可能"
  type        = string
  default     = "example-container"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.container_name))
    error_message = "container_nameは小文字、数字、ハイフンのみで、3-63文字である必要があります。"
  }
}

variable "blob_name" {
  description = "アップロードするBlobの名前"
  type        = string
  default     = "sample.txt"
}

variable "local_file_path" {
  description = "ローカルファイルシステム上のアップロード対象ファイルのパス"
  type        = string
  default     = "./sample.txt"
}

variable "sas_token_expiry" {
  description = "SASトークンの有効期間（Go duration形式: 24h, 168h, 720hなど）"
  type        = string
  default     = "24h"
}