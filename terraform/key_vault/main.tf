# ============================================================================
# Key Vault プロジェクト - メインリソース定義
# ============================================================================
# Azure Key Vault を作成し、RBAC でアクセス制御を行い、
# サンプルシークレットを格納する構成

# ============================================================================
# データソース
# ============================================================================

# 現在の Azure クライアント情報を取得
# tenant_id や object_id（ログイン中のユーザー/サービスプリンシパル）を
# 動的に取得するために使用
data "azurerm_client_config" "current" {}

# ============================================================================
# リソースグループ
# ============================================================================
# Key Vault を配置するリソースグループ

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================================
# Key Vault
# ============================================================================
# シークレット（パスワード、APIキー、接続文字列など）を安全に保管するサービス
#
# Key Vault のアクセス制御には2つのモデルがあります:
#   1. アクセスポリシー（Vault access policy）: Key Vault 固有の権限管理
#   2. Azure RBAC: Azure 全体の統一的な権限管理（推奨）
# このプロジェクトでは RBAC を使用します

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # tenant_id: Key Vault が属する Azure AD テナント
  tenant_id = data.azurerm_client_config.current.tenant_id

  # sku_name: 価格プラン（standard / premium）
  sku_name = var.key_vault_sku

  # ---------------------------------------------------------------------------
  # アクセス制御設定
  # ---------------------------------------------------------------------------

  # enable_rbac_authorization: RBAC によるアクセス制御を有効化
  # true にすると、Azure ロール（Key Vault Secrets Officer 等）で権限を管理
  # false の場合はアクセスポリシーで管理（レガシー方式）
  enable_rbac_authorization = true

  # ---------------------------------------------------------------------------
  # データ保護設定
  # ---------------------------------------------------------------------------

  # soft_delete_retention_days: ソフトデリートの保持期間（7-90日）
  # 削除した Key Vault やシークレットを指定日数間は復元可能
  # 開発環境では最短の 7 日に設定
  soft_delete_retention_days = 7

  # purge_protection_enabled: 完全削除保護
  # true にすると、ソフトデリート期間中の完全削除（パージ）を禁止
  # 本番環境では true を推奨。開発環境では false にしておくと再作成が容易
  purge_protection_enabled = false

  # ---------------------------------------------------------------------------
  # ネットワーク設定
  # ---------------------------------------------------------------------------

  # public_network_access_enabled: パブリックネットワークからのアクセスを許可
  # 開発環境では true（CLI からのアクセスに必要）
  # 本番環境ではプライベートエンドポイントと組み合わせて false を推奨
  public_network_access_enabled = true

  tags = var.tags
}

# ============================================================================
# RBAC ロール割り当て
# ============================================================================
# 現在のユーザーに Key Vault Secrets Officer ロールを付与
#
# Key Vault 関連の主なビルトインロール:
#   - Key Vault Administrator: Key Vault 全体の管理（シークレット、キー、証明書）
#   - Key Vault Secrets Officer: シークレットの読み書き・削除
#   - Key Vault Secrets User: シークレットの読み取りのみ
#   - Key Vault Crypto Officer: キーの管理
#   - Key Vault Certificates Officer: 証明書の管理

resource "azurerm_role_assignment" "current_user" {
  # scope: ロールの適用範囲（この Key Vault リソースに限定）
  scope = azurerm_key_vault.main.id

  # role_definition_name: 付与するロール名
  # Secrets Officer でシークレットの CRUD 操作が可能
  role_definition_name = "Key Vault Secrets Officer"

  # principal_id: ロールを付与する対象（現在ログインしているユーザー）
  principal_id = data.azurerm_client_config.current.object_id
}

# ============================================================================
# シークレット
# ============================================================================
# 動作確認用のサンプルシークレットを作成

resource "azurerm_key_vault_secret" "sample" {
  name         = var.secret_name
  value        = var.secret_value
  key_vault_id = azurerm_key_vault.main.id

  # RBAC のロール割り当てが完了してからシークレットを作成する
  # ロール割り当ては反映までに数秒かかる場合がある
  depends_on = [azurerm_role_assignment.current_user]

  tags = var.tags
}
