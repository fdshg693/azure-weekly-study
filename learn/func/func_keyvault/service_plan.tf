# ============================================================================
# App Service Plan（Reader / Writer 共有 / Linux Consumption / Y1）
# ============================================================================
# Consumption Plan は Function App ごとに専用である必要はなく、複数の Function
# App が同じプランを共有できる。Reader / Writer は同じ実行特性で十分なので
# 1 つのプランにまとめる。

resource "azurerm_service_plan" "func" {
  name                = var.service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  os_type  = "Linux"
  sku_name = "Y1" # Consumption（サーバーレス）

  tags = var.tags
}
