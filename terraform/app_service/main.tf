# ============================================================================
# App Service プロジェクト - メインリソース定義
# ============================================================================
# Azure App Service を使って最小限の Web サイトをデプロイする構成
# Free プラン（F1）で Linux + Node.js ランタイムを使用

# ============================================================================
# リソースグループ
# ============================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================================
# App Service Plan
# ============================================================================
# Web App を実行する基盤（コンピューティングリソース）を定義
#
# os_type:
#   - "Linux": Linux コンテナー上でアプリを実行（推奨）
#   - "Windows": Windows 上でアプリを実行
#
# sku_name:
#   Free (F1) プランはコスト 0 で開発・検証に最適
#   ただし常時接続（Always On）やカスタムドメインの SSL は使えない

resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku

  tags = var.tags
}

# ============================================================================
# Linux Web App
# ============================================================================
# 実際にアプリケーションをホストするリソース
#
# site_config 内の application_stack でランタイムを選択:
#   - node_version: Node.js（"18-lts", "20-lts" 等）
#   - python_version: Python（"3.11", "3.12" 等）
#   - dotnet_version: .NET（"6.0", "8.0" 等）
#   - java_version: Java（"17", "21" 等）
#
# このプロジェクトでは Node.js 20 LTS を使用し、
# 組み込みのデフォルトページを表示する最小構成とする

resource "azurerm_linux_web_app" "main" {
  name                = var.web_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  # ---------------------------------------------------------------------------
  # サイト設定
  # ---------------------------------------------------------------------------
  site_config {
    # always_on: アプリを常時起動状態にするか
    # Free/Shared プランでは false にする必要がある
    always_on = false

    # application_stack: アプリのランタイムを指定
    application_stack {
      node_version = "20-lts"
    }
  }

  # ---------------------------------------------------------------------------
  # アプリ設定（環境変数）
  # ---------------------------------------------------------------------------
  app_settings = {
    # WEBSITE_NODE_DEFAULT_VERSION は Linux App Service では不要だが明示的に設定
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }

  # ---------------------------------------------------------------------------
  # HTTPS 設定
  # ---------------------------------------------------------------------------

  # https_only: HTTP アクセスを HTTPS にリダイレクト
  https_only = true

  tags = var.tags
}
