# ============================================================================
# 全ユーザー共有メモ機能 - Azure Function + Table Storage
# ============================================================================
# 学習テーマ: 「アプリ自身（マネージド ID）の権限で、保護された下流 API を呼ぶ」
#   - メモは全ユーザー共有なので、OBO（サインイン本人の委任）ではなく
#     Web App のシステム割り当て MI で Function を呼ぶ（アプリ間認証）。
#   - Function は EasyAuth（Entra）で保護し、Web App の MI に割り当てた
#     app role（Memo.ReadWrite）を持つトークンだけを受け付ける。
#   - Function 自身も MI で Table Storage をキーレス読み書きする
#     （Storage Table Data Contributor ロール）。
#
# Entra の App Registration / app role 割り当ては Terraform では作らない
# （state に秘密を残さない既存方針）。scripts/setup-memo-api.ps1 で作成し、
# その appId を var.memo_api_app_id 経由で EasyAuth に渡す（空なら EasyAuth オフ）。

# ============================================================================
# Storage Account + Table（メモの保存先）
# ============================================================================
resource "azurerm_storage_account" "memos" {
  name                     = var.memo_storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # 学習用。共有メモのため最小構成（StorageV2 既定）。
  tags = var.tags
}

resource "azurerm_storage_table" "memos" {
  name                 = var.memo_table_name
  storage_account_name = azurerm_storage_account.memos.name
}

# ============================================================================
# Function 専用の App Service Plan（Consumption / Y1）
# ============================================================================
# Web App の B1 プランとは別に、従量課金の Linux プランを用意する
# （関数の実行回数が少ない学習用途では Consumption が最安）。
resource "azurerm_service_plan" "func" {
  name                = var.func_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption
  tags                = var.tags
}

# ============================================================================
# Linux Function App（メモ CRUD API）
# ============================================================================
resource "azurerm_linux_function_app" "memos" {
  name                = var.func_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.func.id

  # Functions ランタイム本体が内部状態に使うストレージ。ここはキー接続でよい
  # （メモ Table のアクセスは別途 MI でキーレスに行う）。
  storage_account_name       = azurerm_storage_account.memos.name
  storage_account_access_key = azurerm_storage_account.memos.primary_access_key

  # Function 自身のシステム割り当て MI。これに Table への書き込みロールを与える。
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      node_version = "20"
    }
  }

  app_settings = {
    # メモ Table の名前（azurerm_storage_table.memos と一致）。
    "MEMO_TABLE_NAME" = azurerm_storage_table.memos.name

    # メモ Table のエンドポイント。Function は MEMO_STORAGE_ACCOUNT_URL があれば
    # キー文字列ではなく MI（DefaultAzureCredential）でここへ繋ぐ（memoStore.js 参照）。
    "MEMO_STORAGE_ACCOUNT_URL" = azurerm_storage_account.memos.primary_table_endpoint

    # EasyAuth を有効化したとき（= memo_api_app_id が設定済み）だけ app role 検証を行う。
    # 空のときは false にして、保護なしで疎通だけ試せるようにする（グレースフル）。
    "MEMO_REQUIRE_AUTH"  = var.memo_api_app_id == "" ? "false" : "true"
    "MEMO_REQUIRED_ROLE" = var.memo_required_role
  }

  # EasyAuth（App Service 認証）。memo_api_app_id が空なら丸ごと無効（dynamic で出し分け）。
  # 設定済みなら、aud = api://<appId> の Entra トークンだけを通し、未認証は 401 を返す。
  dynamic "auth_settings_v2" {
    for_each = var.memo_api_app_id == "" ? [] : [1]
    content {
      auth_enabled           = true
      require_authentication = true
      unauthenticated_action = "Return401"

      active_directory_v2 {
        client_id            = var.memo_api_app_id
        tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
        # このアプリ（api://<appId>）宛てのトークンだけを受け付ける。
        allowed_audiences = ["api://${var.memo_api_app_id}"]
      }

      login {}
    }
  }

  https_only = true
  tags       = var.tags
}

# ============================================================================
# ロール割り当て: Function の MI → Table Storage（キーレス読み書き）
# ============================================================================
# "Storage Table Data Contributor" は Table のエンティティ CRUD に必要なデータ平面ロール。
resource "azurerm_role_assignment" "func_table_contributor" {
  scope                = azurerm_storage_account.memos.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.memos.identity[0].principal_id
}
