# ============================================================================
# App Service Plan（関数ホスティングプラン）の定義
# ============================================================================
# Azure Functionsの実行基盤となるホスティングプランを定義します
#
# プランの種類:
#   - Consumption (Y1): サーバーレス、使った分だけ課金
#     無料枠: 月100万回実行、400,000 GB-s
#     コールドスタートあり（数秒の遅延が発生する場合がある）
#   - Elastic Premium (EP1-EP3): 常時ウォーム、VNet統合、より大きなインスタンス
#   - Dedicated (B1, S1等): App Serviceプランを共有、予測可能なコスト

resource "azurerm_service_plan" "func" {
  name                = var.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # os_type: Azure Functions (Python) は Linux のみサポート
  os_type = "Linux"

  # sku_name: 価格プランの SKU
  # Y1 = Consumption（サーバーレス）プラン
  sku_name = var.service_plan_sku

  tags = var.tags
}
