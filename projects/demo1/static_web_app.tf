# ============================================================================
# Azure Static Web Apps の定義
# ============================================================================
# HTMX ベースの静的サイトを配信するためのリソース
# - HTML/CSS/JS を CDN 経由で配信
# - 別建ての Function App を CORS 越しに呼び出す（Bring-Your-Own-Functions は未使用）
#
# 注意: Static Web Apps は対応リージョンが限定されています
#   westus2 / centralus / eastus2 / westeurope / eastasia

resource "azurerm_static_web_app" "main" {
  name                = var.static_web_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.static_web_app_location

  # Free: 無料枠（個人/学習向け、カスタム認証や SLA なし）
  # Standard: 本番向け（カスタム認証、SLA、SnapShot 環境数増加）
  sku_tier = "Free"
  sku_size = "Free"

  tags = var.tags
}
