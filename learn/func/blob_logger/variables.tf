# ============================================================================
# 変数定義
# ============================================================================
# Storage Account 名と Function App 名はグローバル一意である必要があるため、
# 他プロジェクトと衝突しないよう専用の prefix / suffix を割り当てている。

# ----------------------------------------------------------------------------
# 共通
# ----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "リソースグループの名前"
  type        = string
  default     = "rg-func-blob-logger-dev"
}

variable "location" {
  description = "Azure リソースをデプロイするリージョン"
  type        = string
  default     = "Japan East"
}

# ----------------------------------------------------------------------------
# Storage Account（Function ランタイム兼 入出力データ用）
# ----------------------------------------------------------------------------
# 学習をシンプルにするため、1 つの Storage Account を以下の両方に使う:
#   1. Function App のランタイムストレージ（AzureWebJobsStorage）
#   2. アップロード元（uploads コンテナ）/ ログ出力先（logs コンテナ）
# 本番では「ランタイム用」と「データ用」を分けるのが定石。
variable "storage_account_name" {
  description = "Storage Account の名前（グローバル一意 / 小文字+数字 / 3-24 文字）"
  type        = string
  default     = "stbloblogdevseiwan"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage Account 名は小文字+数字、3-24 文字である必要があります。"
  }
}

variable "uploads_container_name" {
  description = "ファイルをアップロードする入力コンテナ名（Blob トリガーが監視する）"
  type        = string
  default     = "uploads"
}

variable "logs_container_name" {
  description = "ログを書き出す出力コンテナ名（トリガーとは別コンテナ）"
  type        = string
  default     = "logs"
}

# ----------------------------------------------------------------------------
# Function App
# ----------------------------------------------------------------------------
variable "function_app_name" {
  description = "Function App の名前（グローバル一意）"
  type        = string
  default     = "func-blob-logger-dev-seiwan"
}

variable "service_plan_name" {
  description = "App Service Plan（Linux Consumption / Y1）の名前"
  type        = string
  default     = "JapanEastLinuxDynBlobLogger"
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

# ----------------------------------------------------------------------------
# 監視（Application Insights / Log Analytics）
# ----------------------------------------------------------------------------
variable "application_insights_name" {
  description = "Application Insights リソースの名前"
  type        = string
  default     = "appi-blob-logger-dev-seiwan"
}

variable "log_analytics_workspace_name" {
  description = "Log Analytics Workspace の名前（Application Insights のバックエンド）"
  type        = string
  default     = "log-blob-logger-dev-seiwan"
}

variable "log_analytics_retention_days" {
  description = "Log Analytics のログ保持日数（30〜730 日 / 開発はコスト最小化のため 30）"
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days は 30〜730 の範囲で指定してください。"
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
    Project     = "FuncBlobLogger"
    ManagedBy   = "Terraform"
  }
}
