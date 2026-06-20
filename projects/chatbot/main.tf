# ============================================================================
# App Service プロジェクト - メインリソース定義
# ============================================================================
# Azure App Service 上で動く Azure OpenAI チャットボット
#   - Linux Web App (Node.js 20 LTS) で Express + EJS アプリをホスト
#   - Azure OpenAI に gpt-4o-mini をデプロイ
#   - Web App のシステム割り当てマネージド ID から Azure OpenAI を呼び出す
#     （DefaultAzureCredential によりキー不要）
# 参考: https://learn.microsoft.com/en-us/azure/app-service/tutorial-ai-openai-chatbot-node

# 現在の実行者（デプロイ担当者）の情報。Key Vault の tenant_id や、
# シークレット投入権限（Secrets Officer）をこの人物に付与するために使う。
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
# これがないとマネージド ID 経由の呼び出しが失敗する。

resource "azurerm_cognitive_account" "openai" {
  name                  = var.openai_account_name
  location              = var.openai_location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku_name
  custom_subdomain_name = var.openai_account_name

  # ローカル認証（API キー）を無効化し、Entra ID 認証のみを許可する場合は true に
  local_auth_enabled = true

  tags = var.tags
}

# ============================================================================
# Azure OpenAI モデルデプロイ（gpt-4o-mini）
# ============================================================================

resource "azurerm_cognitive_deployment" "chat" {
  name                 = var.openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }

  scale {
    type     = var.openai_deployment_sku
    capacity = var.openai_deployment_capacity
  }
}

# ============================================================================
# Azure OpenAI モデルデプロイ（gpt-5 / Responses API 用）
# ============================================================================
# gpt-5 は推論モデルで Responses API に対応する（gpt-4o-mini は非推論モデルのため
# reasoning.effort 等を受け付けない）。チャットの /chat は Responses API を使うため、
# gpt-4o-mini とは別にこの gpt-5 デプロイを用意し、アプリはこちらを参照する。
# depends_on: 同一 Cognitive アカウント配下のデプロイ作成は直列化しておくと衝突を避けられる。
resource "azurerm_cognitive_deployment" "gpt5" {
  name                 = var.openai_gpt5_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.openai_gpt5_model_name
    version = var.openai_gpt5_model_version
  }

  scale {
    type     = "GlobalStandard"
    capacity = var.openai_gpt5_deployment_capacity
  }

  depends_on = [azurerm_cognitive_deployment.chat]
}

# ============================================================================
# App Service Plan
# ============================================================================
# F1 でも動作するが、Express + openai SDK の npm install は数百 MB を扱うため、
# 初回ビルドでメモリ不足になる場合は B1 以上にアップグレードすることを推奨。

resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku

  tags = var.tags
}

# ============================================================================
# Linux Web App（チャットボット本体）
# ============================================================================

resource "azurerm_linux_web_app" "main" {
  name                = var.web_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  # システム割り当てマネージド ID を有効化。
  # この principal_id を Cognitive Services 側に "Cognitive Services OpenAI User"
  # ロールとして割り当てることで、コードからキーレスで OpenAI を呼び出せる。
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = false

    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    # zip デプロイ後に Oryx で `npm install` を走らせる
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"

    # アプリが参照する Azure OpenAI 接続情報（キーは持たない）
    "AZURE_OPENAI_ENDPOINT"    = azurerm_cognitive_account.openai.endpoint
    "AZURE_OPENAI_DEPLOYMENT"  = azurerm_cognitive_deployment.chat.name
    "AZURE_OPENAI_API_VERSION" = var.openai_api_version
    # Responses API 用の gpt-5 デプロイ名と api-version（/chat はこちらを使う）。
    # Chat Completions 用 (AZURE_OPENAI_*) とはキーを分け、両モデルを併用可能にする。
    "AZURE_OPENAI_RESPONSES_DEPLOYMENT"  = azurerm_cognitive_deployment.gpt5.name
    "AZURE_OPENAI_RESPONSES_API_VERSION" = var.openai_responses_api_version

    # express-session を本番モード (secure cookie) で動かす
    "NODE_ENV"               = "production"
    "EXPRESS_SESSION_SECRET" = var.express_session_secret

    # Tavily リモート MCP（Web 検索）用の設定。
    # キー本体は App Setting には持たせず、アプリが実行時に Key Vault から取得する。
    # ここでは「どの Key Vault のどのシークレットを見るか」だけを渡す。
    # KEY_VAULT_URI が未設定だとアプリは env(TAVILY_API_KEY) にフォールバックする。
    "KEY_VAULT_URI"      = azurerm_key_vault.main.vault_uri
    "TAVILY_SECRET_NAME" = var.tavily_secret_name

    # Microsoft Entra ID (App Registration) + Microsoft Graph 用の設定
    # 値が空のままだと /profile は 503 を返し既存のチャット機能は影響を受けない
    "CLOUD_INSTANCE"           = "https://login.microsoftonline.com/"
    "TENANT_ID"                = var.entra_tenant_id
    "CLIENT_ID"                = var.entra_client_id
    "CLIENT_SECRET"            = var.entra_client_secret
    "REDIRECT_URI"             = "https://${var.web_app_name}.azurewebsites.net/auth/redirect"
    "POST_LOGOUT_REDIRECT_URI" = "https://${var.web_app_name}.azurewebsites.net/"
    "GRAPH_API_ENDPOINT"       = "https://graph.microsoft.com/"
  }

  https_only = true

  tags = var.tags
}

# ============================================================================
# ロール割り当て: Web App のマネージド ID → Azure OpenAI
# ============================================================================
# "Cognitive Services OpenAI User" は推論呼び出しに必要な最小権限。
# モデルデプロイの管理まで行う場合は "Cognitive Services OpenAI Contributor"。

resource "azurerm_role_assignment" "webapp_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# ============================================================================
# Key Vault（Tavily API キーなど、Azure と独立した秘密値の保管庫）
# ============================================================================
# 設計意図:
#   - Tavily の API キーは Azure リソースとは無関係な外部サービスの秘密値。
#     これを App Setting（環境変数）に直書きすると、値の変更＝App Service 再起動になり、
#     かつ Terraform state にも値が残ってしまう。
#   - そこで Key Vault に置き、アプリは実行時にマネージド ID で読む（OpenAI と同じキーレス方式）。
#     キーをローテーションしても、アプリ側の TTL キャッシュが切れれば再起動なしで反映される。
#   - 重要: シークレットの「値」は Terraform では管理しない（state に残さない）。
#     Vault と権限だけ TF で作り、値は `az keyvault secret set`（just tavily-set）で投入する。
#     → variables.tf にキーを置かずに済み、"Azure と独立した秘密値" の扱いがきれいになる。

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # アクセスポリシーではなく Azure RBAC で権限管理する（ロール割り当てで制御）。
  enable_rbac_authorization = true

  # 学習用に削除・作り直しをしやすくする設定（本番では purge_protection を有効に）。
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = var.tags
}

# デプロイ実行者（自分）に「Secrets Officer」を付与。
# これがないと `az keyvault secret set` でキーを投入できない（RBAC 認可のため）。
resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Web App のマネージド ID に「Secrets User」を付与（シークレットの読み取りのみ）。
# アプリはこの権限で Tavily キーを取得する。書き込み権限は与えない（最小権限）。
resource "azurerm_role_assignment" "webapp_kv_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}
