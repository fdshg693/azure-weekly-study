# ============================================================================
# 変数定義
# ============================================================================
# このプロジェクトでは Key Vault と 2 つの Function App（Reader / Writer）を
# まとめて作成する。それぞれの名前はグローバル一意である必要があるため、
# 既存プロジェクトと衝突しないように専用の prefix を割り当てている。

# ----------------------------------------------------------------------------
# 共通
# ----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "リソースグループの名前"
  type        = string
  default     = "rg-func-kv-split-dev"
}

variable "location" {
  description = "Azure リソースをデプロイするリージョン"
  type        = string
  default     = "Japan East"
}

# ----------------------------------------------------------------------------
# Key Vault
# ----------------------------------------------------------------------------
variable "key_vault_name" {
  description = <<-EOT
    Key Vault の名前（グローバル一意 / 英字始まり / 英数字+ハイフン / 3-24文字）。
    Reader / Writer 両方の Function App から参照される。
  EOT
  type        = string
  default     = "kv-fnsplit-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,23}$", var.key_vault_name))
    error_message = "Key Vault 名は英字で始まり、英数字+ハイフン、3-24 文字である必要があります。"
  }
}

variable "secret_name" {
  description = <<-EOT
    Reader/Writer が共通で操作するシークレットの名前。
    Reader は Key Vault reference 経由で読み取り、Writer は SDK で更新する。
  EOT
  type        = string
  default     = "greeting-name"
}

variable "secret_initial_value" {
  description = "シークレットの初期値（Writer で後から更新可能）"
  type        = string
  default     = "World"
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Function App 共通
# ----------------------------------------------------------------------------
variable "service_plan_name" {
  description = "Reader/Writer 両方で共有する Consumption Plan の名前"
  type        = string
  default     = "JapanEastLinuxDynKvSplit"
}

variable "python_version" {
  description = "Python ランタイムのバージョン（3.9 / 3.10 / 3.11 / 3.12 / 3.13）"
  type        = string
  default     = "3.11"

  validation {
    condition     = contains(["3.9", "3.10", "3.11", "3.12", "3.13"], var.python_version)
    error_message = "python_version は '3.9' / '3.10' / '3.11' / '3.12' / '3.13' のいずれか。"
  }
}

variable "application_insights_name" {
  description = "Application Insights リソースの名前（Reader/Writer で共有）"
  type        = string
  default     = "appi-kv-split-dev-seiwan"
}

variable "log_analytics_workspace_name" {
  description = <<-EOT
    Log Analytics Workspace の名前（Application Insights のバックエンド）。
    Application Insights は Workspace-based モードで紐付けるため必須。
    リソースグループ内で一意。
  EOT
  type        = string
  default     = "log-kv-split-dev-seiwan"
}

variable "log_analytics_retention_days" {
  description = <<-EOT
    Log Analytics のログ保持日数。
    最小 30 日（PerGB2018 SKU の場合の制限）、最大 730 日。
    開発環境はコスト最小化のため 30 日。
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days は 30〜730 の範囲で指定してください。"
  }
}

# ----------------------------------------------------------------------------
# Reader Function App（最小権限：Key Vault Secrets User）
# ----------------------------------------------------------------------------
variable "reader_function_app_name" {
  description = "Reader Function App の名前（グローバル一意）。匿名 GET /api/message を提供。"
  type        = string
  default     = "func-kv-reader-dev-seiwan"
}

variable "reader_storage_account_name" {
  description = "Reader Function App ランタイム用 Storage Account（小文字+数字、3-24 文字）"
  type        = string
  default     = "stfnkvreader1seiwan"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.reader_storage_account_name))
    error_message = "Storage Account 名は小文字+数字、3-24 文字。"
  }
}

# ----------------------------------------------------------------------------
# Writer Function App（昇格権限：Key Vault Secrets Officer + Function キー保護）
# ----------------------------------------------------------------------------
variable "writer_function_app_name" {
  description = "Writer Function App の名前（グローバル一意）。Function キー付き POST /api/secret を提供。"
  type        = string
  default     = "func-kv-writer-dev-seiwan"
}

variable "writer_storage_account_name" {
  description = "Writer Function App ランタイム用 Storage Account（小文字+数字、3-24 文字）"
  type        = string
  default     = "stfnkvwriter1seiwan"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.writer_storage_account_name))
    error_message = "Storage Account 名は小文字+数字、3-24 文字。"
  }
}

# ----------------------------------------------------------------------------
# タグ
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグ"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "FuncKeyVaultSplit"
    ManagedBy   = "Terraform"
  }
}
