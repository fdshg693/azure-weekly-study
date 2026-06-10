# ============================================================================
# Application Insights の定義
# ============================================================================
# Azure Functions の監視・ログ分析用リソース
# 関数の実行回数、レスポンスタイム、エラー率などをリアルタイムで監視できます

resource "azurerm_application_insights" "func" {
  name                = var.application_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # application_type: アプリケーションの種類
  # web: Webアプリケーション/API（Azure Functions はこちら）
  # other: その他のアプリケーション
  application_type = "web"

  # Log Analytics ワークスペース（一度設定すると削除不可）
  workspace_id = "/subscriptions/4b6965ad-aae6-499a-82e6-320669f7d2a5/resourceGroups/DefaultResourceGroup-EJP/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-4b6965ad-aae6-499a-82e6-320669f7d2a5-EJP"

  tags = var.tags
}

# ============================================================================
# Azure Function App の定義
# ============================================================================
# Python v2 プログラミングモデルを使用する Linux Function App
# デプロイ対象: azure_func/projects/simple/function_app.py

resource "azurerm_linux_function_app" "main" {
  name                = var.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # ホスティングプラン（Consumption or Premium）
  service_plan_id = azurerm_service_plan.func.id

  # Azure Functions ランタイムに必要な Storage Account
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key

  # ============================================================================
  # サイト設定
  # ============================================================================
  site_config {
    # application_stack: ランタイムスタックの設定
    application_stack {
      # Python バージョン（azure_func/projects/simple で使用するバージョン）
      python_version = var.python_version
    }

    # CORS（Cross-Origin Resource Sharing）設定
    # - Azure Portal からの関数テストを許可
    # - Static Web Apps から HTMX 経由で呼び出すドメインを許可
    # - Logic App から /api/status を呼ぶのは server-side のため CORS は不要
    cors {
      allowed_origins = [
        "https://portal.azure.com",
        "https://${azurerm_static_web_app.main.default_host_name}",
      ]
    }
  }

  # ============================================================================
  # アプリケーション設定（環境変数）
  # ============================================================================
  app_settings = {
    # Azure Functions のランタイム設定
    # FUNCTIONS_WORKER_RUNTIME: ワーカーランタイムの言語
    "FUNCTIONS_WORKER_RUNTIME" = "python"

    # Application Insights の接続キー（監視・ログ用）
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.func.instrumentation_key

    # Application Insights の接続文字列（新しい方式、推奨）
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.func.connection_string

    # Python v2 プログラミングモデルを有効化
    # v2 モデルでは function.json を使わず、デコレーター（@app.route 等）で定義
    "AzureWebJobsFeatureFlags" = "EnableWorkerIndexing"

    # ビルド時にリモートでパッケージを構築する設定
    # true にすると、デプロイ時に requirements.txt から依存関係をインストール
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"

    # ------------------------------------------------------------------
    # Worker Function（Service Bus トリガー）用の設定
    # ------------------------------------------------------------------
    # ServiceBusConnection: Worker の @app.service_bus_queue_trigger(connection=...) と一致させる
    "ServiceBusConnection" = azurerm_servicebus_namespace_authorization_rule.shared.primary_connection_string

    # ワーカーが「重い処理」を模擬するためのスリープ秒数。
    # Logic App 側の Until ループは 3 秒 × 60 回 = 最大 3 分の余裕がある
    "WORKER_SLEEP_SECONDS" = tostring(var.worker_sleep_seconds)

    # ------------------------------------------------------------------
    # /api/async-random プロキシ（案B）用の Logic App 呼び出し URL
    # ------------------------------------------------------------------
    # ブラウザに SAS 署名付き callback URL を露出させずに済むよう、
    # サーバ側（このプロキシ）にだけ知らせる。
    #
    # 循環依存ではない: function_app は callback_url（trigger_http_request の
    # 作成完了時点で確定）に依存し、logic_app の until_done アクションは
    # function_app.default_hostname（function_app 作成完了時点で確定）に依存する。
    # default_hostname は app_settings 更新で変わらないので Terraform は
    # workflow → trigger → function_app → actions の順で素直に解決できる。
    "LOGIC_APP_CALLBACK_URL" = azurerm_logic_app_trigger_http_request.request.callback_url
  }

  # HTTPS のみ許可（セキュリティ推奨設定）
  https_only = true

  tags = var.tags
}
