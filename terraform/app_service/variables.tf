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
  default     = "asp-chatbot-dev"

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
    Azure OpenAI チャットボットでは npm install のメモリ消費が大きいため、
    F1 で動作しない場合は B1 以上を推奨。
  EOT
  type        = string
  default     = "B1"

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
  default     = "webapp-chatbot-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.web_app_name))
    error_message = "Web App名は英数字とハイフンのみで、2-60文字の長さである必要があります。"
  }
}

# ----------------------------------------------------------------------------
# Azure OpenAI（Cognitive Services）関連の変数
# ----------------------------------------------------------------------------
variable "openai_account_name" {
  description = <<-EOT
    Azure OpenAI アカウント名。
    custom_subdomain_name にも同じ値が使われるため、グローバルで一意である必要がある。
    エンドポイントは https://<name>.openai.azure.com/ になる。
  EOT
  type        = string
  default     = "aoai-chatbot-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,64}$", var.openai_account_name))
    error_message = "openai_account_name は英数字とハイフンのみで、2-64文字の長さである必要があります。"
  }
}

variable "openai_location" {
  description = <<-EOT
    Azure OpenAI リソースをデプロイするリージョン。
    モデルの提供状況はリージョンごとに異なるため、利用したいモデル（既定: gpt-4o-mini）
    の対応リージョンを必ず確認すること:
    https://learn.microsoft.com/azure/ai-services/openai/concepts/models#model-summary-table-and-region-availability
  EOT
  type        = string
  default     = "Japan East"
}

variable "openai_sku_name" {
  description = "Azure OpenAI アカウントの SKU（通常は S0 のみ）"
  type        = string
  default     = "S0"
}

variable "openai_deployment_name" {
  description = "Azure OpenAI 上のモデルデプロイ名（アプリが指定する deployment 名）"
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_name" {
  description = "デプロイするモデル名"
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  description = "デプロイするモデルのバージョン"
  type        = string
  default     = "2024-07-18"
}

variable "openai_deployment_sku" {
  description = <<-EOT
    モデルデプロイのスケールタイプ（azurerm 3.x では cognitive_deployment.scale.type にマップ）。
    主な選択肢:
      - GlobalStandard: 推奨。Japan East を含む多くのリージョンで gpt-4o-mini を提供
      - Standard: 一部リージョン限定（Japan East では gpt-4o-mini 非対応）
      - ProvisionedManaged: 予約スループット用
    リージョン × モデル × SKU の対応表:
    https://learn.microsoft.com/azure/ai-services/openai/concepts/models#model-summary-table-and-region-availability
  EOT
  type        = string
  default     = "GlobalStandard"
}

variable "openai_deployment_capacity" {
  description = "モデルデプロイの TPM 容量（1 = 1000 TPM 単位）"
  type        = number
  default     = 1
}

variable "openai_api_version" {
  description = "アプリが呼び出す Azure OpenAI の API バージョン"
  type        = string
  default     = "2024-10-21"
}

# ----------------------------------------------------------------------------
# タグ関連の変数
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグのマップ（コスト管理や整理に便利）"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "AzureOpenAIChatbot"
    ManagedBy   = "Terraform"
  }
}
