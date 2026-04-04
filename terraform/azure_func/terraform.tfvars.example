# ============================================================================
# 開発環境（Development）用の Terraform 変数設定ファイル
# ============================================================================
# 使用方法: terraform apply -var-file="terraform.dev.tfvars"

# リソースグループ名（開発環境用）
resource_group_name = "rg-azure-func-dev"

# デプロイするリージョン（開発用：日本東部）
location = "Japan East"

# Function App 用 Storage Account 名（グローバルで一意である必要があります）
storage_account_name = "stfuncdev001seiwan"

# Function App 名（グローバルで一意である必要があります）
function_app_name = "func-simple-dev-seiwan"

# Python ランタイムバージョン
python_version = "3.11"

# App Service Plan 名
service_plan_name = "plan-func-dev-seiwan"

# App Service Plan SKU（開発環境: Consumption プランでコスト最適化）
# Y1 = Consumption（サーバーレス）: 無料枠あり
service_plan_sku = "Y1"

# Application Insights 名
application_insights_name = "appi-func-dev-seiwan"

# Function App ソースコードのパス
function_app_source_dir = "../../azure_func/projects/simple"

# タグ（リソース管理用）
tags = {
  Environment = "Development"
  Project     = "AzureFunctionsDemo"
  ManagedBy   = "Terraform"
  CostCenter  = "Development"
}
