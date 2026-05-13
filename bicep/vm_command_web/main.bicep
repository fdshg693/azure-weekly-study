// ============================================================================
// VM Command Web (SvelteKit on App Service)
// ============================================================================
// ブラウザ → App Service (SvelteKit/SSR) → Function (vm_command_runner) → VM
//
// セキュリティモデル：
//   - App Service: Easy Auth (Microsoft Entra) でユーザー認証必須
//   - App Service の System-Assigned MI が Function の AAD トークンを取得
//   - Function (vm_command_runner) の Easy Auth は App Service の MI のみ許可
//   - 結果: Function を直接外部から叩く経路が存在しない
//
// デプロイ前提:
//   1. vm_command_runner を先にデプロイ済みであること
//   2. 2 つの AAD アプリ登録を事前に作成し、それぞれの clientId を取得済み
//        - func-aad-app  (Function 側 Easy Auth 用、audience 検証用)
//        - web-aad-app   (App Service 側 Easy Auth 用、ユーザーログイン用)
//      手順は README.md 参照。
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group <vm_command_web 用 RG> \
//     --template-file main.bicep \
//     --parameters main.local.bicepparam

targetScope = 'resourceGroup'

// ============================================================================
// パラメータ
// ============================================================================

@description('リージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス')
@minLength(1)
param prefix string = 'vmcmdweb'

@description('一意性のためのサフィックス')
param suffix string = uniqueString(resourceGroup().id)

@description('App Service Plan SKU')
@allowed(['B1', 'B2', 'S1', 'P0v3', 'P1v3'])
param appServicePlanSku string = 'B1'

@description('Node ランタイム')
@allowed(['18-lts', '20-lts'])
param nodeVersion string = '20-lts'

@description('既存 Function App (vm_command_runner) の名前')
param functionAppName string

@description('既存 Function App が存在するリソースグループ名')
param functionAppResourceGroup string

@description('Function App 用 AAD アプリ登録の clientId (サービス間認証用)')
param functionAadClientId string

@description('App Service 用 AAD アプリ登録の clientId (ユーザーログイン用)')
param webAadClientId string

@description('Microsoft Entra テナント ID')
param aadTenantId string = subscription().tenantId

@description('タグ')
param tags object = {
  Environment: 'Development'
  Project: 'VmCommandWeb'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 名前
// ============================================================================
var resourceNames = {
  appServicePlan: 'plan-${prefix}-${take(suffix, 8)}'
  webApp: 'app-${prefix}-${suffix}'
}

// ============================================================================
// モジュール
// ============================================================================
module plan './modules/app-service-plan.bicep' = {
  name: 'appServicePlan'
  params: {
    location: location
    planName: resourceNames.appServicePlan
    sku: appServicePlanSku
    tags: tags
  }
}

module web './modules/app-service.bicep' = {
  name: 'appService'
  params: {
    location: location
    webAppName: resourceNames.webApp
    appServicePlanId: plan.outputs.id
    nodeVersion: nodeVersion
    functionAppName: functionAppName
    functionAppResourceGroup: functionAppResourceGroup
    functionAadClientId: functionAadClientId
    webAadClientId: webAadClientId
    aadTenantId: aadTenantId
    tags: tags
  }
}

// Function 側 Easy Auth を App Service の MI のみ許可するように設定
module funcAuth './modules/function-easyauth.bicep' = {
  name: 'functionEasyAuth'
  scope: resourceGroup(functionAppResourceGroup)
  params: {
    functionAppName: functionAppName
    functionAadClientId: functionAadClientId
    aadTenantId: aadTenantId
    allowedPrincipalObjectId: web.outputs.principalId
  }
}

// ============================================================================
// 出力
// ============================================================================
@description('App Service 名')
output webAppName string = web.outputs.name

@description('App Service URL')
output webAppUrl string = web.outputs.url

@description('App Service MI Object ID (Function Easy Auth に登録されたもの)')
output webAppPrincipalId string = web.outputs.principalId

@description('SvelteKit コードを zip デプロイするコマンド (ローカルで build 済みの前提)')
output deployCommand string = 'cd svelte && npm run build && cd build && zip -r ../app.zip . && cd .. && az webapp deploy --resource-group ${resourceGroup().name} --name ${web.outputs.name} --src-path app.zip --type zip'
