# ============================================================================
# Log Analytics Workspace + Application Insights
# ============================================================================
# 関数の実行ログ（logging.info(...)）やトリガーの発火状況を確認するために使う。
# Blob トリガーは「ポーリングでいつ発火したか」を追いづらいので、
# App Insights のトレースを見られるようにしておくと学習がはかどる。

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days

  tags = var.tags
}

resource "azurerm_application_insights" "func" {
  name                = var.application_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  application_type = "web"

  # Workspace-based モード（2018 年以降の標準）
  workspace_id = azurerm_log_analytics_workspace.main.id

  tags = var.tags
}
