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
  default     = "rg-azure-func-dev"
}

variable "location" {
  description = "Azureリソースをデプロイするリージョン"
  type        = string
  default     = "Japan East"
}

# ----------------------------------------------------------------------------
# Storage Account関連の変数
# ----------------------------------------------------------------------------
variable "storage_account_name" {
  description = <<-EOT
    Azure Functions用のStorage Account名。
    Function Appのランタイムに必要なストレージ（関数コード、ログ、状態管理）。
    命名規則:
      - 小文字と数字のみ使用可能
      - 3-24文字の長さ制限
      - グローバルで一意である必要があります
  EOT
  type        = string
  default     = "stfuncdev001seiwan"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage Account名は小文字と数字のみで、3-24文字の長さである必要があります。"
  }
}

# ----------------------------------------------------------------------------
# Function App関連の変数
# ----------------------------------------------------------------------------
variable "function_app_name" {
  description = <<-EOT
    Azure Function Appの名前。
    この名前はグローバルで一意である必要があります（URLの一部になるため）。
    例: func-myapp-dev → https://func-myapp-dev.azurewebsites.net
  EOT
  type        = string
  default     = "func-simple-dev-seiwan"
}

variable "python_version" {
  description = <<-EOT
    Python ランタイムのバージョン。
    Azure Functions でサポートされているバージョン:
      - 3.9, 3.10, 3.11, 3.12, 3.13
    プロジェクトの pyproject.toml に合わせて設定してください。
  EOT
  type        = string
  default     = "3.11"

  validation {
    condition     = contains(["3.9", "3.10", "3.11", "3.12", "3.13"], var.python_version)
    error_message = "python_versionは '3.9', '3.10', '3.11', '3.12', '3.13' のいずれかである必要があります。"
  }
}

# ----------------------------------------------------------------------------
# App Service Plan関連の変数
# ----------------------------------------------------------------------------
variable "service_plan_name" {
  description = "App Service Plan（関数ホスティングプラン）の名前"
  type        = string
  default     = "JapanEastLinuxDynamicPlan"
}

variable "service_plan_sku" {
  description = <<-EOT
    App Service PlanのSKU（価格プラン）。
    オプション:
      - Y1: Consumptionプラン（サーバーレス、使った分だけ課金、コールドスタートあり）
      - EP1: Elastic Premium v1（1vCPU, 3.5GB RAM、常時接続、VNet統合対応）
      - EP2: Elastic Premium v2（2vCPU, 7GB RAM）
      - EP3: Elastic Premium v3（4vCPU, 14GB RAM）
      - B1: Basic（開発/テスト向け、低コスト）

    開発環境には Y1（Consumption）を推奨（無料枠あり: 月100万回実行、400,000 GB-s）
  EOT
  type        = string
  default     = "Y1"
}

# ----------------------------------------------------------------------------
# Application Insights関連の変数
# ----------------------------------------------------------------------------
variable "application_insights_name" {
  description = "Application Insights（監視・ログ分析）リソースの名前"
  type        = string
  default     = "func-simple-dev-seiwan"
}

# ----------------------------------------------------------------------------
# デプロイ関連の変数
# ----------------------------------------------------------------------------
variable "function_app_source_dir" {
  description = <<-EOT
    Azure Functions のソースコードが格納されているディレクトリパス。
    このディレクトリ内の function_app.py、host.json、requirements.txt 等が
    Function App にデプロイされます。
  EOT
  type        = string
  default     = "../../azure_func/projects/simple"
}

# ----------------------------------------------------------------------------
# タグ関連の変数
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグのマップ（コスト管理や整理に便利）"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "AzureFunctionsDemo"
    ManagedBy   = "Terraform"
  }
}
