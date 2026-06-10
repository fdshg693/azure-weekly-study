# ============================================================================
# Log Analytics Workspace + Application Insights（Reader / Writer 共有）
# ============================================================================
# Application Insights は 2018 年以降「Workspace-based モード」が標準で、
# 内部的に Log Analytics Workspace にテレメトリを書き込む。
# このプロジェクトは Workspace ごと Terraform で作成して自己完結させる。

# ----------------------------------------------------------------------------
# Log Analytics Workspace
# ----------------------------------------------------------------------------
# SKU = PerGB2018: 取り込み量に応じた課金（無料枠あり: 5 GB/月 まで無料）
# retention_in_days: ログ保持期間（30〜730 日）

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Application Insights（Reader / Writer 共有）
# ----------------------------------------------------------------------------
# 2 つの Function App のテレメトリを 1 つの App Insights に集約する。
# どちらの関数がどう呼ばれたかは cloud_RoleName で識別できる。

resource "azurerm_application_insights" "func" {
  name                = var.application_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  application_type = "web"

  # Workspace-based モード：上で作成した Log Analytics Workspace に紐付け
  # （一度設定すると classic モードへの戻し不可。新規プロジェクトはこれが推奨）
  workspace_id = azurerm_log_analytics_workspace.main.id

  tags = var.tags
}
