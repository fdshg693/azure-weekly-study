# ============================================================================
# 変数定義ファイル
# ============================================================================

# ----------------------------------------------------------------------------
# リソースグループ関連の変数
# ----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "リソースグループの名前"
  type        = string
  default     = "rg-app-service-dev"
}

variable "location" {
  description = "Azureリソースをデプロイするリージョン"
  type        = string
  default     = "Japan East"
}

# ----------------------------------------------------------------------------
# App Service Plan 関連の変数
# ----------------------------------------------------------------------------
variable "app_service_plan_name" {
  description = <<-EOT
    App Service Plan の名前。
    App Service Plan はアプリをホストする仮想マシン群（ワーカー）を定義する。
    命名規則:
      - 英数字とハイフンのみ使用可能
      - 1-60文字の長さ制限
  EOT
  type        = string
  default     = "asp-minimal-site-dev"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,60}$", var.app_service_plan_name))
    error_message = "App Service Plan名は英数字とハイフンのみで、1-60文字の長さである必要があります。"
  }
}

variable "app_service_plan_sku" {
  description = <<-EOT
    App Service Plan の SKU（価格プラン）。
    オプション:
      - F1: Free プラン（無料枠、開発・テスト向け、60分/日の CPU 制限あり）
      - B1: Basic プラン（小規模本番向け、カスタムドメイン対応）
      - S1: Standard プラン（本番向け、スケールアウト対応）
    開発環境には F1 を推奨
  EOT
  type        = string
  default     = "F1"

  validation {
    condition     = contains(["F1", "B1", "S1", "P1v2", "P1v3"], var.app_service_plan_sku)
    error_message = "app_service_plan_skuは 'F1', 'B1', 'S1', 'P1v2', 'P1v3' のいずれかである必要があります。"
  }
}

# ----------------------------------------------------------------------------
# Web App 関連の変数
# ----------------------------------------------------------------------------
variable "web_app_name" {
  description = <<-EOT
    Web App の名前。
    この名前が URL の一部になる: https://<name>.azurewebsites.net
    命名規則:
      - 英数字とハイフンのみ使用可能
      - 2-60文字の長さ制限
      - グローバルで一意である必要がある
  EOT
  type        = string
  default     = "webapp-minimal-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.web_app_name))
    error_message = "Web App名は英数字とハイフンのみで、2-60文字の長さである必要があります。"
  }
}

# ----------------------------------------------------------------------------
# タグ関連の変数
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグのマップ（コスト管理や整理に便利）"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "AppServiceDemo"
    ManagedBy   = "Terraform"
  }
}
