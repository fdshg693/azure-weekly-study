# ============================================================================
# 変数定義ファイル
# ============================================================================

# ----------------------------------------------------------------------------
# リソースグループ関連の変数
# ----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "リソースグループの名前"
  type        = string
  default     = "rg-chatbot-dev-seiwan"
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
  default     = "asp-chatbot-dev-seiwan"

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
  # 命名規約（規約A）: デプロイ名はモデル名と一致させる。アプリ（app/config/models.js）は
  # この名前を直接参照するため、変更する場合は config/models.js の chat.deployment も揃えること。
  description = "Azure OpenAI 上のモデルデプロイ名（= モデル名。app/config/models.js と一致させる）"
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

# 注: api-version は「秘密でないアプリ設定」なので Terraform では管理しない。
# モデルごとの api-version は app/config/models.js に集約している（コミット対象）。

# ----------------------------------------------------------------------------
# gpt-5 デプロイ（Responses API 用）
# ----------------------------------------------------------------------------
# gpt-5 は推論モデルで Responses API（reasoning.effort 等）に対応する。
# gpt-4o-mini デプロイとは別に共存させ、アプリは app/config/models.js の reasoning から参照する。
variable "openai_gpt5_deployment_name" {
  # 命名規約（規約A）: デプロイ名 = モデル名。アプリは app/config/models.js の
  # reasoning.deployment でこの名前を直接参照するため、変更時は両方を揃えること。
  description = "gpt-5 のデプロイ名（= モデル名。app/config/models.js と一致させる）"
  type        = string
  default     = "gpt-5"
}

variable "openai_gpt5_model_name" {
  description = "デプロイする gpt-5 系モデル名"
  type        = string
  default     = "gpt-5"
}

variable "openai_gpt5_model_version" {
  description = "gpt-5 モデルのバージョン（Japan East で利用可能なもの）"
  type        = string
  default     = "2025-08-07"
}

variable "openai_gpt5_deployment_capacity" {
  description = "gpt-5 デプロイの TPM 容量（1 = 1000 TPM 単位）。サブスクリプションのクォータ範囲で設定する。"
  type        = number
  default     = 1
}

# ----------------------------------------------------------------------------
# Microsoft Entra ID (App Registration) / Microsoft Graph 関連の変数
# ----------------------------------------------------------------------------
# これらの値は事前に Entra ID 側で App Registration を作成して取得する。
# 手順は README の「Entra ID 認証 + Graph API」を参照。
# 未設定 (空文字) の場合、/profile ページは 503 を返し既存チャット機能は影響を受けない。
variable "entra_tenant_id" {
  description = "Entra ID テナント ID (App Registration の Directory (tenant) ID)。空文字なら認証無効"
  type        = string
  default     = ""
}

variable "entra_client_id" {
  description = "App Registration のアプリケーション (クライアント) ID。空文字なら認証無効"
  type        = string
  default     = ""
}

variable "entra_client_secret" {
  description = "App Registration のクライアントシークレット。空文字なら認証無効"
  type        = string
  default     = ""
  sensitive   = true
}

variable "express_session_secret" {
  description = "express-session の署名用シークレット。本番では必ず強いランダム値を設定すること"
  type        = string
  default     = ""
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Key Vault（Tavily API キーなど外部秘密値の保管）関連の変数
# ----------------------------------------------------------------------------
variable "key_vault_name" {
  description = <<-EOT
    Key Vault 名。グローバルで一意である必要がある。
    Tavily の API キーなど、Azure と独立した外部サービスの秘密値を保管する。
    命名規則: 英数字とハイフン、3-24文字、先頭は英字。
  EOT
  type        = string
  default     = "kv-chatbot-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "key_vault_name は英字始まり・英数字とハイフン・3-24文字である必要があります。"
  }
}

variable "tavily_secret_name" {
  description = <<-EOT
    Tavily API キーを格納する Key Vault シークレットの名前。
    アプリ（tools.js）の TAVILY_SECRET_NAME と一致させること。
    値そのものは Terraform では管理せず `az keyvault secret set` で投入する。
  EOT
  type        = string
  default     = "tavily-api-key"
}

# ----------------------------------------------------------------------------
# 共有メモ機能（Azure Function + Table Storage）関連の変数
# ----------------------------------------------------------------------------
variable "memo_storage_account_name" {
  description = <<-EOT
    メモ保存用 Storage Account 名。グローバルで一意・小文字英数字のみ・3-24文字。
    Function の MI が "Storage Table Data Contributor" でキーレス読み書きする。
  EOT
  type        = string
  default     = "stchatbotmemoseiwan"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.memo_storage_account_name))
    error_message = "memo_storage_account_name は小文字英数字のみ・3-24文字である必要があります。"
  }
}

variable "memo_table_name" {
  description = "メモを格納する Table 名（Function の MEMO_TABLE_NAME と一致させる）"
  type        = string
  default     = "memos"
}

variable "func_service_plan_name" {
  description = "メモ Function 用 App Service Plan 名（Consumption/Y1）"
  type        = string
  default     = "asp-func-chatbot-dev-seiwan"
}

variable "func_app_name" {
  description = <<-EOT
    メモ CRUD Function App 名。グローバルで一意。
    URL は https://<name>.azurewebsites.net、API は /api/memos。
    アプリ（app/.env / App Settings）の MEMO_API_BASE_URL に同じホストを設定する。
  EOT
  type        = string
  default     = "func-chatbot-memo-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.func_app_name))
    error_message = "func_app_name は英数字とハイフンのみ・2-60文字である必要があります。"
  }
}

variable "memo_required_role" {
  description = "メモ Function が要求する app role 名（Function の MEMO_REQUIRED_ROLE と一致）"
  type        = string
  default     = "Memo.ReadWrite"
}

# memo_api_app_id は scripts/memo-api/setup-memo-api.ps1 が作る App Registration の appId。
# 空のままなら Function の EasyAuth は無効（保護なしで疎通だけ試せる）。
# 設定すると EasyAuth が有効化され、aud=api://<appId> のトークンのみ通す。
# 値はスクリプトが memo.auto.tfvars に書き出す（*.tfvars は .gitignore 済み）。
variable "memo_api_app_id" {
  description = "メモ Function を保護する Entra App Registration の appId（空なら EasyAuth 無効）"
  type        = string
  default     = ""
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
