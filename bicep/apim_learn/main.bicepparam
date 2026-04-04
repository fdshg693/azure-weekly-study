// ============================================================================
// パラメータファイル
// ============================================================================
// Git に入れてよい共通デフォルト値だけを置いてください
// 個人用設定や機密値を含む上書きは main.local.bicepparam を別途作成し、
// Git 管理対象にしないでください
//
// 使い方:
//   az deployment group create \
//     --resource-group rg-func-crud-dev \
//     --template-file main.bicep \
//     --parameters main.bicepparam

using './main.bicep'

// リソース名のプレフィックス（お好みで変更）
param prefix = 'apimlearn'

// Python のバージョン
param pythonVersion = '3.11'

// Consumption プラン（サーバーレス）
param servicePlanSku = 'Y1'

// API Management の SKU
param apimSkuName = 'Developer'

// Azure OpenAI リソースとモデルデプロイをあわせて作成し、APIM に追加する場合だけ true
param enableAzureOpenAiApi = false

// API Management の公開者情報
param apimPublisherName = 'Bicep CRUD Sample'
param apimPublisherEmail = 'noreply@example.com'

// タグ
param tags = {
  Environment: 'Development'
  Project: 'BicepFunctionsCRUD'
  ManagedBy: 'Bicep'
}
