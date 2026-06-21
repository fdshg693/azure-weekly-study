# ============================================================================
# 変数定義（ステップ0: IaC 土台）
# ============================================================================
# このステップでは「Azure OpenAI リソース本体」と「RBAC ロール割り当て」だけを
# 変数化する。モデルデプロイは敢えてここで作らず、後続ステップでアプリ
# （コントロールプレーン操作）から作る対象として残す。詳細は PLAN.md を参照。

# ----------------------------------------------------------------------------
# リソースグループ
# ----------------------------------------------------------------------------
variable "resource_group_name" {
  description = "リソースグループの名前"
  type        = string
  default     = "rg-aigw-dev-seiwan"
}

variable "location" {
  description = "リソースグループを作成するリージョン"
  type        = string
  default     = "Japan East"
}

# ----------------------------------------------------------------------------
# Azure OpenAI（Cognitive Services）アカウント
# ----------------------------------------------------------------------------
variable "openai_account_name" {
  description = <<-EOT
    Azure OpenAI アカウント名。
    custom_subdomain_name にも同じ値が使われるため、グローバルで一意である必要がある。
    エンドポイントは https://<name>.openai.azure.com/ になる。
  EOT
  type        = string
  default     = "aoai-aigw-dev-seiwan"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,64}$", var.openai_account_name))
    error_message = "openai_account_name は英数字とハイフンのみで、2-64文字の長さである必要があります。"
  }
}

variable "openai_location" {
  description = <<-EOT
    Azure OpenAI リソースをデプロイするリージョン。
    モデルの提供状況はリージョンごとに異なる。後続ステップでデプロイするモデルの
    対応リージョンを確認すること:
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

variable "local_auth_enabled" {
  description = <<-EOT
    API キー認証（ローカル認証）を有効にするか。
    本プロジェクトは「認証は Managed Identity / Entra ID を基本、API キー管理は将来機能」
    という設計（PLAN.md §5）。そのため既定は false（= キーレス強制）にしている。
    推論・管理ともに az login / Managed Identity のトークンで行う。
    どうしても API キーで試したい場合のみ true にする。
  EOT
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------
# RBAC ロール割り当て
# ----------------------------------------------------------------------------
# ステップ0 ではアプリをまだホストしないため、ローカル開発で使う「実行者（自分）」の
# Entra ID（az login のユーザー/SP）に対してロールを割り当てる。
# 管理（コントロールプレーン）と推論（データプレーン）で必要なロールが違う点が学習ポイント。
variable "assign_roles_to_current_user" {
  description = <<-EOT
    現在の実行者（az login しているユーザー/SP）に Azure OpenAI のロールを自動付与するか。
    付与するロール:
      - Cognitive Services OpenAI User       … 推論（データプレーン）
      - Cognitive Services Contributor       … モデルデプロイの作成・削除（コントロールプレーン）
    付与にはサブスクリプションで Owner / User Access Administrator 権限が必要。
    権限が無い環境では false にし、別途手動で付与する（justfile / README 参照）。
  EOT
  type        = bool
  default     = true
}

# ----------------------------------------------------------------------------
# タグ
# ----------------------------------------------------------------------------
variable "tags" {
  description = "リソースに適用するタグのマップ（コスト管理や整理に便利）"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "AIGateway"
    ManagedBy   = "Terraform"
  }
}
