# ============================================================================
# App Service Plan（Linux Consumption / Y1）
# ============================================================================
# サーバーレスの従量課金プラン。Blob トリガーはアップロードを検知したときだけ
# 関数を起動するので、Consumption Plan と相性が良い。

resource "azurerm_service_plan" "func" {
  name                = var.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  os_type  = "Linux"
  sku_name = "Y1" # Consumption（サーバーレス）

  tags = var.tags
}
