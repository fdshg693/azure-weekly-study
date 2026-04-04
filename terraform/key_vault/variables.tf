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
  default     = "rg-key-vault-dev"
}

variable "location" {
  description = "Azureリソースをデプロイするリージョン"
  type        = string
  default     = "Japan East"
}

# ----------------------------------------------------------------------------
# Key Vault関連の変数
# ----------------------------------------------------------------------------
variable "key_vault_name" {
  description = <<-EOT
    Azure Key Vaultの名前。
    Key Vaultはシークレット（パスワード、APIキー、接続文字列など）を
    安全に保管・管理するためのサービス。
    命名規則:
      - 英数字とハイフンのみ使用可能
      - 3-24文字の長さ制限
      - 先頭は英字である必要があります
      - グローバルで一意である必要があります（URLの一部になるため）
      - 例: kv-myapp-dev → https://kv-myapp-dev.vault.azure.net
  EOT
  type        = string
  default     = "kv-simple-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,23}$", var.key_vault_name))
    error_message = "Key Vault名は英字で始まり、英数字とハイフンのみで、3-24文字の長さである必要があります。"
  }
}

variable "key_vault_sku" {
  description = <<-EOT
    Key VaultのSKU（価格プラン）。
    オプション:
      - standard: 標準プラン（ソフトウェアキー保護、ほとんどのユースケースに十分）
      - premium: プレミアムプラン（HSMキー保護、高度なセキュリティ要件向け）
    開発環境には standard を推奨
  EOT
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "key_vault_skuは 'standard' または 'premium' のいずれかである必要があります。"
  }
}

# ----------------------------------------------------------------------------
# シークレット関連の変数
# ----------------------------------------------------------------------------
variable "secret_name" {
  description = <<-EOT
    Key Vaultに格納するシークレットの名前。
    命名規則:
      - 英数字とハイフンのみ使用可能
      - 1-127文字の長さ制限
  EOT
  type        = string
  default     = "sample-secret"
}

variable "secret_value" {
  description = "Key Vaultに格納するシークレットの値（機密情報）"
  type        = string
  default     = "Hello-from-KeyVault!"
  sensitive   = true
}

# ----------------------------------------------------------------------------
# タグ関連の変数
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグのマップ（コスト管理や整理に便利）"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "KeyVaultDemo"
    ManagedBy   = "Terraform"
  }
}
