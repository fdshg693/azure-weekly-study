# ============================================================================
# AI Gateway プロジェクト — ステップ0: IaC 土台
# ============================================================================
# このファイルが作るのは「土台」だけ:
#   - リソースグループ
#   - Azure OpenAI（Cognitive Services / kind=OpenAI）アカウント本体
#   - 実行者（自分）への RBAC ロール割り当て（管理用 + 推論用）
#
# 敢えて作らないもの:
#   - モデルデプロイ（azurerm_cognitive_deployment）
#     → 後続ステップで「管理 UI からコントロールプレーン経由で作る」対象として残す。
#       ここで作ってしまうと、本プロジェクトの主目的（デプロイ操作の体験）が薄れる。
# 設計の全体像と各ステップは PLAN.md を参照。

# 現在の実行者（az login しているユーザー/SP）の情報。
# ロール割り当ての principal_id（object_id）に使う。
data "azurerm_client_config" "current" {}

# ============================================================================
# リソースグループ
# ============================================================================
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================================
# Azure OpenAI（Cognitive Services）アカウント
# ============================================================================
# custom_subdomain_name は Microsoft Entra（旧 AAD）トークンでの認証に必須。
# これが無いと Managed Identity / az login トークン経由の呼び出しが失敗する。
resource "azurerm_cognitive_account" "openai" {
  name                  = var.openai_account_name
  location              = var.openai_location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku_name
  custom_subdomain_name = var.openai_account_name

  # 既定は false（キーレス強制）。理由は variables.tf の local_auth_enabled を参照。
  local_auth_enabled = var.local_auth_enabled

  tags = var.tags
}

# ============================================================================
# ロール割り当て: 実行者（自分） → Azure OpenAI
# ============================================================================
# 管理（コントロールプレーン）と推論（データプレーン）で必要ロールが違う、が学習の肝。
#   - 推論呼び出し                : Cognitive Services OpenAI User
#   - モデルデプロイの作成・削除  : Cognitive Services Contributor
# count で assign_roles_to_current_user による on/off を切り替える
# （Owner/User Access Administrator 権限が無い環境では false にして手動付与する）。

# 推論（データプレーン）用
resource "azurerm_role_assignment" "current_user_openai_user" {
  count                = var.assign_roles_to_current_user ? 1 : 0
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# 管理（コントロールプレーン: デプロイ作成・削除）用
resource "azurerm_role_assignment" "current_user_contributor" {
  count                = var.assign_roles_to_current_user ? 1 : 0
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
